import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error raised by the Playit API client.
///
/// [auth] is true when Playit rejected the saved agent key, [network] when the
/// API could not be reached at all (so a saved key must not be discarded).
class PlayitApiException implements Exception {
  const PlayitApiException(
    this.message, {
    this.code,
    this.auth = false,
    this.network = false,
  });
  final String message;
  final String? code;
  final bool auth;
  final bool network;
  @override
  String toString() => message;
}

/// A tunnel as reported by `/agents/rundata`.
class PlayitTunnel {
  const PlayitTunnel({
    required this.id,
    required this.name,
    required this.tunnelType,
    required this.protocol,
    required this.localIp,
    required this.localPort,
    required this.assignedDomain,
    required this.customDomain,
    required this.publicPort,
    required this.disabled,
  });
  final String id;
  final String name;
  final String? tunnelType;
  final String protocol;
  final String localIp;
  final int localPort;
  final String assignedDomain;
  final String? customDomain;
  final int publicPort;
  final bool disabled;

  bool get carriesTcp => protocol == 'tcp' || protocol == 'both';
  bool get carriesUdp => protocol == 'udp' || protocol == 'both';
  bool get ready =>
      assignedDomain.isNotEmpty || (customDomain ?? '').isNotEmpty;

  /// Address players type into Minecraft, built from the API fields. Used only
  /// when Playit's own `display_address` is not available.
  String get fallbackAddress {
    final domain = (customDomain ?? '').isNotEmpty
        ? customDomain!
        : assignedDomain;
    return publicPort > 0 ? '$domain:$publicPort' : domain;
  }

  factory PlayitTunnel.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    final disabled = json['disabled'];
    return PlayitTunnel(
      id: '${json['id']}',
      name: (json['name'] as String?) ?? '',
      tunnelType: json['tunnel_type'] as String?,
      protocol: (json['proto'] as String?) ?? 'tcp',
      localIp: (json['local_ip'] as String?) ?? '127.0.0.1',
      localPort: (json['local_port'] as num?)?.toInt() ?? 0,
      assignedDomain: (json['assigned_domain'] as String?) ?? '',
      customDomain: json['custom_domain'] as String?,
      publicPort: port is Map ? ((port['from'] as num?)?.toInt() ?? 0) : 0,
      disabled: disabled != null,
    );
  }
}

/// Snapshot of what Playit knows about the agent behind the saved key.
class PlayitRunData {
  const PlayitRunData({
    required this.agentId,
    required this.accountStatus,
    required this.tunnels,
  });
  final String agentId;
  final String accountStatus;
  final List<PlayitTunnel> tunnels;
}

/// Minimal Dart client for the playit.gg HTTP API.
///
/// Endpoints and payloads follow the OpenAPI description published in
/// https://github.com/playit-cloud/playit-api-java (claim setup/exchange,
/// agents/rundata, tunnels/create). The Playit agent process is still what
/// carries game traffic; this client only manages the account side so
/// HostCraft never has to scrape the agent's log output.
class PlayitApi {
  PlayitApi({
    this.secret,
    http.Client? client,
    this.base = 'https://api.playit.gg',
  }) : _client = client ?? http.Client();
  final String? secret;
  final String base;
  final http.Client _client;

