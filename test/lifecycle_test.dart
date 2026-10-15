import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/core/models.dart';
import 'package:hostcraft/services/minecraft_server.dart';
import 'package:hostcraft/services/runtime_service.dart';
import 'package:hostcraft/services/tunnel_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  setUpAll(() async {
    fixture = await Directory.systemTemp.createTemp('hostcraft-fixture-');
    final compile = await Process.run('javac', [
      '--release',
      '17',
      '-d',
      fixture.path,
      'test/fixtures/FakeServer.java',
    ]);
    expect(
      compile.exitCode,
      0,
      reason: 'JDK with javac is required: ${compile.stderr}',
    );
    final jar = await Process.run('jar', [
      'cfe',
      p.join(fixture.path, 'fake.jar'),
      'FakeServer',
      '-C',
      fixture.path,
      'FakeServer.class',
    ]);
    expect(jar.exitCode, 0, reason: '${jar.stderr}');
  });
  tearDownAll(() async {
    await fixture.delete(recursive: true);
  });
  test(
    'real subprocess streams commands, drains logs and stops gracefully',
    () async {
      final root = await Directory.systemTemp.createTemp('hostcraft-test-');
      final states = <ServerPhase>[];
      final lines = <String>[];
      final online = Completer<void>();
      final response = Completer<void>();
      final server = MinecraftGameServer(
        profile: const ServerProfile(),
        root: root,
        runtime: const JavaRuntime('java', {}),
        onPhase: (s) {
          states.add(s);
          if (s == ServerPhase.running && !online.isCompleted) {
            online.complete();
          }
        },
        onProgress: (_, _) {},
        onMetrics: (_, _) {},
      );
      final sub = server.consoleOutput.listen((line) {
        lines.add(line);
        if (line == 'Received: list' && !response.isCompleted) {
          response.complete();
        }
      });
      try {
        await server.directory.create(recursive: true);
        await File(p.join(fixture.path, 'fake.jar'))
            .copy(p.join(server.directory.path, 'server.jar'));
        await server.start();
        await online.future.timeout(const Duration(seconds: 15));
        await server.sendCommand('list');
        await response.future.timeout(const Duration(seconds: 5));
        await expectLater(
          server.sendCommand('say hi\nstop'),
          throwsArgumentError,
        );
        await server.stop();
        expect(
          states,
          containsAllInOrder([
            ServerPhase.starting,
            ServerPhase.running,
            ServerPhase.stopping,
            ServerPhase.ready,
          ]),
        );
        expect(lines, contains('World saved. Goodbye.'));
        await expectLater(server.sendCommand('list'), throwsStateError);
      } finally {
        await server.stop();
        await sub.cancel();
        await server.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test('unexpected process exit reports failure', () async {
    final root = await Directory.systemTemp.createTemp('hostcraft-crash-');
    final ready = Completer<void>();
    final failed = Completer<void>();
    final server = MinecraftGameServer(
      profile: const ServerProfile(),
      root: root,
      runtime: const JavaRuntime('java', {}),
      onPhase: (s) {
        if (s == ServerPhase.running && !ready.isCompleted) ready.complete();
        if (s == ServerPhase.failed && !failed.isCompleted) failed.complete();
      },
      onProgress: (_, _) {},
      onMetrics: (_, _) {},
    );
    try {
      await server.directory.create(recursive: true);
      await File(p.join(fixture.path, 'fake.jar'))
          .copy(p.join(server.directory.path, 'server.jar'));
      await server.start();
      await ready.future.timeout(const Duration(seconds: 15));
      await server.sendCommand('crash');
      await failed.future.timeout(const Duration(seconds: 5));
    } finally {
      await server.dispose();
      await root.delete(recursive: true);
    }
  });
  test(
    'prepare requires explicit consent before any server files are written',
    () async {
      final root = await Directory.systemTemp.createTemp('hostcraft-consent-');
      final server = MinecraftGameServer(
        profile: const ServerProfile(),
        root: root,
        onPhase: (_) {},
        onProgress: (_, _) {},
        onMetrics: (_, _) {},
      );
      await expectLater(server.prepare(), throwsStateError);
      expect(await root.list().isEmpty, isTrue);
      await server.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'tunnel address matches local port and excludes disabled/unrelated tunnels',
    () {
      expect(
        TunnelService.parseTunnelAddress(
          'friends.joinmc.link => 127.0.0.1:25565',
          25565,
        ),
        'friends.joinmc.link',
      );
      expect(
        TunnelService.parseTunnelAddress(
          'friends.joinmc.link => 127.0.0.1:25566',
          25565,
        ),
        isNull,
      );
      expect(
        TunnelService.parseTunnelAddress(
          'friends.joinmc.link => (disabled)',
          25565,
        ),
        isNull,
      );
      expect(
        TunnelService.parseTunnelAddress(
          'https://playit.gg/claim/example',
          25565,
        ),
        isNull,
      );
    },
  );
}
