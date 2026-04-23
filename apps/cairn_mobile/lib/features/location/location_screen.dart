/// Screen 2 — **Location & building typology**.
///
/// Auto-resolves device GPS via `geolocator`, optional reverse geocode for an
/// address line, then asks the volunteer to pick a typology chip + a story
/// count. Writes both into the live `SessionDraft`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

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
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  String _typology = 'wood_light_frame';
  int _stories = 2;
  String _address = '';
  GeoLocation? _loc;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // permission gate — geolocator handles the platform-specific dance
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final asked = await Geolocator.requestPermission();
        if (asked == LocationPermission.denied ||
            asked == LocationPermission.deniedForever) {
          throw StateError('location permission denied');
        }
      } else if (perm == LocationPermission.deniedForever) {
        throw StateError('location permission permanently denied');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      String address = '';
      try {
        final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          address = [p.street, p.locality, p.administrativeArea, p.country]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
        }
      } catch (_) {
        // Reverse geocode is best-effort; ignore on failure.
      }

      setState(() {
        _loc = GeoLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracyMeters: pos.accuracy,
          addressText: address,
        );
        _address = address;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _continue() {
    final loc = _loc;
    if (loc == null) return;
    final controller = ref.read(sessionControllerProvider.notifier);
    controller.setLocation(loc.copyWithAddress(_address));
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
      // No active session — bounce to start.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.go(AppRoutes.start));
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
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('GPS error: $_error',
                      style: TextStyle(color: Colors.red.shade700)),
                ),
              if (_loc != null) ...[
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
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _resolveLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-acquire GPS'),
              ),
              const Divider(height: 32),
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
                    onPressed: _stories > 1
                        ? () => setState(() => _stories--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_stories',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  IconButton(
                    onPressed: _stories < 30
                        ? () => setState(() => _stories++)
                        : null,
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
}

extension on GeoLocation {
  GeoLocation copyWithAddress(String address) => GeoLocation(
        lat: lat,
        lng: lng,
        accuracyMeters: accuracyMeters,
        addressText: address,
      );
}

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
