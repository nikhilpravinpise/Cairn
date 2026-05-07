package app.cairn.cairn_mobile

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.SamplerConfig
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var engine: Engine? = null
    private var conversation: Conversation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.cairn/native_mtp_gemma"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> scope.launch {
                    runCatching {
                        createNativeSession(
                            modelPath = call.argument<String>("modelPath")!!,
                            systemPrompt = call.argument<String>("systemPrompt") ?: "",
                            topK = call.argument<Int>("topK") ?: 40,
                            topP = call.argument<Double>("topP") ?: 0.95,
                            temperature = call.argument<Double>("temperature") ?: 0.1,
                            enableMtp = call.argument<Boolean>("enableMtp") ?: true,
                            enableVision = call.argument<Boolean>("enableVision") ?: true,
                        )
                    }.fold(
                        onSuccess = { withContext(Dispatchers.Main) { result.success(null) } },
                        onFailure = { error ->
                            withContext(Dispatchers.Main) {
                                result.error("native_mtp_create", error.message, error.stackTraceToString())
                            }
                        },
                    )
                }
                "generate" -> scope.launch {
                    runCatching {
                        generateNative(
                            text = call.argument<String>("text") ?: "",
                            images = call.argument<List<ByteArray>>("images") ?: emptyList(),
                        )
                    }.fold(
                        onSuccess = { payload ->
                            withContext(Dispatchers.Main) { result.success(payload) }
                        },
                        onFailure = { error ->
                            withContext(Dispatchers.Main) {
                                result.error("native_mtp_generate", error.message, error.stackTraceToString())
                            }
                        },
                    )
                }
                "close" -> scope.launch {
                    closeNativeSession()
                    withContext(Dispatchers.Main) { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.cairn/storage_health"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "availableBytes" -> {
                    val stat = StatFs(filesDir.absolutePath)
                    result.success(stat.availableBytes)
                }
                else -> result.notImplemented()
            }
        }
    }

    @OptIn(ExperimentalApi::class)
    private fun createNativeSession(
        modelPath: String,
        systemPrompt: String,
        topK: Int,
        topP: Double,
        temperature: Double,
        enableMtp: Boolean,
        enableVision: Boolean,
    ) {
        closeNativeSession()
        ExperimentalFlags.enableSpeculativeDecoding = enableMtp
        val newEngine = Engine(
            EngineConfig(
                modelPath = modelPath,
                backend = Backend.GPU(),
                visionBackend = if (enableVision) Backend.GPU() else Backend.CPU(),
                cacheDir = cacheDir.path,
            )
        )
        newEngine.initialize()
        val config = ConversationConfig(
            systemInstruction = Contents.of(systemPrompt),
            samplerConfig = SamplerConfig(
                topK = topK,
                topP = topP,
                temperature = temperature,
            ),
        )
        engine = newEngine
        conversation = newEngine.createConversation(config)
    }

    @OptIn(ExperimentalApi::class)
    private suspend fun generateNative(
        text: String,
        images: List<ByteArray>,
    ): Map<String, Any> {
        val activeConversation =
            conversation ?: throw IllegalStateException("native_mtp session is not loaded")
        val startedAt = System.nanoTime()
        var ttftMs: Long? = null
        val output = StringBuilder()
        val contents = if (images.isEmpty()) {
            Contents.of(text)
        } else {
            val parts = images.map { Content.ImageBytes(it) } + Content.Text(text)
            Contents.of(*parts.toTypedArray())
        }
        activeConversation.sendMessageAsync(contents).collect { message ->
            if (ttftMs == null) {
                ttftMs = (System.nanoTime() - startedAt) / 1_000_000
            }
            output.append(activeConversation.renderMessageIntoString(message))
        }
        val wallclockMs = (System.nanoTime() - startedAt) / 1_000_000
        return mapOf(
            "text" to output.toString(),
            "thinking" to "",
            "ttftMs" to (ttftMs ?: wallclockMs),
            "wallclockMs" to wallclockMs,
        )
    }

    private fun closeNativeSession() {
        conversation?.close()
        conversation = null
        engine?.close()
        engine = null
    }

    override fun onDestroy() {
        closeNativeSession()
        scope.cancel()
        super.onDestroy()
    }
}
