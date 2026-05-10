package app.cairn.cairn_mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
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
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var backendUsed: String = "none"
    private var speculativeDecodingRequested: Boolean = false
    private var speculativeDecodingAvailable: Boolean = false

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
                            maxTokens = call.argument<Int>("maxTokens") ?: 4096,
                            maxNumImages = call.argument<Int>("maxNumImages") ?: 1,
                            backend = call.argument<String>("backend") ?: "gpu",
                            visionBackend = call.argument<String>("visionBackend") ?: "gpu",
                            audioBackend = call.argument<String>("audioBackend") ?: "cpu",
                            enableMtp = call.argument<Boolean>("enableMtp") ?: true,
                            enableVision = call.argument<Boolean>("enableVision") ?: true,
                        )
                    }.fold(
                        onSuccess = { payload ->
                            withContext(Dispatchers.Main) { result.success(payload) }
                        },
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
                            timeoutMs = call.argument<Int>("timeoutMs") ?: 180_000,
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.cairn/image_preprocess"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "resizeJpeg" -> scope.launch {
                    runCatching {
                        resizeJpegForInference(
                            bytes = call.argument<ByteArray>("bytes")
                                ?: throw IllegalArgumentException("bytes is required"),
                            maxLongEdgePx = call.argument<Int>("maxLongEdgePx") ?: 640,
                            quality = call.argument<Int>("quality") ?: 82,
                        )
                    }.fold(
                        onSuccess = { payload ->
                            withContext(Dispatchers.Main) { result.success(payload) }
                        },
                        onFailure = { error ->
                            withContext(Dispatchers.Main) {
                                result.error(
                                    "image_preprocess_resize_jpeg",
                                    error.message,
                                    error.stackTraceToString(),
                                )
                            }
                        },
                    )
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
        maxTokens: Int,
        maxNumImages: Int,
        backend: String,
        visionBackend: String,
        audioBackend: String,
        enableMtp: Boolean,
        enableVision: Boolean,
    ): Map<String, Any> {
        closeNativeSession()
        speculativeDecodingRequested = enableMtp
        ExperimentalFlags.enableSpeculativeDecoding = enableMtp
        ExperimentalFlags.enableBenchmark = true
        // NOTE: speculativeDecodingAvailable reflects the flag we SET, not a confirmed
        // runtime state. LiteRT-LM 0.11.0 exposes no draft-acceptance counters.
        // Use lastDecodeTokensPerSecond A/B (MTP on vs off) to confirm MTP is active.
        speculativeDecodingAvailable = ExperimentalFlags.enableSpeculativeDecoding == true

        fun buildEngine(primaryBackend: String): Engine {
            return Engine(
                EngineConfig(
                    modelPath = modelPath,
                    backend = backendFromName(primaryBackend),
                    visionBackend = if (enableVision) {
                        backendFromName(visionBackend)
                    } else {
                        Backend.CPU()
                    },
                    audioBackend = backendFromName(audioBackend),
                    maxNumTokens = maxTokens,
                    maxNumImages = maxNumImages,
                    cacheDir = cacheDir.path,
                )
            )
        }

        val preferredBackend = normalizeBackendName(backend)
        val newEngine = try {
            buildEngine(preferredBackend).also {
                it.initialize()
                backendUsed = preferredBackend
            }
        } catch (error: Throwable) {
            if (preferredBackend != "gpu") throw error
            Log.w("Cairn/native_mtp", "GPU engine create failed; retrying CPU", error)
            buildEngine("cpu").also {
                it.initialize()
                backendUsed = "cpu"
            }
        }
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
        return mapOf(
            "backendUsed" to backendUsed,
            "speculativeDecodingRequested" to speculativeDecodingRequested,
            "speculativeDecodingAvailable" to speculativeDecodingAvailable,
            "gpuFallback" to (preferredBackend == "gpu" && backendUsed == "cpu"),
            "maxTokens" to maxTokens,
            "maxNumImages" to maxNumImages,
        )
    }

    @OptIn(ExperimentalApi::class)
    private suspend fun generateNative(
        text: String,
        images: List<ByteArray>,
        timeoutMs: Int,
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
        withTimeout(timeoutMs.toLong()) {
            activeConversation.sendMessageAsync(contents).collect { message ->
                if (ttftMs == null) {
                    ttftMs = (System.nanoTime() - startedAt) / 1_000_000
                }
                output.append(activeConversation.renderMessageIntoString(message))
            }
        }
        val wallclockMs = (System.nanoTime() - startedAt) / 1_000_000
        // ExperimentalFlags.enableBenchmark = true so BenchmarkInfo is populated.
        // Use hardware counters rather than output.length / 4 estimates.
        val bench = activeConversation.getBenchmarkInfo()
        val decodeTokenCount = bench.lastDecodeTokenCount.coerceAtLeast(1)
        val prefillTokenCount = bench.lastPrefillTokenCount
        val decodeTokS = bench.lastDecodeTokensPerSecond
        val prefillTokS = bench.lastPrefillTokensPerSecond
        // Use hardware TTFT when positive; fall back to wall-clock measurement.
        val realTtftMs: Long = if (bench.timeToFirstTokenInSecond > 0.0) {
            (bench.timeToFirstTokenInSecond * 1_000.0).toLong()
        } else {
            ttftMs ?: wallclockMs
        }
        return mapOf(
            "text" to output.toString(),
            "thinking" to "",
            "ttftMs" to realTtftMs,
            "wallclockMs" to wallclockMs,
            "backendUsed" to backendUsed,
            "outputTokenEstimate" to decodeTokenCount,
            "tokensPerSecond" to decodeTokS,
            "prefillTokenCount" to prefillTokenCount,
            "prefillTokS" to prefillTokS,
            "speculativeDecodingRequested" to speculativeDecodingRequested,
            "speculativeDecodingAvailable" to speculativeDecodingAvailable,
        )
    }

    private fun normalizeBackendName(name: String): String {
        return when (name.lowercase()) {
            "cpu" -> "cpu"
            else -> "gpu"
        }
    }

    private fun backendFromName(name: String): Backend {
        return when (normalizeBackendName(name)) {
            "cpu" -> Backend.CPU()
            else -> Backend.GPU()
        }
    }

    private fun closeNativeSession() {
        conversation?.close()
        conversation = null
        engine?.close()
        engine = null
        backendUsed = "none"
    }

    private fun resizeJpegForInference(
        bytes: ByteArray,
        maxLongEdgePx: Int,
        quality: Int,
    ): ByteArray {
        require(maxLongEdgePx > 0) { "maxLongEdgePx must be > 0" }
        require(quality in 1..100) { "quality must be 1..100" }

        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("unsupported image bytes")
        }

        val longEdge = maxOf(bounds.outWidth, bounds.outHeight)
        val sourceLooksJpeg = bytes.size >= 2 &&
            bytes[0] == 0xFF.toByte() &&
            bytes[1] == 0xD8.toByte()
        if (longEdge <= maxLongEdgePx && sourceLooksJpeg) {
            return bytes
        }

        val sampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, maxLongEdgePx)
        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOptions)
            ?: throw IllegalArgumentException("failed to decode image")

        val oriented = applyExifOrientation(decoded, bytes)
        if (oriented !== decoded) {
            decoded.recycle()
        }

        val orientedLongEdge = maxOf(oriented.width, oriented.height)
        val scaled = if (orientedLongEdge > maxLongEdgePx) {
            val scale = maxLongEdgePx.toFloat() / orientedLongEdge.toFloat()
            val targetWidth = maxOf(1, (oriented.width * scale).toInt())
            val targetHeight = maxOf(1, (oriented.height * scale).toInt())
            Bitmap.createScaledBitmap(oriented, targetWidth, targetHeight, true)
        } else {
            oriented
        }
        if (scaled !== oriented) {
            oriented.recycle()
        }

        return ByteArrayOutputStream().use { out ->
            val ok = scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
            scaled.recycle()
            if (!ok) throw IllegalStateException("failed to encode JPEG")
            out.toByteArray()
        }
    }

    private fun calculateInSampleSize(width: Int, height: Int, maxLongEdgePx: Int): Int {
        var sample = 1
        var sampledLongEdge = maxOf(width, height)
        while (sampledLongEdge / 2 >= maxLongEdgePx) {
            sample *= 2
            sampledLongEdge /= 2
        }
        return sample
    }

    private fun applyExifOrientation(bitmap: Bitmap, bytes: ByteArray): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    override fun onDestroy() {
        closeNativeSession()
        scope.cancel()
        super.onDestroy()
    }
}
