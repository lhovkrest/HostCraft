import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/background_service.dart';
import 'ui/hostcraft_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundService.initialize();
  runApp(const ProviderScope(child: HostCraftApp()));
}
