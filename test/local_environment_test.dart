import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/services/download_service.dart';
import 'package:hostcraft/services/local_environment.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'dotenv preserves literal key characters and supports quotes/comments',
    () {
      expect(
        LocalEnvironment.parseCurseForgeKey(
          r'CURSEFORGE_API_KEY=$2a$key=value',
        ),
        r'$2a$key=value',
      );
      expect(
        LocalEnvironment.parseCurseForgeKey(
          'export CURSEFORGE_API_KEY="quoted#key" # comment',
        ),
        'quoted#key',
      );
      expect(
        LocalEnvironment.parseCurseForgeKey(
          "CURSEFORGE_API_KEY='single quoted'",
        ),
        'single quoted',
      );
      expect(
        LocalEnvironment.parseCurseForgeKey(
          '# comment\nOTHER=value\nCURSEFORGE_API_KEY=plain # comment',
        ),
        'plain',
      );
      expect(
        LocalEnvironment.parseCurseForgeKey('CURSEFORGE_API_KEY="unclosed'),
        '',
      );
    },
  );

  test(
    'process environment takes precedence, with ordered file fallback',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'hostcraft-env-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final first = Directory('${folder.path}/first')..createSync();
      final second = Directory('${folder.path}/second')..createSync();
      await File('${first.path}/.env')
          .writeAsString('CURSEFORGE_API_KEY=first');
      await File('${second.path}/.env')
          .writeAsString('CURSEFORGE_API_KEY=second');
      Future<String> read(Map<String, String> environment) =>
          LocalEnvironment.curseForgeKey(
            supportDirectory: folder,
            environment: environment,
            searchDirectories: [first, second],
          );
      expect(await read({'CURSEFORGE_API_KEY': 'process'}), 'process');
      expect(await read({}), 'first');
      await File('${first.path}/.env').writeAsString('CURSEFORGE_API_KEY=');
      expect(await read({}), 'second');
      await File('${second.path}/.env').delete();
      expect(await read({}), '');
    },
  );

  test('download key is scoped to HTTPS CurseForge CDN hosts', () {
    final download = DownloadService(curseForgeKey: 'test-key');
    expect(
      download.headers('https://edge.forgecdn.net/files/test.jar')['x-api-key'],
      'test-key',
    );
    for (final url in [
      'http://edge.forgecdn.net/files/test.jar',
      'https://forgecdn.net.example.org/test.jar',
      'https://notforgecdn.net/test.jar',
      'https://cdn.modrinth.com/test.jar',
    ]) {
      expect(download.headers(url).containsKey('x-api-key'), isFalse);
    }
  });

  test(
    'download redirects keep key on CDN and strip it on unrelated hosts',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'hostcraft-download-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, isFalse);
        if (request.url.host == 'edge.forgecdn.net') {
          expect(request.headers['x-api-key'], 'test-key');
          return http.Response(
            '',
            302,
            headers: {'location': 'https://media.forgecdn.net/file.jar'},
          );
        }
        if (request.url.host == 'media.forgecdn.net') {
          expect(request.headers['x-api-key'], 'test-key');
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.org/file.jar'},
          );
        }
        expect(request.headers.containsKey('x-api-key'), isFalse);
        return http.Response(
          request.method == 'HEAD' ? '' : 'jar-content',
          200,
        );
      });
      addTearDown(client.close);
      final download = DownloadService(
        curseForgeKey: 'test-key',
        client: client,
      );
      final target = File('${folder.path}/test.jar');
      await download.file('https://edge.forgecdn.net/file.jar', target);
      expect(await target.readAsString(), 'jar-content');
      expect(requests.where((r) => r.method == 'HEAD'), hasLength(3));
      expect(requests.where((r) => r.method == 'GET'), hasLength(3));
    },
  );

  test(
    'download rejects insecure redirects without sending a credential',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'hostcraft-redirect-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        return http.Response(
          '',
          302,
          headers: {'location': 'http://edge.forgecdn.net/file.jar'},
        );
      });
      addTearDown(client.close);
      final download = DownloadService(
        curseForgeKey: 'test-key',
        client: client,
      );
      await expectLater(
        download.file(
          'https://edge.forgecdn.net/file.jar',
          File('${folder.path}/test.jar'),
        ),
        throwsA(isA<HttpException>()),
      );
    },
  );
}
