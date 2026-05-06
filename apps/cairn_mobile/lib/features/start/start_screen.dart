/// Screen 1 — **Start** (production dashboard).
///
/// Auto-manages the Gemma model lifecycle: loads on entry, unloads on dispose.
/// The model picker is hidden behind a settings gear. "Start building
/// screening" is the single primary action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/llm/gemma_session.dart';
import '../../core/llm/model_registry.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/storage/file_draft_persistence.dart';

class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  GemmaLoadProgress? _progress;
  Object? _error;
  bool _busy = false;
  bool _modelReady = false;

  bool _draftChecking = true;
  bool _draftAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkForDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoadModel());
  }

  Future<void> _checkForDraft() async {
    final dp = ref.read(draftPersistenceProvider);
    final has = await dp.hasActiveDraft();
    if (!mounted) return;
    setState(() {
      _draftAvailable = has;
      _draftChecking = false;
    });
  }

  Future<void> _resumeDraft() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final dp = ref.read(draftPersistenceProvider);
      final meta = await dp.loadDraftMeta();
      if (meta == null) {
        setState(() {
          _draftAvailable = false;
          _busy = false;
        });
        return;
      }
      final draft = await restoreDraftWithBytes(meta);
      if (!mounted) return;
      if (draft == null) {
        await dp.clearDraft();
        setState(() {
          _draftAvailable = false;
          _busy = false;
        });
        return;
      }
      ref.read(sessionControllerProvider.notifier).restoreDraft(draft);

      if (!mounted) return;
      // Navigate to photos if images already exist in draft, else start from
      // location so the volunteer can confirm/skip GPS before capturing.
      final dest =
          draft.photos.isNotEmpty ? AppRoutes.photos : AppRoutes.location;
      context.go(dest);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _discardDraft() async {
    await ref.read(draftPersistenceProvider).clearDraft();
    if (!mounted) return;
    setState(() => _draftAvailable = false);
  }

  Future<void> _autoLoadModel() async {
    final session = ref.read(gemmaSessionProvider);
    if (session != null) {
      if (!mounted) return;
      setState(() => _modelReady = true);
      return;
    }
    // Don't fully load the model here — PhotosScreen owns the model lifecycle
    // and will load it when needed for describe-all. Pre-loading here wastes
    // ~1.5 GB GPU RAM that PhotosScreen immediately unloads to prevent OOM
    // during camera capture (BUG-3).
    //
    // Instead, just mark as ready so the user can start a session.
    // The model will be loaded on-demand in PhotosScreen._describeAll().
    if (!mounted) return;
    setState(() => _modelReady = true);
  }

  void _startSession() {
    final spec = ref.read(selectedModelSpecProvider);
    ref.read(sessionControllerProvider.notifier).startNew(
          modelName: 'gemma-4-${spec.key}-it',
          modelQuant: spec.quant,
          localeBCP47: 'en-US',
        );
    context.go(AppRoutes.location);
  }

  void _showSettings(BuildContext context) {
    final modelKey = ref.read(selectedModelKeyProvider);
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Model', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: modelKey,
              isExpanded: true,
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) {
                        ref.read(selectedModelKeyProvider.notifier).state = v;
                        Navigator.pop(context);
                      }
                    },
              items: [
                for (final m in models.values)
                  DropdownMenuItem(value: m.key, child: Text(m.display)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = ref.watch(selectedModelSpecProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cairn'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Post-earthquake building screening',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'FEMA P-154 Level 1 sidewalk survey. Preliminary screening only — '
                'this is not an engineer’s placard.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              if (!_draftChecking && _draftAvailable)
                _DraftBanner(
                  onResume: _busy ? null : _resumeDraft,
                  onDiscard: _busy ? null : _discardDraft,
                ),
              const SizedBox(height: 24),
              _ModelStatus(
                ready: _modelReady,
                busy: _busy,
                progress: _progress,
                error: _error,
                specDisplay: spec.display,
                onRetry: _autoLoadModel,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Start building screening',
                        style: TextStyle(fontSize: 18)),
                  ),
                  onPressed: _busy ? null : _startSession,
                ),
              ),
              const SizedBox(height: 16),
              const _RecentReports(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelStatus extends StatelessWidget {
  const _ModelStatus({
    required this.ready,
    required this.busy,
    required this.progress,
    required this.error,
    required this.specDisplay,
    required this.onRetry,
  });

  final bool ready;
  final bool busy;
  final GemmaLoadProgress? progress;
  final Object? error;
  final String specDisplay;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ready
            ? Colors.green.shade50
            : error != null
                ? Colors.red.shade50
                : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ready
              ? Colors.green.shade300
              : error != null
                  ? Colors.red.shade300
                  : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline
                    : busy
                        ? Icons.downloading_outlined
                        : error != null
                            ? Icons.error_outline
                            : Icons.hourglass_empty,
                size: 20,
                color: ready
                    ? Colors.green.shade700
                    : error != null
                        ? Colors.red.shade700
                        : cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                ready
                    ? '$specDisplay \u2014 ready'
                    : busy
                        ? 'Preparing $specDisplay\u2026'
                        : error != null
                            ? 'Model error'
                            : 'Model not loaded',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ready ? Colors.green.shade800 : cs.onSurface,
                ),
              ),
              const Spacer(),
              if (error != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          if (busy && progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: 4),
            Text(
              '${progress!.phase}: ${(progress!.fraction * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              '$error',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentReports extends ConsumerWidget {
  const _RecentReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(evidenceVaultProvider);
    return FutureBuilder(
      future: vault.listPackets(),
      builder: (_, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No reports yet.',
                style: TextStyle(color: Colors.black54)),
          );
        }
        final fmt = DateFormat.yMMMd().add_jm();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Recent reports',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            for (final s in items.take(5))
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor:
                      _bandColor(s.priorityBand).withValues(alpha: 0.2),
                  foregroundColor: _bandColor(s.priorityBand),
                  child: Text('${s.priorityScore}'),
                ),
                title: Text('${s.priorityBand} — ${s.buildingType}'),
                subtitle: Text(
                    '${fmt.format(s.createdAtUtc.toLocal())}  ·  ${s.locale}'),
              ),
          ],
        );
      },
    );
  }

  Color _bandColor(String band) => switch (band) {
        'CRITICAL' => Colors.red,
        'HIGH' => Colors.orange,
        'MEDIUM' => Colors.amber,
        _ => Colors.green,
      };
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.onResume, required this.onDiscard});
  final VoidCallback? onResume;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: const Color(0xFF1976D2).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.restore_outlined, color: Color(0xFF1565C0)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unsaved session found',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0))),
                  Text('You have an in-progress screening. Resume or discard.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1565C0))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onDiscard,
              child: const Text('Discard',
                  style: TextStyle(color: Color(0xFF1565C0))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
              onPressed: onResume,
              child: const Text('Resume'),
            ),
          ],
        ),
      );
}
