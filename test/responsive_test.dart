import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/core/host_controller.dart';
import 'package:hostcraft/core/models.dart';
import 'package:hostcraft/ui/hostcraft_app.dart';

import 'widget_test.dart' show PreviewHost;

void main() {
  const capture = bool.fromEnvironment('HOSTCRAFT_CAPTURE');
  if (capture) {
    setUpAll(() async {
      final loader = FontLoader('Segoe UI');
      for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
        loader.addFont(
          File('C:/Windows/Fonts/$name')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
      for (final family in ['Roboto', 'monospace']) {
        final font = FontLoader(family);
        font.addFont(
          File(
            'C:/Windows/Fonts/${family == 'monospace' ? 'consola.ttf' : 'segoeui.ttf'}',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
        await font.load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }

  for (final scenario in [
    ('desktop-dark', const Size(1440, 1080), ThemeMode.dark, 1.0),
    ('desktop-light', const Size(1280, 1000), ThemeMode.light, 1.0),
    ('phone-dark', const Size(390, 844), ThemeMode.dark, 1.0),
    ('phone-small', const Size(320, 740), ThemeMode.light, 1.0),
    ('phone-large-text', const Size(390, 844), ThemeMode.dark, 1.4),
    ('tablet', const Size(850, 1000), ThemeMode.light, 1.0),
    ('compact-desktop', const Size(900, 760), ThemeMode.dark, 1.0),
  ]) {
    testWidgets('${scenario.$1} keeps navigation and content usable', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.$2;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final host = PreviewHost()..themeMode = scenario.$3;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ProviderScope(
            overrides: [hostProvider.overrideWith((ref) => host)],
            child: const HostCraftApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (capture) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('build/design-review/${scenario.$1}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final navigation = scenario.$2.width > 850
          ? find.byType(NavigationRail)
          : find.byType(NavigationBar);
      for (final label in ['Console', 'Network', 'Settings', 'Overview']) {
        await tester.tap(
          find.descendant(of: navigation, matching: find.text(label)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${scenario.$1}: $label',
        );
      }
      if (scenario.$2.width <= 850) {
        await tester.tap(find.byTooltip('Server tools'));
        await tester.pumpAndSettle();
        expect(find.text('Mods & plugins'), findsOneWidget);
        expect(find.text('Server files'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('server actions reflect ready, running and busy states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = PreviewHost()
      ..phase = ServerPhase.ready
      ..profile = const ServerProfile(eulaAccepted: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostProvider.overrideWith((ref) => host)],
        child: const HostCraftApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start server'),
          )
          .onPressed,
      isNotNull,
    );
    host.phase = ServerPhase.running;
    host.changed();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Stop server'),
          )
          .onPressed,
      isNotNull,
    );
    host.phase = ServerPhase.stopping;
    host.changed();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Stop server'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
