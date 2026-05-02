/// Unit tests for Phase 7 photo-capture robustness: [PendingSlotStore] and
/// the lost-data recovery state machine in [PhotosScreen].
///
/// [PendingSlotStore] is tested directly (SharedPreferences is mocked via
/// the standard Flutter test pattern). The [PhotosScreen] lost-data logic
/// is exercised at the unit level by testing the helper types rather than
/// via widget tests, keeping the test suite consistent with prior phases.
///
/// Coverage:
///   - [PendingSlotStore.save] writes the key
///   - [PendingSlotStore.read] returns the correct value
///   - [PendingSlotStore.clear] removes the key
///   - Save → clear round-trip yields null on second read
///   - Multiple saves: last write wins
///   - Save with empty string is legal and round-trips correctly
///   - read() returns null when no key has been written
///   - [PendingSlotStore._key] is stable (regression guard)
///   - Concurrent-safe: two stores backed by the same SharedPreferences
///     instance share state
library;

import 'package:cairn_mobile/core/photos/pending_slot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Reset to a clean state before every test.
    SharedPreferences.setMockInitialValues({});
  });

  Future<PendingSlotStore> makeStore() async => PendingSlotStore.create();

  group('PendingSlotStore — basic save/read/clear', () {
    test('read returns null before any save', () async {
      final store = await makeStore();
      expect(store.read(), isNull);
    });

    test('save then read returns the saved slot', () async {
      final store = await makeStore();
      await store.save('front');
      expect(store.read(), 'front');
    });

    test('save then clear then read returns null', () async {
      final store = await makeStore();
      await store.save('cracks');
      await store.clear();
      expect(store.read(), isNull);
    });

    test('multiple saves: last write wins', () async {
      final store = await makeStore();
      await store.save('front');
      await store.save('ground_floor');
      await store.save('foundation');
      expect(store.read(), 'foundation');
    });

    test('save with empty string round-trips correctly', () async {
      final store = await makeStore();
      await store.save('');
      expect(store.read(), '');
    });

    test('clear on empty store is a no-op (no throw)', () async {
      final store = await makeStore();
      await expectLater(store.clear(), completes);
      expect(store.read(), isNull);
    });
  });

  group('PendingSlotStore — all known slot names persist', () {
    const knownSlots = [
      'front',
      'ground_floor',
      'cracks',
      'foundation',
      'extra',
    ];

    for (final slot in knownSlots) {
      test('slot "$slot" round-trips correctly', () async {
        SharedPreferences.setMockInitialValues({});
        final store = await makeStore();
        await store.save(slot);
        expect(store.read(), slot,
            reason: 'slot "$slot" must survive save/read');
      });
    }
  });

  group('PendingSlotStore — key stability (regression guard)', () {
    test('stored under the expected SharedPreferences key', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = PendingSlotStore(prefs);
      await store.save('front');
      expect(prefs.getString('cairn.pending_photo_slot'), 'front',
          reason:
              'key must be cairn.pending_photo_slot — changing it breaks '
              'the Activity-kill recovery contract');
    });
  });

  group('PendingSlotStore — shared state', () {
    test('two instances on the same prefs share state', () async {
      final prefs = await SharedPreferences.getInstance();
      final store1 = PendingSlotStore(prefs);
      final store2 = PendingSlotStore(prefs);

      await store1.save('cracks');
      expect(store2.read(), 'cracks',
          reason: 'both stores must see the same underlying key');
    });

    test('clear via store1 is seen by store2', () async {
      final prefs = await SharedPreferences.getInstance();
      final store1 = PendingSlotStore(prefs);
      final store2 = PendingSlotStore(prefs);

      await store1.save('foundation');
      await store1.clear();
      expect(store2.read(), isNull);
    });
  });

  group('PendingSlotStore — capture flow simulation', () {
    test('typical capture cycle: save → pick → clear', () async {
      final store = await makeStore();

      // Before capture: no pending slot.
      expect(store.read(), isNull);

      // User taps "Capture" on the 'cracks' slot.
      await store.save('cracks');
      expect(store.read(), 'cracks',
          reason: 'slot saved before camera intent fires');

      // Camera returns successfully.
      await store.clear();
      expect(store.read(), isNull,
          reason: 'slot cleared after successful pick');
    });

    test(
        'Activity-kill scenario: slot survives until recovery reads and clears it',
        () async {
      // Simulate: Activity is killed after save() but before clear().
      // A new store instance (new Activity) must still see the saved slot.
      final prefs = await SharedPreferences.getInstance();

      // Old Activity: save before camera intent.
      final oldStore = PendingSlotStore(prefs);
      await oldStore.save('front');

      // Activity is "killed" — old store instance is gone.
      // New Activity creates a fresh store backed by the same prefs.
      final newStore = PendingSlotStore(prefs);
      final recovered = newStore.read();
      expect(recovered, 'front',
          reason: 'new Activity must see the slot saved by old Activity');

      // Recovery clears the key.
      await newStore.clear();
      expect(newStore.read(), isNull,
          reason: 'slot cleared after recovery');
    });

    test('user cancels camera: clear removes pending slot', () async {
      final store = await makeStore();

      await store.save('extra');
      // User presses back / cancels camera.
      await store.clear();
      expect(store.read(), isNull);
    });

    test('retake scenario: second save overwrites first', () async {
      final store = await makeStore();

      // First capture attempt on 'front'.
      await store.save('front');
      await store.clear(); // completed successfully

      // Second capture on 'ground_floor'.
      await store.save('ground_floor');
      expect(store.read(), 'ground_floor');
    });
  });
}
