import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void hostingCallback() => FlutterForegroundTask.setTaskHandler(HostingTask());

class HostingTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    FlutterForegroundTask.sendDataToMain('stop');
  }

  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);
}

class BackgroundService {
  static void initialize() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hostcraft_hosting',
        channelName: 'Minecraft hosting',
        channelDescription: 'Active Minecraft server',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        stopWithTask: false,
      ),
    );
  }

  static Future<void> start(String name) async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 2141,
      notificationTitle: 'HostCraft · $name',
      notificationText: 'Minecraft server is active. Tap to open.',
      notificationButtons: [
        const NotificationButton(id: 'stop', text: 'Stop server'),
      ],
      callback: hostingCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('Cannot start hosting service: ${result.error}');
    }
  }

  static Future<void> stop() async {
    if (Platform.isAndroid) await FlutterForegroundTask.stopService();
  }
}
