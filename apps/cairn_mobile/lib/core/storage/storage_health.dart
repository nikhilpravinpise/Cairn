library;

import 'package:flutter/services.dart';

class StorageStatus {
  const StorageStatus({
    required this.availableBytes,
    required this.lowDisk,
    required this.supported,
  });

  final int? availableBytes;
  final bool lowDisk;
  final bool supported;

  String get label {
    final bytes = availableBytes;
    if (!supported || bytes == null) return 'Storage status unavailable';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB free';
  }
}

class StorageHealthService {
  static const _channel = MethodChannel('app.cairn/storage_health');
  static const _lowDiskThresholdBytes = 1024 * 1024 * 1024;

  Future<StorageStatus> check() async {
    try {
      final available = await _channel.invokeMethod<int>('availableBytes');
      if (available == null) {
        return const StorageStatus(
          availableBytes: null,
          lowDisk: false,
          supported: false,
        );
      }
      return StorageStatus(
        availableBytes: available,
        lowDisk: available < _lowDiskThresholdBytes,
        supported: true,
      );
    } catch (_) {
      return const StorageStatus(
        availableBytes: null,
        lowDisk: false,
        supported: false,
      );
    }
  }
}
