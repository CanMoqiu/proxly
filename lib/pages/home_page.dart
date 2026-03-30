import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/clash_service.dart';
import '../services/ssh_service.dart';
import '../widgets/traffic_edit_dialog.dart';
import 'proxy_page.dart';
import '../widgets/connection_detail_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;
  Timer? _clockTimer;
  bool _loading = true;
  String? _error;

  int _activeConnections = 0;
  int _totalDownload = 0;
  int _totalUpload = 0;
  List<ProviderTraffic> _originalProviders = [];
  List<ProviderTraffic> _displayProviders = [];
  final Map<String, ProviderTraffic> _localOverrides = {};

  final List<double> _downloadSpeeds = List.filled(60, 0, growable: true);
  final List<double> _uploadSpeeds = List.filled(60, 0, growable: true);
  double _currentDownSpeed = 0;
  double _currentUpSpeed = 0;
  int _lastDownload = -1;
  int _lastUpload = -1;

  bool _developerMode = false;
  bool _restarting = false;
  String _restartStatus = '';
  List<ConnectionEntry> _connections = [];
  bool _connectionsExpanded = false;
  bool _chainFullDisplay = true;
  String _connSortBy = 'time_desc';
  String _filterIp = '';
  Map<String, int> _prevConnUpload = {};
  Map<String, int> _prevConnDownload = {};
  Map<String, int> _connUpSpeed = {};
  Map<String, int> _connDownSpeed = {};

  @override
  void initState() {
    super.initState();
    _loadDeveloperSettings();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connections.isNotEmpty) setState(() {});
    });
  }

  Future<void> _loadDeveloperSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _developerMode = prefs.getBool('developer_mode') ?? false;
        _chainFullDisplay = prefs.getBool('chain_full_display') ?? true;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _restartClash() async {
    if (_restarting) return;

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('clash_host') ?? '';
    final token = prefs.getString('clash_token') ?? '';
    if (host.isEmpty) {
      _showSnack('请先在设置页填写 Clash 地址', success: false);
      return;
    }
    final routerIp = host.contains(':') ? host.split(':')[0] : host;

    // 弹出 SSH 密码输入框
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _SshDialog(routerIp: routerIp),
    );
    if (password == null || !mounted) return;

    setState(() {
      _restarting = true;
      _restartStatus = '正在连接 SSH...';
      _error = null;
    });

    try {
      await SshService.execute(
          routerIp, password, '/etc/init.d/openclash restart');

      if (mounted) setState(() => _restartStatus = '等待 Clash 重新上线...');

      bool online = false;
      for (int i = 0; i < 30 && mounted; i++) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          final headers = token.isNotEmpty
              ? {'Authorization': 'Bearer $token'}
              : <String, String>{};
          final resp = await http
              .get(Uri.parse('http://$host/version'), headers: headers)
              .timeout(const Duration(seconds: 3));
          if (resp.statusCode == 200) {
            online = true;
            break;
          }
        } catch (_) {}
      }

      _showSnack(
        online ? 'OpenClash 重启成功' : '等待超时，请手动检查 Clash 状态',
        success: online,
      );
    } catch (e) {
      _showSnack('重启失败：$e', success: false);
    } finally {
      if (mounted) setState(() {
        _restarting = false;
        _restartStatus = '';
      });
    }
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor:
          success ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A),
    ));
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _lastDownload = -1;
      _lastUpload = -1;
      _localOverrides.clear();
    });
    await _fetchData();
  }

  Future<void> _fetchData() async {
    if (!ClashService.instance.isConfigured) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_restarting) _error = '请先在设置页填写 Clash 地址';
        });
      }
      return;
    }
    try {
      final results = await Future.wait([
        ClashService.instance.getTrafficSnapshot(),
        ClashService.instance.getProviderTraffic(),
      ]);

      final snapshot = results[0] as Map<String, dynamic>;
      final providers = results[1] as List<ProviderTraffic>;
      final connections = List<ConnectionEntry>.from(snapshot['connections'] as List? ?? []);

      // 计算每条连接的实时速度
      final newUpSpeed = <String, int>{};
      final newDownSpeed = <String, int>{};
      for (final c in connections) {
        final prevUp = _prevConnUpload[c.id];
        final prevDown = _prevConnDownload[c.id];
        if (prevUp != null && prevDown != null) {
          newUpSpeed[c.id] = (c.upload - prevUp).clamp(0, 999999999);
          newDownSpeed[c.id] = (c.download - prevDown).clamp(0, 999999999);
        }
      }
      _prevConnUpload = {for (final c in connections) c.id: c.upload};
      _prevConnDownload = {for (final c in connections) c.id: c.download};

      final downTotal = snapshot['downloadTotal'] as int;
      final upTotal = snapshot['uploadTotal'] as int;

      double downSpeed = 0;
      double upSpeed = 0;
      if (_lastDownload >= 0) {
        downSpeed = (downTotal - _lastDownload).toDouble().clamp(0, double.infinity);
        upSpeed = (upTotal - _lastUpload).toDouble().clamp(0, double.infinity);
      }
      _lastDownload = downTotal;
      _lastUpload = upTotal;

      _downloadSpeeds.removeAt(0);
      _downloadSpeeds.add(downSpeed);
      _uploadSpeeds.removeAt(0);
      _uploadSpeeds.add(upSpeed);

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _activeConnections = snapshot['count'] as int;
          _totalDownload = downTotal;
          _totalUpload = upTotal;
          _originalProviders = providers;
          _applyLocalOverrides();
          _currentDownSpeed = downSpeed;
          _currentUpSpeed = upSpeed;
          _connections = connections;
          _connUpSpeed = newUpSpeed;
          _connDownSpeed = newDownSpeed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_restarting) _error = '错误：$e';
        });
      }
    }
  }

  void _applyLocalOverrides() {
    _displayProviders = _originalProviders.map((p) {
      return _localOverrides[p.name] ?? p;
    }).toList();
  }

  void _editProviderTraffic(ProviderTraffic provider) async {
    final currentData = _localOverrides[provider.name] ?? provider;

    final resultBytes = await showDialog<int>(
      context: context,
      builder: (ctx) => TrafficEditDialog(provider: currentData),
    );

    if (resultBytes != null) {
      setState(() {
        _localOverrides[provider.name] = ProviderTraffic(
          name: provider.name,
          used: resultBytes,
          total: currentData.total,
        );
        _applyLocalOverrides();
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String _formatSpeed(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)}B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB/s';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  String _formatElapsed(DateTime startTime) {
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inSeconds < 60) return '新连接';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}分钟前';
    return '${elapsed.inHours}小时前';
  }

  String get _connSortLabel {
    switch (_connSortBy) {
      case 'time_asc':       return '时间 旧→新';
      case 'down_desc':      return '下载量';
      case 'up_desc':        return '上传量';
      case 'down_speed_desc': return '下载速度';
      case 'up_speed_desc':  return '上传速度';
      default:               return '时间 新→旧';
    }
  }

  List<ConnectionEntry> get _filteredSortedConnections {
    var list = List<ConnectionEntry>.from(_connections);
    if (_filterIp.isNotEmpty) list = list.where((c) => c.sourceIp == _filterIp).toList();
    switch (_connSortBy) {
      case 'time_asc':
        list.sort((a, b) => a.startTime.compareTo(b.startTime));
        break;
      case 'down_desc':
        list.sort((a, b) => b.download.compareTo(a.download));
        break;
      case 'up_desc':
        list.sort((a, b) => b.upload.compareTo(a.upload));
        break;
      case 'down_speed_desc':
        list.sort((a, b) => (_connDownSpeed[b.id] ?? 0)
            .compareTo(_connDownSpeed[a.id] ?? 0));
        break;
      case 'up_speed_desc':
        list.sort((a, b) => (_connUpSpeed[b.id] ?? 0)
            .compareTo(_connUpSpeed[a.id] ?? 0));
        break;
      default:
        list.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF191E24) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF378ADD)));
    }

    if (_error != null && !_restarting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: textSecondary),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _fetchData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF378ADD),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('重试', style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ],
        ),
      );
    }

    double maxChartSpeed = [..._downloadSpeeds, ..._uploadSpeeds]
        .fold(0.0, (a, b) => a > b ? a : b);
    if (maxChartSpeed < 1024) maxChartSpeed = 1024;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF378ADD),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _restarting ? null : _restartClash,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF7C3AED)
                                .withValues(alpha: 0.3),
                            width: 0.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.refresh_rounded,
                              color: Color(0xFFA78BFA), size: 16),
                          SizedBox(width: 6),
                          Text('重启 Clash',
                              style: TextStyle(
                                  color: Color(0xFFA78BFA),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                  _DashboardButton(
                    color: textPrimary,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        PageRouteBuilder(
                          transitionDuration: const Duration(milliseconds: 260),
                          reverseTransitionDuration:
                              const Duration(milliseconds: 200),
                          pageBuilder: (_, __, ___) => const ProxyPage(),
                          transitionsBuilder: (_, animation, __, child) {
                            return FadeTransition(
                              opacity: CurvedAnimation(
                                  parent: animation, curve: Curves.easeOut),
                              child: SlideTransition(
                                position: Tween(
                                  begin: const Offset(0, 0.04),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic)),
                                child: child,
                              ),
                            );
                          },
                        ),
                      );
                      if (mounted) {
                        _lastDownload = -1;
                        _lastUpload = -1;
                        _fetchData();
                      }
                    },
                  ),
                ],
              ),
              if (_restarting) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                        width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFA78BFA)),
                      ),
                      const SizedBox(width: 10),
                      Text(_restartStatus,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFA78BFA))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              if (_displayProviders.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('流量信息',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
                      const SizedBox(height: 16),
                      ..._displayProviders.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;

                        final Color barColor;
                        if (p.percentage >= 0.8) {
                          barColor = const Color(0xFFE24B4A);
                        } else if (p.percentage >= 0.5) {
                          barColor = const Color(0xFFF59E0B);
                        } else {
                          barColor = const Color(0xFF1D9E75);
                        }

                        return Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: _developerMode ? () => _editProviderTraffic(p) : null,
                              child: Container(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(p.name,
                                                style: TextStyle(
                                                    fontSize: 12, color: textPrimary)),
                                            if (_developerMode &&
                                                _localOverrides.containsKey(p.name))
                                              Padding(
                                                padding: const EdgeInsets.only(left: 6),
                                                child: Icon(Icons.edit,
                                                    size: 12, color: textSecondary),
                                              ),
                                          ],
                                        ),
                                        Text(
                                            '${_formatBytes(p.used)} / ${_formatBytes(p.total)}',
                                            style: TextStyle(
                                                fontSize: 11, color: textSecondary)),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: p.percentage,
                                        backgroundColor: isDark
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFFF1F5F9),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(barColor),
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (i < _displayProviders.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                  height: 1,
                                  thickness: 0.5,
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder, width: 0.5),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('运行概览',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: '活跃连接',
                            value: '$_activeConnections',
                            cardBg:
                                isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F5F5),
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: '累计下载',
                            value: _formatBytes(_totalDownload),
                            valueColor: const Color(0xFF378ADD),
                            cardBg:
                                isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F5F5),
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: '累计上传',
                            value: _formatBytes(_totalUpload),
                            valueColor: const Color(0xFF1D9E75),
                            cardBg:
                                isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F5F5),
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 100,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 50,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatSpeed(maxChartSpeed),
                                    style:
                                        TextStyle(fontSize: 9, color: textSecondary)),
                                Text(_formatSpeed(maxChartSpeed * 0.75),
                                    style:
                                        TextStyle(fontSize: 9, color: textSecondary)),
                                Text(_formatSpeed(maxChartSpeed * 0.5),
                                    style:
                                        TextStyle(fontSize: 9, color: textSecondary)),
                                Text(_formatSpeed(maxChartSpeed * 0.25),
                                    style:
                                        TextStyle(fontSize: 9, color: textSecondary)),
                                Text('0B/s',
                                    style:
                                        TextStyle(fontSize: 9, color: textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CustomPaint(
                              size: const Size(double.infinity, 100),
                              painter: _SpeedChartPainter(
                                downloadSpeeds: _downloadSpeeds,
                                uploadSpeeds: _uploadSpeeds,
                                isDark: isDark,
                                maxSpeed: maxChartSpeed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 56),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('60s',
                              style: TextStyle(fontSize: 9, color: textSecondary)),
                          Text('30s',
                              style: TextStyle(fontSize: 9, color: textSecondary)),
                          Text('0s',
                              style: TextStyle(fontSize: 9, color: textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SpeedLegend(
                            color: const Color(0xFF378ADD),
                            label: '↓ ${_formatSpeed(_currentDownSpeed)}'),
                        const SizedBox(width: 24),
                        _SpeedLegend(
                            color: const Color(0xFF1D9E75),
                            label: '↑ ${_formatSpeed(_currentUpSpeed)}'),
                      ],
                    ),
                  ],
                ),
              ),
              if (_connections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 卡片标题栏：标题 + 展开按钮
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('出站链路',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => StatefulBuilder(
                                builder: (ctx, setDialogState) {
                                  final bg = isDark
                                      ? const Color(0xFF191E24)
                                      : Colors.white;
                                  return AlertDialog(
                                    backgroundColor: bg,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    title: Text('出站链路设置',
                                        style: TextStyle(
                                            fontSize: 15,
                                            color: textPrimary)),
                                    content: SwitchListTile(
                                      title: Text('完整链路',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: textPrimary)),
                                      subtitle: Text(
                                          '关闭后仅显示最终出站节点',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: textSecondary)),
                                      value: _chainFullDisplay,
                                      onChanged: (v) async {
                                        setState(() => _chainFullDisplay = v);
                                        setDialogState(() {});
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setBool('chain_full_display', v);
                                      },
                                      activeColor:
                                          const Color(0xFF378ADD),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx),
                                        child: const Text('关闭',
                                            style: TextStyle(
                                                color:
                                                    Color(0xFF378ADD))),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.tune_rounded,
                                  size: 18, color: textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_filteredSortedConnections.length > 10)
                            GestureDetector(
                              onTap: () => setState(() =>
                                  _connectionsExpanded = !_connectionsExpanded),
                              child: Row(
                                children: [
                                  Text(
                                    _connectionsExpanded
                                        ? '收起'
                                        : '全部 (${_filteredSortedConnections.length})',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF378ADD)),
                                  ),
                                  Icon(
                                    _connectionsExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    size: 16,
                                    color: const Color(0xFF378ADD),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 工具栏：排序 + 筛选
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            PopupMenuButton<String>(
                              initialValue: _connSortBy,
                              onSelected: (v) =>
                                  setState(() => _connSortBy = v),
                              color: isDark
                                  ? const Color(0xFF191E24)
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'time_desc',      child: Text('时间 新→旧',   style: TextStyle(fontSize: 13, color: textPrimary))),
                                PopupMenuItem(value: 'time_asc',       child: Text('时间 旧→新',   style: TextStyle(fontSize: 13, color: textPrimary))),
                                PopupMenuItem(value: 'down_desc',      child: Text('下载量 多→少', style: TextStyle(fontSize: 13, color: textPrimary))),
                                PopupMenuItem(value: 'up_desc',        child: Text('上传量 多→少', style: TextStyle(fontSize: 13, color: textPrimary))),
                                PopupMenuItem(value: 'down_speed_desc', child: Text('下载速度 快→慢', style: TextStyle(fontSize: 13, color: textPrimary))),
                                PopupMenuItem(value: 'up_speed_desc',  child: Text('上传速度 快→慢', style: TextStyle(fontSize: 13, color: textPrimary))),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sort,
                                        size: 13, color: textSecondary),
                                    const SizedBox(width: 4),
                                    Text(_connSortLabel,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: textSecondary)),
                                    Icon(Icons.arrow_drop_down,
                                        size: 14, color: textSecondary),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 设备 IP 筛选下拉菜单
                            () {
                              final active = _filterIp.isNotEmpty;
                              final ipOptions = _connections
                                  .map((c) => c.sourceIp)
                                  .where((s) => s.isNotEmpty)
                                  .toSet()
                                  .toList()
                                ..sort();
                              String display = active ? _filterIp : '设备IP';
                              if (display.length > 14) display = '${display.substring(0, 14)}…';
                              return PopupMenuButton<String>(
                                onSelected: (v) =>
                                    setState(() => _filterIp = v),
                                color: isDark
                                    ? const Color(0xFF191E24)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: '',
                                      child: Text('全部',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: textSecondary))),
                                  ...ipOptions.map((ip) => PopupMenuItem(
                                      value: ip,
                                      child: Text(ip,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: textPrimary)))),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0xFF378ADD)
                                            .withValues(alpha: 0.12)
                                        : isDark
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: active
                                          ? const Color(0xFF378ADD)
                                          : Colors.transparent,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(display,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: active
                                                  ? const Color(0xFF378ADD)
                                                  : textSecondary)),
                                      Icon(Icons.arrow_drop_down,
                                          size: 14,
                                          color: active
                                              ? const Color(0xFF378ADD)
                                              : textSecondary),
                                    ],
                                  ),
                                ),
                              );
                            }(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...() {
                        final filtered = _filteredSortedConnections;
                        final list = _connectionsExpanded
                            ? filtered
                            : filtered.take(10).toList();
                        final widgets = <Widget>[];
                        for (int i = 0; i < list.length; i++) {
                          final c = list[i];
                          final chainLower = c.chain.toLowerCase();
                          final chainColor = chainLower.contains('reject')
                              ? const Color(0xFFE24B4A)
                              : (chainLower.contains('direct') ||
                                      chainLower.contains('直连') ||
                                      chainLower.contains('本地'))
                                  ? const Color(0xFF1D9E75)
                                  : const Color(0xFF378ADD);
                          final upSpeed = _connUpSpeed[c.id] ?? 0;
                          final downSpeed = _connDownSpeed[c.id] ?? 0;
                          widgets.add(GestureDetector(
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height * 0.72,
                              ),
                              builder: (_) => ConnectionDetailSheet(
                                conn: c,
                                upSpeed: _connUpSpeed[c.id] ?? 0,
                                downSpeed: _connDownSpeed[c.id] ?? 0,
                              ),
                            ),
                            child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 第一行：来源 IP + 连接时间 + 关闭按钮
                                Row(
                                  children: [
                                    Text(c.sourceIp,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: textSecondary)),
                                    const Spacer(),
                                    Text(_formatElapsed(c.startTime),
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: textSecondary)),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        ClashService.instance
                                            .closeConnection(c.id)
                                            .catchError((_) {});
                                        setState(() => _connections
                                            .removeWhere((e) => e.id == c.id));
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.close,
                                            size: 14, color: textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // 第二行：目标主机
                                Text(c.host,
                                    style: TextStyle(
                                        fontSize: 12, color: textPrimary),
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                // 第三行：代理链路
                                Text(
                                  () {
                                    if (_chainFullDisplay) return c.chain;
                                    final parts = c.chain.split(' → ');
                                    if (parts.length <= 2) return c.chain;
                                    return '${parts.first} → ${parts.last}';
                                  }(),
                                  style: TextStyle(
                                      fontSize: 10, color: chainColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                // 第四行：规则 + 实时速度 + 累计流量
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(c.rule,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: textSecondary),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    Text(
                                      '↓${_formatSpeed(downSpeed.toDouble())} ↑${_formatSpeed(upSpeed.toDouble())}  ↓${_formatBytes(c.download)} ↑${_formatBytes(c.upload)}',
                                      style: TextStyle(
                                          fontSize: 10, color: textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            ),
                          ));
                          if (i < list.length - 1)
                            widgets.add(Divider(
                              height: 1,
                              thickness: 0.5,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ));
                        }
                        return widgets;
                      }(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SpeedLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _SpeedLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 2,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<double> downloadSpeeds;
  final List<double> uploadSpeeds;
  final bool isDark;
  final double maxSpeed;

  _SpeedChartPainter({
    required this.downloadSpeeds,
    required this.uploadSpeeds,
    required this.isDark,
    required this.maxSpeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final scale = maxSpeed > 0 ? (size.height - 4) / maxSpeed : 1.0;
    final step = size.width / (downloadSpeeds.length - 1);

    void drawLine(List<double> speeds, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < speeds.length; i++) {
        final x = i * step;
        final y = size.height - (speeds[i] * scale).clamp(0, size.height - 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawLine(downloadSpeeds, const Color(0xFF378ADD));
    drawLine(uploadSpeeds, const Color(0xFF1D9E75));
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) =>
      old.isDark != isDark ||
      old.maxSpeed != maxSpeed ||
      old.downloadSpeeds.last != downloadSpeeds.last ||
      old.uploadSpeeds.last != uploadSpeeds.last;
}

// ─── SSH 密码输入框 ────────────────────────────────────────────────────────────

class _SshDialog extends StatefulWidget {
  final String routerIp;
  const _SshDialog({required this.routerIp});

  @override
  State<_SshDialog> createState() => _SshDialogState();
}

class _SshDialogState extends State<_SshDialog> {
  late final TextEditingController _ctrl;
  bool _obscure = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ssh_password') ?? '';
    if (mounted) _ctrl.text = saved;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final password = _ctrl.text;
    if (password.isEmpty) return;
    setState(() => _connecting = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssh_password', password);
    if (mounted) Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF191E24) : Colors.white;
    final textColor = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final inputBg = isDark ? const Color(0xFF1D232A) : const Color(0xFFF5F5F5);
    final borderColor = isDark ? const Color(0xFF2A3140) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SSH 登录',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 4),
            Text('root@${widget.routerIp}',
                style: TextStyle(fontSize: 12, color: hintColor)),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              autofocus: true,
              style: TextStyle(fontSize: 14, color: textColor),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                hintText: '路由器密码',
                hintStyle: TextStyle(color: hintColor),
                filled: true,
                fillColor: inputBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor, width: 0.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor, width: 0.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: Color(0xFF378ADD), width: 1)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: hintColor),
                  onPressed: () =>
                      setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                          color: inputBg,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text('取消',
                              style: TextStyle(
                                  fontSize: 14, color: hintColor))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _connecting ? null : _confirm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                          color: const Color(0xFF378ADD),
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: _connecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('确认',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 控制台入口按钮 ────────────────────────────────────────────────────────────

class _DashboardButton extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;

  const _DashboardButton({required this.color, required this.onTap});

  @override
  State<_DashboardButton> createState() => _DashboardButtonState();
}

class _DashboardButtonState extends State<_DashboardButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.78)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: SvgPicture.asset(
            'assets/web_panel/icon.svg',
            width: 26,
            height: 26,
            colorFilter:
                ColorFilter.mode(widget.color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
