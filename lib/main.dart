import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/exit_service.dart';
import 'services/background_service.dart';
import 'ui/hostcraft_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundService.initialize();
  // One container shared by the UI and the exit service, so closing the app
  // can stop the same server the UI is controlling.
  final container = ProviderContainer();
  await AppExitService(container).initialize();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HostCraftApp(),
    ),
  );
}