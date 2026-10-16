import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/services/device_service.dart';
import 'package:hostcraft/services/playit_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('agentRunData sends the agent key and parses tunnels', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/agents/rundata');
      expect(request.headers['Authorization'], 'Agent-Key abc123');
      return _json({
        'status': 'success',
        'data': {
          'agent_id': 'agent-1',
          'agent_type': 'assignable',
          'account_status': 'ready',
          'tunnels': [
            {
              'id': 'tunnel-1',
              'name': 'HostCraft',
              'ip_num': 1,
              'region_num': 1,
              'port': {'from': 25565, 'to': 25565},
              'proto': 'tcp',
              'local_ip': '127.0.0.1',
              'local_port': 25565,
              'tunnel_type': 'minecraft-java',
              'assigned_domain': 'quiet-fox.craft.playit.gg',
              'custom_domain': null,
              'disabled': null,
            },
          ],
          'pending': [],
        },
      });
    });
    final data = await PlayitApi(secret: 'abc123', client: client).agentRunData();
    expect(data.agentId, 'agent-1');
    expect(data.tunnels, hasLength(1));
    final tunnel = data.tunnels.single;
    expect(tunnel.localPort, 25565);
    expect(tunnel.carriesTcp, isTrue);
    expect(tunnel.disabled, isFalse);
    expect(tunnel.fallbackAddress, 'quiet-fox.craft.playit.gg:25565');
  });

  test('createMinecraftTunnel posts an agent-origin tcp tunnel', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      expect(request.url.path, '/tunnels/create');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'status': 'success',
        'data': {'id': 'new-tunnel'},
      });
    });
    final id = await PlayitApi(secret: 'abc123', client: client)
        .createMinecraftTunnel(agentId: 'agent-1', localPort: 25570);
    expect(id, 'new-tunnel');
    expect(sent['tunnel_type'], 'minecraft-java');
    expect(sent['port_type'], 'tcp');
    expect(sent['port_count'], 1);
    expect(sent['enabled'], true);
    expect(sent['origin'], {
      'type': 'agent',
      'data': {
        'agent_id': 'agent-1',
        'local_ip': '127.0.0.1',
        'local_port': 25570,
      },
    });
  });

  test('claim flow uses the claim endpoints without a key', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.headers.containsKey('Authorization'), isFalse);
      if (request.url.path == '/claim/setup') {
        return _json({'status': 'success', 'data': 'UserAccepted'});
      }
      return _json({
        'status': 'success',
        'data': {'secret_key': 'deadbeef'},
      });
    });
    final api = PlayitApi(client: client);
    expect(await api.claimSetup('0011223344', version: 'hostcraft test'), 'UserAccepted');
    expect(await api.claimExchange('0011223344'), 'deadbeef');
    expect(paths, ['/claim/setup', '/claim/exchange']);
  });

  test('rejected keys are reported as auth errors', () async {
    final client = MockClient(
      (_) async => _json({
        'status': 'error',
        'data': {'type': 'auth', 'message': 'InvalidAgentKey'},
      }, 401),
    );
    await expectLater(
      PlayitApi(secret: 'bad', client: client).agentRunData(),
      throwsA(isA<PlayitApiException>().having((e) => e.auth, 'auth', isTrue)),
    );
  });

  test('claim failures expose their code and network errors are flagged', () async {
    final failing = MockClient(
      (_) async => _json({'status': 'fail', 'data': 'NotAccepted'}, 400),
    );
    await expectLater(
      PlayitApi(client: failing).claimExchange('0011223344'),
      throwsA(
        isA<PlayitApiException>().having((e) => e.code, 'code', 'NotAccepted'),
      ),
    );
    final offline = MockClient((_) async => throw http.ClientException('offline'));
    await expectLater(
      PlayitApi(secret: 'abc', client: offline).agentRunData(),
      throwsA(
        isA<PlayitApiException>().having((e) => e.network, 'network', isTrue),
      ),
    );
  });

  test('device memory limits follow the installed RAM', () {
    expect(DeviceService.roundDownToStep(5700), 5632);
    expect(DeviceService.maxHeapMb(5632), 5632);
    expect(DeviceService.maxHeapMb(16384), 16384);
    expect(DeviceService.clampHeapMb(9000, 4096), 4096);
    expect(DeviceService.clampHeapMb(100, 4096), DeviceService.minMemoryMb);
    expect(DeviceService.defaultHeapMb(65536), 2048);
  });
}
