/// Location resolution service — typed error model + injectable resolver.
///
/// Separates all Geolocator / Geocoding calls behind the [LocationResolver]
/// interface so tests can inject a [_MockLocationResolver] without any
/// platform channel. Production code calls [resolveLocation()] which defaults
/// to [GeolocatorLocationResolver].
library;

import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/evidence_packet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Error taxonomy
// ─────────────────────────────────────────────────────────────────────────────

/// All failure reasons [resolveLocation] can return.
enum LocationErrorKind {
  /// User has not yet granted permission but may be prompted again.
  denied,

  /// User permanently denied; must direct them to device Settings.
  deniedForever,

  /// Device location services (GPS / network) are switched off.
  servicesDisabled,

  /// No GPS fix received within the timeout window.
  timeout,

  /// Unexpected platform error; [LocationFailure.message] carries details.
  unknown,
}

extension LocationErrorKindX on LocationErrorKind {
  /// Short user-facing label.
  String get label => switch (this) {
        LocationErrorKind.denied => 'Permission denied',
        LocationErrorKind.deniedForever => 'Permission permanently denied',
        LocationErrorKind.servicesDisabled => 'Location services disabled',
        LocationErrorKind.timeout => 'GPS timed out',
        LocationErrorKind.unknown => 'Location error',
      };

  /// Actionable guidance shown below the label in the UI.
  String get guidance => switch (this) {
        LocationErrorKind.denied =>
          'Tap "Try Again" to re-request location permission.',
        LocationErrorKind.deniedForever =>
          'Open device Settings, grant Location access for Cairn, '
              'then return here.',
        LocationErrorKind.servicesDisabled =>
          'Enable GPS / location services in device Settings, '
              'then tap "Try Again".',
        LocationErrorKind.timeout =>
          'No GPS fix in 30 s. Move to a more open area and tap "Retry".',
        LocationErrorKind.unknown =>
          'An unexpected error occurred. Tap "Retry" or skip GPS.',
      };

  /// True when the error can be retried without leaving the app.
  bool get canRetryInApp => this != LocationErrorKind.deniedForever;

  /// True when the user should be offered an "Open Settings" button.
  bool get requiresSettings =>
      this == LocationErrorKind.deniedForever ||
      this == LocationErrorKind.servicesDisabled;
}

// ─────────────────────────────────────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────────────────────────────────────

sealed class LocationResult {
  const LocationResult();

  factory LocationResult.success(GeoLocation location) = LocationSuccess;
  factory LocationResult.failure(LocationErrorKind kind, {String? message}) =
      LocationFailure;

  bool get isSuccess => this is LocationSuccess;

  GeoLocation? get location =>
      this is LocationSuccess ? (this as LocationSuccess).location : null;

  LocationErrorKind? get errorKind =>
      this is LocationFailure ? (this as LocationFailure).kind : null;
}

final class LocationSuccess extends LocationResult {
  const LocationSuccess(this.location);
  @override
  final GeoLocation location;
}

final class LocationFailure extends LocationResult {
  const LocationFailure(this.kind, {this.message});
  final LocationErrorKind kind;
  final String? message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Skip-GPS sentinel
// ─────────────────────────────────────────────────────────────────────────────

/// The address-text marker written when the volunteer explicitly skips GPS.
const _kSkipAddressMarker = '[GPS unavailable — location not recorded]';

/// A [GeoLocation] written when the volunteer explicitly skips GPS.
///
/// Uses `accuracyMeters == 0.0` (schema-valid; `accuracy_m >= 0` required) and
/// a distinctive [_kSkipAddressMarker] string as the sentinel discriminator.
/// The report PDF and downstream validator both recognise it and display a
/// "[GPS unavailable]" notice rather than coordinates.
const kSkippedGeoLocation = GeoLocation(
  lat: 0.0,
  lng: 0.0,
  accuracyMeters: 0.0,
  addressText: _kSkipAddressMarker,
);

/// True when [loc] carries the skip-GPS sentinel.
///
/// A zero-accuracy real fix (unusual but valid) is NOT a skipped location
/// because its [GeoLocation.addressText] will differ from [_kSkipAddressMarker].
bool isSkippedLocation(GeoLocation loc) =>
    loc.lat == 0.0 &&
    loc.lng == 0.0 &&
    loc.accuracyMeters == 0.0 &&
    loc.addressText == _kSkipAddressMarker;

// ─────────────────────────────────────────────────────────────────────────────
// Abstract resolver (seam for unit tests)
// ─────────────────────────────────────────────────────────────────────────────

abstract class LocationResolver {
  const LocationResolver();

  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition({required Duration timeout});

  /// Best-effort reverse geocode; returns empty string on any failure.
  Future<String> reverseGeocode(double lat, double lng);
}

// ─────────────────────────────────────────────────────────────────────────────
// Production resolver — geolocator + geocoding packages
// ─────────────────────────────────────────────────────────────────────────────

class GeolocatorLocationResolver implements LocationResolver {
  const GeolocatorLocationResolver();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition({required Duration timeout}) =>
      Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(timeout);

  @override
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return '';
      final p = places.first;
      return [p.street, p.locality, p.administrativeArea, p.country]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-level resolution function
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the current device location.
///
/// Checks service enable-state, permission state (requesting if needed),
/// acquires a GPS fix within [timeout], and best-effort reverse-geocodes.
/// **Never throws** — every failure is returned as a [LocationFailure].
Future<LocationResult> resolveLocation({
  LocationResolver resolver = const GeolocatorLocationResolver(),
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    // 1. Services enabled?
    final serviceOn = await resolver.isServiceEnabled();
    if (!serviceOn) {
      return LocationResult.failure(LocationErrorKind.servicesDisabled);
    }

    // 2. Permission
    var perm = await resolver.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      return LocationResult.failure(LocationErrorKind.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      perm = await resolver.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        return LocationResult.failure(LocationErrorKind.deniedForever);
      }
      if (perm == LocationPermission.denied) {
        return LocationResult.failure(LocationErrorKind.denied);
      }
    }

    // 3. Fix (timeout-guarded)
    final pos = await resolver.getCurrentPosition(timeout: timeout);

    // 4. Reverse geocode (best-effort; failure is silent)
    final address = await resolver.reverseGeocode(pos.latitude, pos.longitude);

    return LocationResult.success(GeoLocation(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      addressText: address,
    ));
  } on TimeoutException {
    return LocationResult.failure(LocationErrorKind.timeout);
  } catch (e) {
    return LocationResult.failure(
      LocationErrorKind.unknown,
      message: e.toString(),
    );
  }
}
