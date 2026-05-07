library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dev_model/dev_scenario.dart';
import '../../core/llm/gemma_session.dart';
import '../../core/providers.dart';

class DevModelTestScreen extends ConsumerStatefulWidget {
  const DevModelTestScreen({super.key});

  @override
  ConsumerState<DevModelTestScreen> createState() => _DevModelTestScreenState();
}

class _DevModelTestScreenState extends ConsumerState<DevModelTestScreen> {
  final _scenarios = loadBuiltInDevScenarios();
  final _results = <String, DevScenarioRunResult>{};
  Object? _error;
  String? _runningId;
  GemmaLoadProgress? _loadProgress;

  Future<void> _ensureVisionModelLoaded() async {
    if (ref.read(gemmaSessionProvider) != null) return;
    await ref.read(gemmaSessionProvider.notifier).load(
          profile: SessionProfile.vision,
          onProgress: (progress) {
            if (mounted) setState(() => _loadProgress = progress);
          },
        );
  }

  Future<void> _runScenario(DevScenario scenario) async {
    setState(() {
      _runningId = scenario.scenarioId;
      _error = null;
      _loadProgress = null;
    });
    try {
      await _ensureVisionModelLoaded();
      final orchestrator = ref.read(orchestratorProvider);
      if (orchestrator == null) {
        throw StateError('Gemma orchestrator is not loaded.');
      }
      final result = await runDevScenario(
        scenario: scenario,
        orchestrator: orchestrator,
        bundle: rootBundle,
      );
      if (!mounted) return;
      setState(() => _results[scenario.scenarioId] = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _runningId = null);
    }
  }

  Future<void> _runAll() async {
    for (final scenario in _scenarios) {
      await _runScenario(scenario);
      if (_error != null) break;
    }
  }

  Future<void> _exportResults() async {
    final payload = {
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'results': [for (final result in _results.values) result.toJson()],
    };
    final name =
        'dev_model_eval_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json';
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/json',
          name: name,
          length: bytes.length,
        ),
      ],
      subject: 'Cairn developer model evaluation',
      fileNameOverrides: [name],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _runningId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Model Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'On-device Gemma 4 scenario runner',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Runs the real 4-photo describeAll path and computes pass/fail '
              'from deterministic evaluator metrics.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_loadProgress != null)
              LinearProgressIndicator(value: _loadProgress!.fraction),
            if (_error != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                'Error: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _runAll,
                    icon: const Icon(Icons.playlist_play),
                    label: const Text('Run all scenarios'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Export results',
                  onPressed: _results.isEmpty || busy ? null : _exportResults,
                  icon: const Icon(Icons.ios_share),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final scenario in _scenarios)
              _ScenarioCard(
                scenario: scenario,
                result: _results[scenario.scenarioId],
                running: _runningId == scenario.scenarioId,
                onRun: busy ? null : () => _runScenario(scenario),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.result,
    required this.running,
    required this.onRun,
  });

  final DevScenario scenario;
  final DevScenarioRunResult? result;
  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(scenario.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (result != null)
                  Icon(
                    result.passed ? Icons.check_circle : Icons.cancel_outlined,
                    color: result.passed ? Colors.green : Colors.red,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${scenario.expected.priorityBand} expected - '
              '${scenario.photos.length} photos - ${scenario.building.type}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (running)
              const LinearProgressIndicator()
            else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onRun,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run'),
                ),
              ),
            if (result != null) ...[
              const Divider(height: 20),
              _MetricRow('Understands damage', result.understandsDamage),
              _MetricRow('Severity close', result.severityClose),
              _MetricRow('Priority band correct',
                  result.priorityBand == scenario.expected.priorityBand),
              _MetricRow('Any schema failures', result.schemaFailureCount == 0),
              Text(
                'Vision score ${result.visionUnderstandingScore.toStringAsFixed(2)} - '
                '${result.priorityBand} ${result.priorityScore}/10 - '
                '${result.totalWallclockMs} ms',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final photo in result.photoEvals)
                Text(
                  '${photo.slot}: tags=${photo.observedTags.join(', ')} '
                  'jaccard=${photo.tagJaccard.toStringAsFixed(2)} '
                  'severityDelta=${photo.severityBucketDelta}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.pass);

  final String label;
  final bool pass;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(
              pass ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 16,
              color: pass ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}
