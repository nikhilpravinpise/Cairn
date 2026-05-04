/// Unit tests for [resolveLocation] and supporting types.
///
/// All tests use [_MockLocationResolver] — no platform channels are involved.
/// Coverage:
///   - All five [LocationErrorKind] paths through [resolveLocation]
///   - Permission escalation: denied → request → granted
///   - Permission escalation: denied → request → deniedForever
///   - Timeout exception mapped to [LocationErrorKind.timeout]
///   - Unexpected exception mapped to [LocationErrorKind.unknown]
///   - Happy path returns [LocationSuccess] with correct coordinates
///   - [LocationErrorKindX] extension: label, guidance, canRetryInApp,
///     requiresSettings
///   - [kSkippedGeoLocation] sentinel values
///   - [isSkippedLocation] predicate
library;

import 'dart:async';

import 'package:cairn_mobile/core/location/location_service.dart';
import 'package:cairn_mobile/core/models/evidence_packet.dart';
import 'package:cairn_mobile/core/models/evidence_packet_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock resolver
// ─────────────────────────────────────────────────────────────────────────────

class _MockLocationResolver implements LocationResolver {
  _MockLocationResolver({
    required this.serviceEnabled,
    required this.initialPermission,
    LocationPermission? permissionAfterRequest,
    this.position,
    this.geocodeResult = '',
    this.throwOnGetPosition,
  }) : permissionAfterRequest =
            permissionAfterRequest ?? initialPermission;

  final bool serviceEnabled;
  final LocationPermission initialPermission;
  final LocationPermission permissionAfterRequest;
  final Position? position;
  final String geocodeResult;
  final Object? throwOnGetPosition;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => initialPermission;

  @override
  Future<LocationPermission> requestPermission() async =>
      permissionAfterRequest;

  @override
  Future<Position> getCurrentPosition({required Duration timeout}) async {
    if (throwOnGetPosition != null) throw throwOnGetPosition!;
    if (position == null) {
      throw StateError('_MockLocationResolver: position not configured');
    }
    return position!;
  }

  @override
  Future<String> reverseGeocode(double lat, double lng) async =>
      geocodeResult;
}

