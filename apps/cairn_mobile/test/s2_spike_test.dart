/// Phase 10 — S2 spike repair tests.
///
/// Proves that [runBurst] surfaces a clean, actionable error when
/// [assets/images/s2_probe.jpg] is absent instead of propagating an
/// unhandled [FlutterError] or [Exception].
///
/// Test strategy: override [probeImageLoaderProvider] via [ProviderContainer]
/// so no live asset bundle or native model is required.
library;

import 'dart:typed_data';

import 'package:cairn_mobile/spike/s2_spike_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // probeImageLoaderProvider
  // ---------------------------------------------------------------------------

  group('probeImageLoaderProvider', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('is a non-null Riverpod provider', () {
      expect(probeImageLoaderProvider, isNotNull);
    });

    test('is readable from a ProviderContainer without throwing', () {
      // Verify the provider is registered; calling the returned function would
      // throw in a test environment with no real asset bundle, but reading the
      // provider itself must not throw.
      expect(() => container.read(probeImageLoaderProvider), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // spikeCtlProvider — initial state
  // ---------------------------------------------------------------------------

  group('spikeCtlProvider initial state', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('modelKey defaults to e4b', () {
      expect(container.read(spikeCtlProvider).modelKey, equals('e4b'));
    });

    test('loading is false', () {
      expect(container.read(spikeCtlProvider).loading, isFalse);
    });

    test('error is null', () {
      expect(container.read(spikeCtlProvider).error, isNull);
    });

    test('runs is empty', () {
      expect(container.read(spikeCtlProvider).runs, isEmpty);
    });

    test('session is null', () {
      expect(container.read(spikeCtlProvider).session, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // selectModel
  // ---------------------------------------------------------------------------

  group('selectModel', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('changes modelKey when no session is loaded', () {
      container.read(spikeCtlProvider.notifier).selectModel('e2b');
      expect(container.read(spikeCtlProvider).modelKey, equals('e2b'));
    });

    test('can select e4b (round-trip)', () {
      container.read(spikeCtlProvider.notifier).selectModel('e2b');
      container.read(spikeCtlProvider.notifier).selectModel('e4b');
      expect(container.read(spikeCtlProvider).modelKey, equals('e4b'));
    });
  });

  // ---------------------------------------------------------------------------
  // runBurst — missing probe image (pre-flight check)
  // ---------------------------------------------------------------------------

  group('runBurst — missing probe image', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          probeImageLoaderProvider.overrideWith(
            (ref) =>
                () async => throw Exception('Asset not found: s2_probe.jpg'),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('does not throw; error state set instead', () async {
      await expectLater(
        () => container.read(spikeCtlProvider.notifier).runBurst(),
        returnsNormally,
      );
      expect(container.read(spikeCtlProvider).error, isNotNull);
    });

    test('error message says S2 probe image not found', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(
        container.read(spikeCtlProvider).error,
        contains('S2 probe image not found'),
      );
    });

    test('error message contains the asset path', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(
        container.read(spikeCtlProvider).error,
        contains('assets/images/s2_probe.jpg'),
      );
    });

    test('error message contains rebuild instruction', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(container.read(spikeCtlProvider).error, contains('rebuild'));
    });

    test('error message references s2_checklist.md', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(
        container.read(spikeCtlProvider).error,
        contains('s2_checklist.md'),
      );
    });

    test('no runs are added', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(container.read(spikeCtlProvider).runs, isEmpty);
    });

    test('loading remains false', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(container.read(spikeCtlProvider).loading, isFalse);
    });

    test('session remains null', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(container.read(spikeCtlProvider).session, isNull);
    });

    test('image-missing error is set even when session is null', () async {
      // Pre-flight image check runs first; "load model first" is never reached.
      await container.read(spikeCtlProvider.notifier).runBurst();
      final error = container.read(spikeCtlProvider).error!;
      expect(error, contains('S2 probe image not found'));
      expect(error, isNot(contains('load model first')));
    });
  });

  // ---------------------------------------------------------------------------
  // runBurst — no session loaded (image available)
  // ---------------------------------------------------------------------------

  group('runBurst — no session loaded (image available)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          probeImageLoaderProvider.overrideWith(
            (ref) => () async => Uint8List(4),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('sets "load model first" error', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(
        container.read(spikeCtlProvider).error,
        contains('load model first'),
      );
    });

    test('no runs are added', () async {
      await container.read(spikeCtlProvider.notifier).runBurst();
      expect(container.read(spikeCtlProvider).runs, isEmpty);
    });
  });
}
