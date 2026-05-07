library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/routing/app_router.dart';
import '../../core/storage/evidence_vault.dart';
import '../../core/theme/cairn_theme.dart';
import '../../core/providers.dart';

class SavedScreeningsScreen extends ConsumerWidget {
  const SavedScreeningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(evidenceVaultProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Screenings')),
      body: SafeArea(
        child: FutureBuilder<List<PacketSummary>>(
          future: vault.listPackets(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return const _EmptySavedState();
            }
            return RefreshIndicator(
              onRefresh: () async {
                await vault.listPackets();
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = items[index];
                  return _PacketSummaryTile(
                    summary: item,
                    onTap: () => context.push(
                      AppRoutes.packetPath(item.packetId),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PacketSummaryTile extends StatelessWidget {
  const _PacketSummaryTile({required this.summary, required this.onTap});

  final PacketSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_jm();
    final address = summary.addressText.trim().isEmpty
        ? summary.locale
        : summary.addressText.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor:
              CairnColors.forBand(summary.priorityBand).withValues(alpha: 0.14),
          foregroundColor: CairnColors.forBand(summary.priorityBand),
          child: Text('${summary.priorityScore}'),
        ),
        title: Text(
          '${summary.priorityBand} - ${_buildingLabel(summary.buildingType)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${fmt.format(summary.createdAtUtc.toLocal())}\n'
          '$address - ${summary.photoCount} photos - '
          '${summary.hasReportPdf ? 'PDF ready' : 'PDF not saved'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _EmptySavedState extends StatelessWidget {
  const _EmptySavedState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text('No saved screenings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'Completed packets will appear here with photos, JSON, PDF, '
                'and model turn logs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
}

String _buildingLabel(String type) => type
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