/// Creates a [Position] with the given lat/lng; all other fields defaulted.
Position _pos(double lat, double lng, {double accuracy = 10.0}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026),
      accuracy: accuracy,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('resolveLocation — service disabled', () {
    test('returns servicesDisabled when location service is off', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: false,
          initialPermission: LocationPermission.always,
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.servicesDisabled);
    });
  });

  group('resolveLocation — permission denied forever (initial)', () {
    test('returns deniedForever without requesting permission', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.deniedForever,
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.deniedForever);
    });
  });

  group('resolveLocation — denied, then granted after request', () {
    test('returns success when request grants whileInUse', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.denied,
          permissionAfterRequest: LocationPermission.whileInUse,
          position: _pos(48.8566, 2.3522),
          geocodeResult: 'Paris, France',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.location!.lat, closeTo(48.8566, 0.0001));
      expect(result.location!.lng, closeTo(2.3522, 0.0001));
      expect(result.location!.addressText, 'Paris, France');
    });

    test('returns denied when request still returns denied', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.denied,
          permissionAfterRequest: LocationPermission.denied,
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.denied);
    });

    test('returns deniedForever when request escalates to deniedForever',
        () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.denied,
          permissionAfterRequest: LocationPermission.deniedForever,
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.deniedForever);
    });
  });

  group('resolveLocation — timeout', () {
    test('returns timeout when getCurrentPosition throws TimeoutException',
        () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.whileInUse,
          throwOnGetPosition: TimeoutException('timed out'),
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.timeout);
    });
  });

  group('resolveLocation — unknown error', () {
    test('returns unknown when getCurrentPosition throws generic error',
        () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.always,
          throwOnGetPosition: Exception('platform error'),
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorKind, LocationErrorKind.unknown);
      expect((result as LocationFailure).message, contains('platform error'));
    });
  });

  group('resolveLocation — happy path', () {
    test('returns success with correct coordinates and address', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.always,
          position: _pos(37.7749, -122.4194, accuracy: 5.0),
          geocodeResult: 'San Francisco, CA, US',
        ),
      );
      expect(result.isSuccess, isTrue);
      final loc = result.location!;
      expect(loc.lat, closeTo(37.7749, 0.0001));
      expect(loc.lng, closeTo(-122.4194, 0.0001));
      expect(loc.accuracyMeters, closeTo(5.0, 0.001));
      expect(loc.addressText, 'San Francisco, CA, US');
    });

    test('succeeds even when geocode returns empty string', () async {
      final result = await resolveLocation(
        resolver: _MockLocationResolver(
          serviceEnabled: true,
          initialPermission: LocationPermission.always,
          position: _pos(0, 0),
          geocodeResult: '',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.location!.addressText, '');
    });

    test('already-granted permission skips requestPermission', () async {
      var requestCalled = false;

      final resolver = _AlwaysGrantedResolver(
        position: _pos(1, 2),
        onRequest: () => requestCalled = true,
      );

      final result = await resolveLocation(resolver: resolver);
      expect(result.isSuccess, isTrue);
      expect(requestCalled, isFalse,
          reason:
              'requestPermission should not be called when already granted');
    });
  });

  // ── LocationResult type ───────────────────────────────────────────────────

  group('LocationResult', () {
    test('LocationSuccess.location is set; errorKind is null', () {
      const loc = GeoLocation(lat: 1, lng: 2, accuracyMeters: 3);
      final r = LocationResult.success(loc);
      expect(r.isSuccess, isTrue);
      expect(r.location, equals(loc));
      expect(r.errorKind, isNull);
    });

    test('LocationFailure.errorKind is set; location is null', () {
      final r = LocationResult.failure(LocationErrorKind.denied);
      expect(r.isSuccess, isFalse);
      expect(r.location, isNull);
      expect(r.errorKind, LocationErrorKind.denied);
    });

    test('LocationFailure carries optional message', () {
      final r = LocationResult.failure(LocationErrorKind.unknown,
          message: 'crash info');
      expect((r as LocationFailure).message, 'crash info');
    });
  });

  // ── LocationErrorKindX extension ──────────────────────────────────────────

  group('LocationErrorKindX.label', () {
    test('all five kinds have non-empty labels', () {
      for (final kind in LocationErrorKind.values) {
        expect(kind.label, isNotEmpty,
            reason: '${kind.name} must have a label');
      }
    });

    test('labels are distinct', () {
      final labels = LocationErrorKind.values.map((k) => k.label).toList();
      expect(labels.toSet().length, LocationErrorKind.values.length,
          reason: 'each kind must have a unique label');
    });
  });

  group('LocationErrorKindX.guidance', () {
    test('all five kinds have non-empty guidance strings', () {
      for (final kind in LocationErrorKind.values) {
        expect(kind.guidance, isNotEmpty,
            reason: '${kind.name} must have guidance text');
      }
    });
  });

  group('LocationErrorKindX.canRetryInApp', () {
    test('deniedForever cannot retry in-app', () {
      expect(LocationErrorKind.deniedForever.canRetryInApp, isFalse);
    });

    test('all others can retry in-app', () {
      final others = LocationErrorKind.values
          .where((k) => k != LocationErrorKind.deniedForever);
      for (final kind in others) {
        expect(kind.canRetryInApp, isTrue,
            reason: '${kind.name} should allow in-app retry');
      }
    });
  });

  group('LocationErrorKindX.requiresSettings', () {
    test('deniedForever and servicesDisabled require settings', () {
      expect(LocationErrorKind.deniedForever.requiresSettings, isTrue);
      expect(LocationErrorKind.servicesDisabled.requiresSettings, isTrue);
    });

    test('denied, timeout, unknown do not require settings', () {
      for (final kind in [
        LocationErrorKind.denied,
        LocationErrorKind.timeout,
        LocationErrorKind.unknown,
      ]) {
        expect(kind.requiresSettings, isFalse,
            reason: '${kind.name} should not require settings');
      }
    });
  });

  // ── kSkippedGeoLocation sentinel ──────────────────────────────────────────

  group('kSkippedGeoLocation', () {
    test('has accuracyMeters == 0.0 (schema-valid sentinel)', () {
      expect(kSkippedGeoLocation.accuracyMeters, 0.0);
    });

    test('lat and lng are 0.0', () {
      expect(kSkippedGeoLocation.lat, 0.0);
      expect(kSkippedGeoLocation.lng, 0.0);
    });

    test('addressText is non-empty (visible in report)', () {
      expect(kSkippedGeoLocation.addressText, isNotEmpty);
    });

    test('isSkippedLocation returns true for sentinel', () {
      expect(isSkippedLocation(kSkippedGeoLocation), isTrue);
    });

    test('isSkippedLocation returns false for real location', () {
      const real = GeoLocation(lat: 37.7, lng: -122.4, accuracyMeters: 10);
      expect(isSkippedLocation(real), isFalse);
    });

    test('zero-accuracy real fix is NOT the skip sentinel', () {
      const zeroAccuracy = GeoLocation(lat: 0, lng: 0, accuracyMeters: 0);
      expect(isSkippedLocation(zeroAccuracy), isFalse,
          reason: 'sentinel requires the specific addressText marker; '
              'a bare zero-accuracy fix has an empty addressText');
    });

    test('kSkippedGeoLocation passes EvidencePacketValidator accuracy check',
        () {
      // Before Sprint 0, accuracyMeters was -1.0 which violated accuracy_m >= 0.
      // This regression test ensures the skipped location is always schema-valid.
      final errors = EvidencePacketValidator.validate(
        _buildMinimalPacket(location: kSkippedGeoLocation),
      );
      final locationErrors =
          errors.where((e) => e.path.startsWith('location')).toList();
      expect(locationErrors, isEmpty,
          reason: 'skipped GPS location must be schema-valid (accuracy_m >= 0)');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

EvidencePacket _buildMinimalPacket({GeoLocation? location}) {
  return EvidencePacket(
    packetId: '01900000-0000-7000-8000-000000000001',
    createdAtUtc: DateTime.utc(2026, 1, 1),
    appVersion: '0.0.0',
    protocol: 'FEMA-P-154-L1',
    modelName: 'gemma-4-e2b-it',
    modelQuant: 'int4',
    location: location ??
        const GeoLocation(lat: 34.05, lng: -118.24, accuracyMeters: 5),
    building:
        const BuildingInfo(type: 'wood_light_frame', storiesAboveGrade: 1),
    observations: const [],
    hazardsFlagged: const [],
    protocolAnswers: const ProtocolAnswersRecord(),
    triage: const TriageResult(
      priorityScore: 3,
      priorityBand: 'LOW',
      rationaleBullets: ['no issues observed'],
      uncertaintyNotes: [],
      recommendEngineerFollowup: false,
    ),
    volunteer: const VolunteerAttestation(
      attestation: 'I am not a licensed engineer.',
      signatureHash: 'sha256:0000000000000000000000000000000000000000000000000000000000000000',
      locale: 'en-US',
    ),
    images: const [],
    audio: const [],
  );
}

class _AlwaysGrantedResolver implements LocationResolver {
  _AlwaysGrantedResolver({required this.position, required this.onRequest});
  final Position position;
  final void Function() onRequest;

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async {
    onRequest();
    return LocationPermission.always;
  }

  @override
  Future<Position> getCurrentPosition({required Duration timeout}) async =>
      position;

  @override
  Future<String> reverseGeocode(double lat, double lng) async => '';
}
