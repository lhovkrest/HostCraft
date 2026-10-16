import 'dart:io';
import 'dart:math' as math;

import 'runtime_service.dart';

/// Reads facts about the device HostCraft runs on, mainly installed RAM.
/// Supported platforms: Android and Windows.
class DeviceService {
  static const memoryStepMb = 256;
  static const minMemoryMb = 512;

  /// Used only when the device RAM cannot be read at all.
  static const fallbackRamMb = 8192;

  /// Total physical RAM in megabytes, or null when it cannot be determined.
  static Future<int?> totalRamMb() async {
    try {
      if (Platform.isAndroid) {
        final info = await RuntimeService.androidInfo();
        final value = info['totalMemMb'];
        return value is num && value > 0 ? value.round() : null;
      }
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ]);
        final bytes = int.tryParse('${result.stdout}'.trim());
        return bytes == null ? null : bytes ~/ (1024 * 1024);
      }
    } catch (_) {
      // Fall through: the caller shows a note and uses a safe default.
    }
    return null;
  }

  static int roundDownToStep(int mb) => (mb ~/ memoryStepMb) * memoryStepMb;

  /// The most heap a server may be given: all of the device's RAM.
  static int maxHeapMb(int totalMb) =>
      math.max(minMemoryMb, roundDownToStep(totalMb));

  /// Heap that normally leaves the system enough room to keep running:
  /// about half the RAM on phones, three quarters on Windows PCs.
  static int recommendedHeapMb(int totalMb) {
    final share = Platform.isAndroid ? 0.5 : 0.75;
    final value = roundDownToStep((totalMb * share).floor());
    return math.min(maxHeapMb(totalMb), math.max(minMemoryMb, value));
  }

  /// Default heap for a brand new server: the old 2 GB default, lowered on
  /// devices where that would be more than the recommendation.
  static int defaultHeapMb(int totalMb) =>
      math.min(2048, recommendedHeapMb(totalMb));

  static int clampHeapMb(int mb, int totalMb) =>
      math.min(maxHeapMb(totalMb), math.max(minMemoryMb, mb));
}