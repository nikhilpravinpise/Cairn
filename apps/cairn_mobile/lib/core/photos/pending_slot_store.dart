/// Persists the in-flight photo slot name across Android Activity kills.
///
/// On Android, launching the camera intent may cause the host Activity to be
/// destroyed by the OS to reclaim RAM. Saving the slot key to SharedPreferences
/// **before** firing the intent lets [PhotosScreen] recover which slot to
/// assign the [image_picker] lost-data result to when the Activity is
/// reconstructed.
///
/// Usage:
/// ```dart
/// // Before launching camera:
/// await store.save(spec.slot);
/// final xFile = await _picker.pickImage(...);
/// await store.clear();           // success — clear immediately
/// ```
///
/// On reconstruction, `initState` calls `retrieveLostData()` and reads
/// `store.read()` to determine which slot the recovered image belongs to.
library;

import 'package:shared_preferences/shared_preferences.dart';

class PendingSlotStore {
  static const _key = 'cairn.pending_photo_slot';

  final SharedPreferences _prefs;
  PendingSlotStore(this._prefs);

  /// Create an instance backed by the singleton SharedPreferences store.
  static Future<PendingSlotStore> create() async =>
      PendingSlotStore(await SharedPreferences.getInstance());

  /// Persist [slot] immediately before launching the camera intent.
  Future<void> save(String slot) => _prefs.setString(_key, slot);

  /// Clear after a successful pick or explicit cancel.
  Future<void> clear() async => _prefs.remove(_key);

  /// Read the in-flight slot; returns null if not set or already cleared.
  String? read() => _prefs.getString(_key);
}
