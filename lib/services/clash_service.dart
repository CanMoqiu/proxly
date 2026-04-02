import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class ClashConfig {
  final String host;
  final String token;

  const ClashConfig({required this.host, required this.token});

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
}

class ProviderTraffic {
  final String name;
  final int used;
  final int total;

  const ProviderTraffic({
    required this.name,
    required this.used,
    required this.total,
  });

  double get percentage => total > 0 ? used / total : 0;
}

class ConnectionEntry {
  final String id;
  final String sourceIp;
  final String sourcePort;
  final String host;
  final String sniffHost;
  final String destinationIp;
  final String destinationPort;
  final String remoteDestination;
  final String network;
  final String type;
  final String chain;
  final List<String> chainList;
  final List<String> providerChains;
  final String rule;
  final String inboundName;
  final String inboundIp;
  final String inboundPort;
  final String process;
  final String dnsMode;
  final DateTime startTime;
  final int upload;
  final int download;
  final int apiUpSpeed;
  final int apiDownSpeed;

  const ConnectionEntry({
    required this.id,
    required this.sourceIp,
    required this.sourcePort,
    required this.host,
    required this.sniffHost,
    required this.destinationIp,
    required this.destinationPort,
    required this.remoteDestination,
    required this.network,
    required this.type,
    required this.chain,
    required this.chainList,
    required this.providerChains,
    required this.rule,
    required this.inboundName,
    required this.inboundIp,
    required this.inboundPort,
    required this.process,
    required this.dnsMode,
    required this.startTime,
    required this.upload,
    required this.download,
    required this.apiUpSpeed,
    required this.apiDownSpeed,
  });
}

class ClashService {
  static ClashService? _instance;
  static ClashService get instance => _instance ??= ClashService._();
  ClashService._();

  ClashConfig? _config;

  Future<void> loadConfig() async {
    const storage = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('clash_host') ?? '';
    final token = await storage.read(key: 'clash_token') ?? '';
    _config = host.isNotEmpty ? ClashConfig(host: host, token: token) : null;
  }

  bool get isConfigured => _config != null;

  Future<T> _get<T>(String path, T Function(Map<String, dynamic>) parser) async {
    if (_config == null) throw Exception('未配置 Clash 地址');
    final uri = Uri.parse('http://${_config!.host}$path');
    final response = await http
        .get(uri, headers: _config!.headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      return parser(jsonDecode(response.body));
    } else if (response.statusCode == 401) {
      throw Exception('Token 错误');
    } else {
      throw Exception('请求失败 ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getTrafficSnapshot() async {
    return _get('/connections', (data) {
      final conns = data['connections'] as List? ?? [];
      return {
        'downloadTotal': data['downloadTotal'] ?? 0,
        'uploadTotal': data['uploadTotal'] ?? 0,
        'count': conns.length,
        'connections': conns.map((c) {
          final meta = c['metadata'] as Map<String, dynamic>? ?? {};
          final host = (meta['host'] as String?)?.isNotEmpty == true
              ? meta['host'] as String
              : '${meta['destinationIP'] ?? ''}:${meta['destinationPort'] ?? ''}';
          final network = (meta['network'] as String? ?? 'tcp').toUpperCase();
          final chains = (c['chains'] as List? ?? []).cast<String>();
          final chainStr = chains.length > 1
              ? chains.reversed.join(' → ')
              : chains.isNotEmpty ? chains.first : 'DIRECT';
          final rule = c['rule'] as String? ?? '';
          final rulePayload = c['rulePayload'] as String? ?? '';
          final ruleDisplay = rule.isNotEmpty && rulePayload.isNotEmpty
              ? '$rule: $rulePayload'
              : rule;
          final id = c['id'] as String? ?? '';
          final sourceIp = meta['sourceIP'] as String? ?? '';
          final sourcePort = (meta['sourcePort'] ?? '').toString();
          final destinationIp = meta['destinationIP'] as String? ?? '';
          final destinationPort = (meta['destinationPort'] ?? '').toString();
          final remoteDestination = meta['remoteDestination'] as String? ?? '';
          final sniffHost = meta['sniffHost'] as String? ?? '';
          final type = meta['type'] as String? ?? '';
          final inboundName = meta['inboundName'] as String? ?? '';
          final inboundIp = meta['inboundIP'] as String? ?? '';
          final inboundPort = (meta['inboundPort'] ?? '').toString();
          final process = meta['process'] as String? ?? '';
          final dnsMode = meta['dnsMode'] as String? ?? '';
          final chainList = chains.isEmpty
              ? ['DIRECT']
              : chains.length == 1
                  ? chains.toList()
                  : chains.reversed.toList();
          final providerChains = (c['providerChains'] as List? ?? [])
              .map((e) => e?.toString() ?? '')
              .toList();
          final startStr = c['start'] as String? ?? '';
          final startTime = startStr.isNotEmpty
              ? DateTime.tryParse(startStr) ?? DateTime.now()
              : DateTime.now();
          final upload = c['upload'] as int? ?? 0;
          final download = c['download'] as int? ?? 0;
          final apiUpSpeed = c['uploadSpeed'] as int? ?? 0;
          final apiDownSpeed = c['downloadSpeed'] as int? ?? 0;
          return ConnectionEntry(
            id: id,
            sourceIp: sourceIp,
            sourcePort: sourcePort,
            host: host,
            sniffHost: sniffHost,
            destinationIp: destinationIp,
            destinationPort: destinationPort,
            remoteDestination: remoteDestination,
            network: network,
            type: type,
            chain: chainStr,
            chainList: chainList,
            providerChains: providerChains,
            rule: ruleDisplay,
            inboundName: inboundName,
            inboundIp: inboundIp,
            inboundPort: inboundPort,
            process: process,
            dnsMode: dnsMode,
            startTime: startTime,
            upload: upload,
            download: download,
            apiUpSpeed: apiUpSpeed,
            apiDownSpeed: apiDownSpeed,
          );
        }).toList(),
      };
    });
  }

  Future<void> closeConnection(String id) async {
    if (_config == null) return;
    final uri = Uri.parse('http://${_config!.host}/connections/$id');
    await http
        .delete(uri, headers: _config!.headers)
        .timeout(const Duration(seconds: 5));
  }

  Future<List<ProviderTraffic>> getProviderTraffic() async {
    try {
      return _get('/providers/proxies', (data) {
        final providers = data['providers'] as Map<String, dynamic>? ?? {};
        final result = <ProviderTraffic>[];
        providers.forEach((name, value) {
          final info = value as Map<String, dynamic>;
          final traffic = info['subscriptionInfo'] as Map<String, dynamic>?;
          if (traffic != null) {
            final upload = traffic['Upload'] as int? ?? 0;
            final download = traffic['Download'] as int? ?? 0;
            final total = traffic['Total'] as int? ?? 0;
            if (total > 0) {
              result.add(ProviderTraffic(name: name, used: upload + download, total: total));
            }
          }
        });
        return result;
      });
    } catch (_) {
      return [];
    }
  }

}
