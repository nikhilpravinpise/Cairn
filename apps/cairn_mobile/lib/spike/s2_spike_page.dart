/// S2 spike page — 10 consecutive vision prompts on Gemma E4B (web target).
///
/// Web-first Week-1 build: no file I/O. The 10-prompt report is shown on the
/// page and offered as a download via `Clipboard.setData` + (on web) a
/// blob download helper.
///
/// Lives under `spike/` so the real Week-2 app (`features/`) never imports it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/llm/gemma_session.dart';
import '../core/llm/model_registry.dart';
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart'
    as web_download;

/// Provider for the S2 probe image loader.
///
/// Returns a callable that loads [assets/images/s2_probe.jpg] from the
/// asset bundle.  Override in tests to simulate missing-asset conditions
/// without a live asset bundle or device.  (Phase 10 — §1.8)
final probeImageLoaderProvider = Provider<Future<Uint8List> Function()>(
  (ref) => () async =>
      (await rootBundle.load('assets/images/s2_probe.jpg')).buffer.asUint8List(),
);

/// Public provider for the S2 spike controller.
///
/// Exposed (no leading `_`) so that [test/s2_spike_test.dart] can override
/// [probeImageLoaderProvider] and assert on state without needing a live
/// asset bundle or native model.  (Phase 10)
final spikeCtlProvider =
    NotifierProvider<_SpikeController, _SpikeState>(_SpikeController.new);

class _SpikeState {
  const _SpikeState({
    this.modelKey = 'e4b',
    this.loading = false,
    this.loadProgress,
    this.session,
    this.runs = const [],
    this.error,
    this.loraAttached = false,
    this.reportJson,
  });

  final String modelKey;
  final bool loading;
  final GemmaLoadProgress? loadProgress;
  final GemmaSession? session;
  final List<_RunRow> runs;
  final String? error;
  final bool loraAttached;
  final String? reportJson;

  _SpikeState copyWith({
    String? modelKey,
    bool? loading,
    GemmaLoadProgress? loadProgress,
    Object? session = const _Unset(),
    List<_RunRow>? runs,
    Object? error = const _Unset(),
    bool? loraAttached,
    Object? reportJson = const _Unset(),
  }) =>
      _SpikeState(
        modelKey: modelKey ?? this.modelKey,
        loading: loading ?? this.loading,
        loadProgress: loadProgress ?? this.loadProgress,
        session: session is _Unset ? this.session : session as GemmaSession?,
        runs: runs ?? this.runs,
        error: error is _Unset ? this.error : error as String?,
        loraAttached: loraAttached ?? this.loraAttached,
        reportJson:
            reportJson is _Unset ? this.reportJson : reportJson as String?,
      );
}

class _Unset {
  const _Unset();
}

class _RunRow {
  const _RunRow({
    required this.n,
    required this.ttftMs,
    required this.wallclockMs,
    required this.tokensOut,
    required this.ok,
    required this.parsedJson,
    required this.excerpt,
  });

  final int n;
  final int ttftMs;
  final int wallclockMs;
  final int tokensOut;
  final bool ok;
  final bool parsedJson;
  final String excerpt;

  Map<String, Object?> toJson() => {
        'n': n,
        'ttft_ms': ttftMs,
        'wallclock_ms': wallclockMs,
        'tokens_out': tokensOut,
        'ok': ok,
        'parsed_json': parsedJson,
        'excerpt': excerpt,
      };
}

class _SpikeController extends Notifier<_SpikeState> {
  static const _promptsToRun = 10;

  @override
  _SpikeState build() => const _SpikeState();

  void selectModel(String key) {
    if (state.session != null) return; // unload first
    state = state.copyWith(modelKey: key);
  }

  Future<void> loadModel({String? loraPath}) async {
    state = state.copyWith(loading: true, error: null, reportJson: null);
    try {
      final sys =
          await rootBundle.loadString('assets/prompts/system_prompt_v1.txt');
      final spec = models[state.modelKey];
      if (spec == null) {
        throw StateError('unknown model key ${state.modelKey}');
      }
      final session = await GemmaSession.open(
        spec,
        systemPrompt: sys,
        loraPath: loraPath,
        onProgress: (p) => state = state.copyWith(loadProgress: p),
      );
      state = state.copyWith(
        loading: false,
        session: session,
        loraAttached: loraPath != null,
        loadProgress: null,
      );
    } catch (e, st) {
      state = state.copyWith(loading: false, error: '$e\n$st');
    }
  }

  Future<void> unload() async {
    await state.session?.close();
    state = state.copyWith(
      session: null,
      runs: const [],
      loraAttached: false,
      reportJson: null,
    );
  }