  void close() => _client.close();

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'HostCraft',
      if (secret != null) 'Authorization': 'Agent-Key $secret',
    };
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$base$path'),
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const PlayitApiException(
        'Playit did not answer in time. Check your internet connection and try again.',
        network: true,
      );
    } catch (e) {
      throw PlayitApiException(
        'Cannot reach Playit (api.playit.gg). Check your internet connection. ($e)',
        network: true,
      );
    }
    if (response.statusCode == 429) {
      throw const PlayitApiException(
        'Playit is rate limiting requests. Wait a minute and try again.',
        network: true,
      );
    }
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (_) {
      throw PlayitApiException(
        'Unexpected answer from Playit (HTTP ${response.statusCode}).',
        network: response.statusCode >= 500,
      );
    }
    if (json is! Map) {
      throw PlayitApiException(
        'Unexpected answer from Playit (HTTP ${response.statusCode}).',
      );
    }
    final status = json['status'];
    final data = json['data'];
    if (status == 'success') return data;
    final isAuth =
        response.statusCode == 401 ||
        (status == 'error' && data is Map && data['type'] == 'auth');
    if (isAuth) {
      throw PlayitApiException(
        'Playit no longer accepts the saved account link.',
        code: data is Map ? '${data['message']}' : null,
        auth: true,
      );
    }
    if (status == 'fail') {
      throw PlayitApiException(_describe('$data'), code: '$data');
    }
    if (status == 'error' && data is Map) {
      final message = data['message'];
      throw PlayitApiException(
        'Playit: ${message ?? data['type'] ?? 'request failed'}',
        code: '${data['type']}',
      );
    }
    throw PlayitApiException(
      'Playit answered with HTTP ${response.statusCode}.',
    );
  }

  static String _describe(String code) => switch (code) {
    'InvalidCode' =>
      'Playit did not accept the link code. Try connecting again.',
    'CodeExpired' =>
      'The approval link expired. Connect again to get a new one.',
    'CodeNotFound' => 'Playit could not find the approval link. Connect again.',
    'UserRejected' => 'The link was declined in Playit.',
    'RequiresVerifiedAccount' => 'Your Playit account needs a verified email before it can create tunnels. Finish signing up at playit.gg, then connect again.',
    'RequiresPlayitPremium' => 'Playit says this tunnel needs Playit Premium (the free tunnel limit may be used up). Remove an unused tunnel at playit.gg or upgrade.',
    'InvalidPortCount' => 'Playit rejected the tunnel port count.',
    'AgentNotFound' || 'InvalidAgentId' => 'Playit does not know this agent any more. Unlink Playit and connect again.',
    'AgentVersionTooOld' => 'This Playit agent version is too old for the API.',
    'DefaultAgentNotSupported' =>
      'Playit does not allow creating tunnels for this kind of agent.',
    'InvalidTunnelName' => 'Playit rejected the tunnel name.',
    _ => 'Playit said: $code',
  };

  /// `/claim/setup`: registers a claim code and returns the user's progress:
  /// WaitingForUserVisit, WaitingForUser, UserAccepted or UserRejected.
  Future<String> claimSetup(String code, {required String version}) async {
    final data = await _post('/claim/setup', {
      'code': code,
      'agent_type': 'self-managed',
      'version': version,
    });
    return '$data';
  }

  /// `/claim/exchange`: trades an approved claim code for the agent secret.
  Future<String> claimExchange(String code) async {
    final data = await _post('/claim/exchange', {'code': code});
    if (data is Map && data['secret_key'] is String) {
      return data['secret_key'] as String;
    }
    throw const PlayitApiException('Playit did not return an agent key.');
  }

  /// `/agents/rundata`: the agent id plus every tunnel assigned to it.
  Future<PlayitRunData> agentRunData() async {
    final data = await _post('/agents/rundata');
    if (data is! Map) {
      throw const PlayitApiException('Playit returned unreadable agent data.');
    }
    final tunnels = <PlayitTunnel>[];
    final raw = data['tunnels'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          tunnels.add(PlayitTunnel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return PlayitRunData(
      agentId: '${data['agent_id']}',
      accountStatus: '${data['account_status']}',
      tunnels: tunnels,
    );
  }

  /// Public addresses exactly as the Playit agent displays them, keyed by
  /// tunnel id. Best effort: returns an empty map if the endpoint is not
  /// available, in which case [PlayitTunnel.fallbackAddress] is used.
  Future<Map<String, String>> displayAddresses() async {
    try {
      final data = await _post('/v1/agents/rundata');
      final result = <String, String>{};
      if (data is Map && data['tunnels'] is List) {
        for (final item in data['tunnels'] as List) {
          if (item is Map &&
              item['id'] != null &&
              item['display_address'] is String &&
              (item['display_address'] as String).isNotEmpty) {
            result['${item['id']}'] = item['display_address'] as String;
          }
        }
      }
      return result;
    } on PlayitApiException catch (e) {
      if (e.auth) rethrow;
      return const {};
    }
  }

  /// `/tunnels/create`: a tunnel that forwards to [localIp]:[localPort]
  /// through the agent [agentId]. Returns the tunnel id.
  ///
  /// Minecraft Java uses `minecraft-java` over `tcp`; Bedrock (Geyser) uses
  /// `minecraft-bedrock` over `udp`.
  Future<String> createTunnel({
    required String agentId,
    required int localPort,
    String tunnelType = 'minecraft-java',
    String portType = 'tcp',
    String localIp = '127.0.0.1',
    String name = 'HostCraft',
  }) async {
    final data = await _post('/tunnels/create', {
      'name': name,
      'tunnel_type': tunnelType,
      'port_type': portType,
      'port_count': 1,
      'origin': {
        'type': 'agent',
        'data': {
          'agent_id': agentId,
          'local_ip': localIp,
          'local_port': localPort,
        },
      },
      'enabled': true,
    });
    if (data is Map && data['id'] != null) return '${data['id']}';
    throw const PlayitApiException('Playit did not confirm the new tunnel.');
  }

  /// A TCP Minecraft Java tunnel.
  Future<String> createMinecraftTunnel({
    required String agentId,
    required int localPort,
    String localIp = '127.0.0.1',
    String name = 'HostCraft',
  }) => createTunnel(
    agentId: agentId,
    localPort: localPort,
    localIp: localIp,
    name: name,
  );
}
