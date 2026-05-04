/// Screen 1 — **Start**.
///
/// Choose a model, load it (one-time per session), then tap "Start screening"
/// to begin the FEMA P-154 walk-through. Recent reports list lives at the
/// bottom (lifted from the vault).
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

  bool _draftChecking = true;
  bool _draftAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkForDraft();
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

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await ref.read(gemmaSessionProvider.notifier).load(
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _progress = p);
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unload() async {
    await ref.read(gemmaSessionProvider.notifier).unload();
    if (!mounted) return;
    setState(() => _progress = null);
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(gemmaSessionProvider);
    final modelKey = ref.watch(selectedModelKeyProvider);
    final loaded = session != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cairn'),
        actions: [
          IconButton(
            tooltip: 'S2 spike',
            onPressed: () => context.push(AppRoutes.spike),
            icon: const Icon(Icons.science_outlined),
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
              _ModelPicker(
                value: modelKey,
                enabled: !loaded && !_busy,
                onChanged: (k) =>
                    ref.read(selectedModelKeyProvider.notifier).state = k,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_outlined),
                    label: Text(loaded ? 'Model loaded' : 'Load model'),
                    onPressed: loaded || _busy ? null : _load,
                  ),
                  const SizedBox(width: 8),
                  if (loaded)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _unload,
                      icon: const Icon(Icons.eject_outlined),
                      label: const Text('Unload'),
                    ),
                ],
              ),
              if (_busy && _progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress!.fraction),
                const SizedBox(height: 4),
                Text(
                  '${_progress!.phase}: '
                  '${(_progress!.fraction * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.shade50,
                  child: SelectableText('$_error',
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
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

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Model',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: !enabled ? null : (v) => v == null ? null : onChanged(v),
          items: [
            for (final m in models.values)
              DropdownMenuItem(value: m.key, child: Text(m.display)),
          ],
        ),
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
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
          border: Border.all(color: const Color(0xFF1976D2).withValues(alpha: 0.4)),
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
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF1565C0))),
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