  Future<void> runBurst() async {
    // Pre-flight: load the probe image BEFORE touching the session.
    // This surfaces a clean, actionable error instead of an unhandled
    // FlutterError when the operator-provided asset is absent. (Phase 10)
    Uint8List img;
    try {
      img = await ref.read(probeImageLoaderProvider)();
    } catch (e) {
      state = state.copyWith(
        error: 'S2 probe image not found.\n'
            'Place a JPEG at assets/images/s2_probe.jpg and rebuild the app.\n'
            'See apps/cairn_mobile/docs/s2_checklist.md for instructions.\n'
            '(Error: $e)',
      );
      return;
    }

    final session = state.session;
    if (session == null) {
      state = state.copyWith(error: 'load model first');
      return;
    }
    const userTurn =
        '{"task":"describe_photo","asked_in":"en","prompt_id":"fema_p154_q02_exterior_walls",'
        '"image_refs":["img-1"],"user_text":null}';

    final acc = <_RunRow>[...state.runs];
    for (var i = 1; i <= _promptsToRun; i++) {
      try {
        final r = await session.generate(userText: userTurn, image: img);
        var parsed = false;
        try {
          jsonDecode(r.text);
          parsed = true;
        } catch (_) {}
        acc.add(_RunRow(
          n: acc.length + 1,
          ttftMs: r.ttftMs,
          wallclockMs: r.wallclockMs,
          tokensOut: r.outputCharCount,
          ok: true,
          parsedJson: parsed,
          excerpt:
              r.text.length > 120 ? '${r.text.substring(0, 120)}…' : r.text,
        ));
      } catch (e) {
        acc.add(_RunRow(
          n: acc.length + 1,
          ttftMs: 0,
          wallclockMs: 0,
          tokensOut: 0,
          ok: false,
          parsedJson: false,
          excerpt: 'ERROR: $e',
        ));
      }
      state = state.copyWith(runs: List.unmodifiable(acc));
    }
    _buildReport();
  }

  void _buildReport() {
    final payload = {
      'schema': 'cairn.spike.s2.v1',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'model_key': state.modelKey,
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'lora_attached': state.loraAttached,
      'runs': [for (final r in state.runs) r.toJson()],
    };
    state = state.copyWith(
      reportJson: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  void copyReport() {
    final j = state.reportJson;
    if (j != null) Clipboard.setData(ClipboardData(text: j));
  }

  void downloadReport() {
    final j = state.reportJson;
    if (j == null) return;
    final stamp =
        DateTime.now().toUtc().toIso8601String().replaceAll(':', '').split('.')[0];
    web_download.downloadJson(j, 's2_report_$stamp.json');
  }
}

class S2SpikePage extends ConsumerWidget {
  const S2SpikePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(spikeCtlProvider);
    final ctl = ref.read(spikeCtlProvider.notifier);
    final loaded = s.session != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Cairn — S2 flutter_gemma spike (Android)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DropdownButton<String>(
                  value: s.modelKey,
                  onChanged: loaded
                      ? null
                      : (v) {
                          if (v != null) ctl.selectModel(v);
                        },
                  items: [
                    for (final m in models.values)
                      DropdownMenuItem(
                        value: m.key,
                        child: Text(m.display),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: s.loading || loaded ? null : () => ctl.loadModel(),
                  child: const Text('Load'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: loaded && !s.loading ? () => ctl.runBurst() : null,
                  child: const Text('Run 10 prompts'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: loaded ? () => ctl.unload() : null,
                  child: const Text('Unload'),
                ),
                const Spacer(),
                if (s.reportJson != null) ...[
                  IconButton(
                    tooltip: 'copy report JSON',
                    onPressed: ctl.copyReport,
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: 'download s2_report.json',
                    onPressed: ctl.downloadReport,
                    icon: const Icon(Icons.download),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (s.loading) _LoadStatus(progress: s.loadProgress),
            if (s.error != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade100,
                child: SelectableText(s.error!),
              ),
            const SizedBox(height: 12),
            Expanded(child: _RunsTable(runs: s.runs)),
            if (s.reportJson != null)
              Container(
                height: 140,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    s.reportJson!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadStatus extends StatelessWidget {
  const _LoadStatus({this.progress});
  final GemmaLoadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: p?.fraction),
        const SizedBox(height: 4),
        Text(
          p == null
              ? 'loading…'
              : '${p.phase}: ${(p.fraction * 100).toStringAsFixed(0)}%',
        ),
      ],
    );
  }
}

class _RunsTable extends StatelessWidget {
  const _RunsTable({required this.runs});
  final List<_RunRow> runs;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const Center(child: Text('no runs yet'));
    }
    return ListView.builder(
      itemCount: runs.length,
      itemBuilder: (_, i) {
        final r = runs[i];
        final bg = !r.ok
            ? Colors.red.shade50
            : r.parsedJson
                ? Colors.green.shade50
                : Colors.orange.shade50;
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              SizedBox(width: 32, child: Text('#${r.n}')),
              SizedBox(
                width: 160,
                child: Text('ttft ${r.ttftMs} ms / wall ${r.wallclockMs} ms'),
              ),
              SizedBox(width: 80, child: Text('${r.tokensOut} chars')),
              SizedBox(width: 80, child: Text(r.parsedJson ? 'JSON ✓' : 'JSON ✗')),
              Expanded(
                child: Text(
                  r.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
