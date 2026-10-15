import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/core/host_controller.dart';
import 'package:hostcraft/core/models.dart';
import 'package:hostcraft/services/minecraft_server.dart';
import 'package:hostcraft/ui/hostcraft_app.dart';

class PreviewHost extends HostController {
  PreviewHost() {
    loaded = true;
    server = MinecraftGameServer(
      profile: profile,
      root: Directory.systemTemp,
      onPhase: (_) {},
      onProgress: (_, _) {},
      onMetrics: (_, _) {},
    );
    logs.add(LogLine('Welcome to HostCraft. Your world, your hardware.'));
    lanAddresses = ['192.168.1.42'];
  }
  @override
  Future<Map<String, String>> readSettings() async => {
    ...ServerProperties.defaults,
  };
}

void main() {
  testWidgets('phone layout navigates and gates setup behind EULA choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = PreviewHost();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostProvider.overrideWith((ref) => host)],
        child: const HostCraftApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make room for adventure.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Set up server'));
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save setup'),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Console'));
    await tester.pumpAndSettle();
    expect(find.text('Live console'), findsOneWidget);
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(find.text('Invite the whole crew.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Your server, your rules.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('desktop layout uses navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostProvider.overrideWith((ref) => PreviewHost())],
        child: const HostCraftApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
