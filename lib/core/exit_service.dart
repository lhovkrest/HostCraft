import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../services/background_service.dart';
import 'host_controller.dart';
import 'models.dart';

/// Give this to `MaterialApp(navigatorKey: rootNavigatorKey)` so the exit
/// dialog can be shown from outside the widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>();

enum _ExitChoice { minimize, exit }

/// Decides what happens when the user tries to close HostCraft.
///
/// * Windows: the window's close button asks "Minimize to tray" or "Exit".
/// * Android: the system Back button at the top level asks "Keep running in
///   background" or "Exit".
///
/// Choosing Exit stops Playit and Java (graceful `stop`, then a hard kill) and
/// only then closes the app, so no `java.exe` is left running.
class AppExitService with WidgetsBindingObserver, WindowListener, TrayListener {
  AppExitService(this._container);
  final ProviderContainer _container;
  bool _asking = false;
  bool _exiting = false;
  bool _trayReady = false;

  HostController get _host => _container.read(hostProvider);

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    try {
      trayManager.addListener(this);
      // Declare this file under `flutter: assets:` in pubspec.yaml.
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('HostCraft');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Show HostCraft'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Exit and stop server'),
          ],
        ),
      );
      _trayReady = true;
    } catch (_) {
      // Without a tray icon the window is minimized to the taskbar instead.
      _trayReady = false;
    }
  }

  // ---- triggers -----------------------------------------------------------

  @override
  void onWindowClose() => unawaited(requestExit());

  /// Android Back button. Only intercepted at the top level; inside the app
  /// the Navigator keeps handling Back as usual.
  @override
  Future<bool> didPopRoute() async {
    if (!Platform.isAndroid || _exiting) return false;
    final nav = rootNavigatorKey.currentState;
    if (nav == null || nav.canPop()) return false;
    unawaited(requestExit());
    return true;
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(_showWindow());
    if (menuItem.key == 'exit') unawaited(_exitNow());
  }

  // ---- flow ---------------------------------------------------------------

  Future<void> requestExit() async {
    if (_asking || _exiting) return;
    if (rootNavigatorKey.currentContext == null) {
      await _exitNow(); // The UI is not ready, nothing to ask.
      return;
    }
    _asking = true;
    try {
      if (Platform.isWindows) await _showWindow();
      final dialogContext = rootNavigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) return;
      final serverOn =
          _host.active || _host.phase == ServerPhase.preparing || (_host.tunnel?.running ?? false);
      final choice = await showDialog<_ExitChoice>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: const Text('Close HostCraft?'),
          content: Text(
            serverOn
                ? (Platform.isWindows
                      ? 'Your Minecraft server is running. Minimize to the tray to keep it online, or exit to stop the server and the Java process.'
                      : 'Your Minecraft server is running. Keep it running in the background, or exit to stop the server.')
                : (Platform.isWindows
                      ? 'Minimize to the tray, or exit HostCraft completely.'
                      : 'Send HostCraft to the background, or exit it completely.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(_ExitChoice.minimize),
              child: Text(
                Platform.isWindows ? 'Minimize to tray' : 'Keep in background',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_ExitChoice.exit),
              child: Text(serverOn ? 'Exit and stop server' : 'Exit'),
            ),
          ],
        ),
      );
      switch (choice) {
        case _ExitChoice.minimize:
          await _minimize();
        case _ExitChoice.exit:
          await _exitNow();
        case null:
          break;
      }
    } finally {
      _asking = false;
    }
  }

  Future<void> _minimize() async {
    if (Platform.isWindows) {
      if (_trayReady) {
        await windowManager.setSkipTaskbar(true);
        await windowManager.hide();
      } else {
        await windowManager.minimize();
      }
    } else {
      FlutterForegroundTask.minimizeApp();
    }
  }

  Future<void> _showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitNow() async {
    if (_exiting) return;
    _exiting = true;
    final visible = !Platform.isWindows || await windowManager.isVisible();
    final context = rootNavigatorKey.currentContext;
    if (visible && context != null && context.mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 16),
                  Text('Stopping the server…'),
                ],
              ),
            ),
          ),
        ),
      );
    }
    try {
      await _host.shutdown().timeout(const Duration(seconds: 60));
    } catch (_) {
      // Anything still alive is killed with HostCraft (see ProcessGuard).
    }
    if (Platform.isWindows) {
      try {
        await trayManager.destroy();
      } catch (_) {}
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    } else {
      await BackgroundService.stop();
      await SystemNavigator.pop();
    }
  }
}
