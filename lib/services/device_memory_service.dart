import 'dart:io';

import 'runtime_service.dart';

class DeviceMemory {
  const DeviceMemory(this.totalMb, this.availableMb);
  final int totalMb;
  final int availableMb;
}

/// Total and available RAM. Supported platforms: Android and Windows.
class DeviceMemoryService {
  static Future<DeviceMemory> detect() async {
    if (Platform.isAndroid) {
      final info = await RuntimeService.androidInfo();
      return DeviceMemory(
        ((info['totalMemoryBytes'] as num) / 1048576).floor(),
        ((info['availableMemoryBytes'] as num) / 1048576).floor(),
      );
    }
    if (Platform.isWindows) {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$m=Get-CimInstance Win32_OperatingSystem; Write-Output $m.TotalVisibleMemorySize; Write-Output $m.FreePhysicalMemory',
      ]);
      if (result.exitCode != 0) {
        throw StateError('Windows could not report physical memory');
      }
      final numbers = '${result.stdout}'
          .trim()
          .split(RegExp(r'\s+'))
          .map(int.parse)
          .toList();
      return DeviceMemory(numbers[0] ~/ 1024, numbers[1] ~/ 1024);
    }
    throw UnsupportedError('HostCraft supports Android and Windows only.');
  }
}