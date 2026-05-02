/// Screen 2 — **Location & building typology**.
///
/// Resolves device GPS via [resolveLocation], handles all four error kinds
/// (denied, denied-forever, services-disabled, timeout) with distinct UI and
/// actionable CTAs. Provides a **Skip GPS** escape hatch so the volunteer can
/// continue without location when permission is permanently denied or when
/// on-site conditions prevent a fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/location/location_service.dart';
import '../../core/models/evidence_packet.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';

const _typologies = <String, String>{
  'wood_light_frame': 'Wood light frame',
  'unreinforced_masonry': 'Unreinforced masonry',
  'concrete_moment_frame': 'Concrete moment frame',
  'steel': 'Steel',
  'mixed': 'Mixed',
  'unknown': 'Unknown',
};

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key, this.resolverOverride});

  /// Injectable resolver — set in widget tests to avoid platform calls.
  final LocationResolver? resolverOverride;

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  String _typology = 'wood_light_frame';
  int _stories = 2;
  String _address = '';

  /// Non-null once GPS resolves or the user taps "Skip GPS".
  GeoLocation? _loc;

  bool _busy = false;
  LocationFailure? _locationError;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  Future<void> _acquire() async {
    setState(() {
      _busy = true;
      _locationError = null;
    });
    final result = await resolveLocation(
      resolver:
          widget.resolverOverride ?? const GeolocatorLocationResolver(),
    );
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        _loc = result.location;
        _address = result.location!.addressText;
        _busy = false;
      });
    } else {
      setState(() {
        _locationError = result as LocationFailure;
        _busy = false;
      });
    }
  }

  void _skipGps() {
    setState(() {
      _loc = kSkippedGeoLocation;
      _locationError = null;
      _address = '';
    });
  }

  void _continue() {
    final loc = _loc;
    if (loc == null) return;
    final controller = ref.read(sessionControllerProvider.notifier);
    // Preserve the skip-GPS sentinel address; only override for live fixes.
    final finalLoc = isSkippedLocation(loc)
        ? loc
        : GeoLocation(
            lat: loc.lat,
            lng: loc.lng,
            accuracyMeters: loc.accuracyMeters,
            addressText: _address.isNotEmpty ? _address : loc.addressText,
          );
    controller.setLocation(finalLoc);
    controller.setBuilding(BuildingInfo(
      type: _typology,
      storiesAboveGrade: _stories,
    ));
    context.push(AppRoutes.photos);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.start);
      });
      return const Scaffold();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Location & building')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Where are you?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              // ── Status / error ───────────────────────────────────────────
              if (_busy) const LinearProgressIndicator(),

              if (_locationError != null)
                _LocationErrorCard(
                  failure: _locationError!,
                  onRetry: _locationError!.kind.canRetryInApp ? _acquire : null,
                  onOpenSettings: _locationError!.kind.requiresSettings
                      ? _openSettings
                      : null,
                  onSkip: _skipGps,
                ),

              // ── Skipped sentinel banner ──────────────────────────────────
              if (_loc != null && isSkippedLocation(_loc!))
                _SkippedLocationBanner(onReacquire: _acquire),

              // ── Live location card + address edit ────────────────────────
              if (_loc != null && !isSkippedLocation(_loc!)) ...[
                _LocationCard(loc: _loc!),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _address,
                  decoration: const InputDecoration(
                    labelText: 'Address (correct if needed)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _address = v,
                ),
              ],

              // ── Re-acquire + skip controls ───────────────────────────────
              if (_locationError == null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _acquire,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-acquire GPS'),
                    ),
                    if (_loc == null && !_busy)
                      TextButton(
                        onPressed: _skipGps,
                        child: const Text('Skip GPS'),
                      ),
                  ],
                ),
              ],

              const Divider(height: 32),

              // ── Building typology ────────────────────────────────────────
              const Text('Building typology',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _typologies.entries)
                    ChoiceChip(
                      selected: _typology == entry.key,
                      label: Text(entry.value),
                      onSelected: (s) =>
                          s ? setState(() => _typology = entry.key) : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Stories above grade:'),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed:
                        _stories > 1 ? () => setState(() => _stories--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_stories',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  IconButton(
                    onPressed:
                        _stories < 30 ? () => setState(() => _stories++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loc == null ? null : _continue,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Continue', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (_locationError?.kind == LocationErrorKind.servicesDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await openAppSettings();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error card
// ─────────────────────────────────────────────────────────────────────────────

class _LocationErrorCard extends StatelessWidget {
  const _LocationErrorCard({
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onSkip,
  });

  final LocationFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failure.kind.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            failure.kind.guidance,
            style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (onRetry != null)
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(failure.kind == LocationErrorKind.timeout
                      ? 'Retry'
                      : 'Try Again'),
                ),
              if (onOpenSettings != null)
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text(
                    failure.kind == LocationErrorKind.servicesDisabled
                        ? 'Enable Location'
                        : 'Open Settings',
                  ),
                ),
              TextButton(
                onPressed: onSkip,
                child: const Text('Skip GPS'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skipped-GPS banner
// ─────────────────────────────────────────────────────────────────────────────

class _SkippedLocationBanner extends StatelessWidget {
  const _SkippedLocationBanner({required this.onReacquire});
  final VoidCallback onReacquire;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'GPS skipped — location will not be recorded in the packet.',
              style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
            ),
          ),
          TextButton(
            onPressed: onReacquire,
            child: const Text('Retry GPS'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live-location card
// ─────────────────────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.loc});
  final GeoLocation loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: Colors.green.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${loc.lat.toStringAsFixed(5)}, ${loc.lng.toStringAsFixed(5)}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
                Text('±${loc.accuracyMeters.toStringAsFixed(0)} m'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
