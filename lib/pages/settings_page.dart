import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/clash_service.dart';
import '../services/web_panel_service.dart';
import '../main.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;

  bool _developerMode = false;
  bool _showBall = false;
  bool _showLogs = false;

  String? _webPanelVersion;
  bool _checkingUpdate = false;
  WebPanelVersionInfo? _latestVersionInfo;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _updateMessage;
  bool _updateMessageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final panelVersion = await WebPanelService.getInstalledVersion();
    if (mounted) {
      setState(() {
        _hostController.text = prefs.getString('clash_host') ?? '';
        _tokenController.text = prefs.getString('clash_token') ?? '';
        _developerMode = prefs.getBool('developer_mode') ?? false;
        _showBall = prefs.getBool('show_floating_ball') ?? false;
        _showLogs = prefs.getBool('show_logs') ?? false;
        _webPanelVersion = panelVersion;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _latestVersionInfo = null;
      _updateMessage = null;
    });
    try {
      final info = await WebPanelService.checkLatest();
      if (!mounted) return;
      setState(() {
        _latestVersionInfo = info;
        if (info.tag == _webPanelVersion) {
          _updateMessage = '当前已是最新版本 ${info.tag}';
          _updateMessageIsError = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateMessage = '检查失败：$e';
        _updateMessageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _doUpdate() async {
    if (_latestVersionInfo == null) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _updateMessage = null;
    });
    try {
      await WebPanelService.downloadAndInstall(
        _latestVersionInfo!,
        (p) { if (mounted) setState(() => _downloadProgress = p); },
      );
      if (!mounted) return;
      setState(() {
        _webPanelVersion = _latestVersionInfo!.tag;
        _latestVersionInfo = null;
        _updateMessage = '更新成功，重新打开控制台即可生效';
        _updateMessageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateMessage = '下载失败：$e';
        _updateMessageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _toggleDeveloperMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('developer_mode', value);
    setState(() => _developerMode = value);
  }

  Future<void> _toggleShowBall(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_floating_ball', value);
    setState(() => _showBall = value);
    if (mounted) ProxlyApp.setBallVisibilityOf(context, value);
  }

  Future<void> _toggleShowLogs(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_logs', value);
    setState(() => _showLogs = value);
  }

  Future<void> _saveSettings() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先填写 OpenClash 地址'),
            backgroundColor: Color(0xFFE24B4A)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('clash_host', host);
      await prefs.setString('clash_token', _tokenController.text.trim());
      await ClashService.instance.loadConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('设置已保存'),
              backgroundColor: Color(0xFF1D9E75)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('保存失败：$e'),
              backgroundColor: const Color(0xFFE24B4A)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = '请先填写 Clash 控制器地址';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final token = _tokenController.text.trim();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final response = await http
          .get(Uri.parse('http://$host/version'), headers: headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _testSuccess = true;
          _testResult = '连接成功 · Clash ${data['version'] ?? '未知版本'}';
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _testSuccess = false;
          _testResult = '密钥错误，请检查后重试';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = '连接失败 · 状态码 ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = '无法连接，请检查地址是否正确';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF191E24) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);
    final inputBg = isDark ? const Color(0xFF1D232A) : const Color(0xFFF5F5F5);
    final labelColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final textColor = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cardBorder, width: 0.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF378ADD), width: 1),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设置',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 4),
            Text('填写你的 Clash 连接信息',
                style: TextStyle(fontSize: 13, color: hintColor)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder, width: 0.5)),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OpenClash 地址',
                      style: TextStyle(
                          fontSize: 11, color: labelColor, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hostController,
                    style: TextStyle(fontSize: 14, color: textColor),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: '请输入(IP:端口)',
                      hintStyle: TextStyle(color: hintColor),
                      filled: true,
                      fillColor: inputBg,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: focusedBorder,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('外部控制管理密钥',
                      style: TextStyle(
                          fontSize: 11, color: labelColor, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    style: TextStyle(fontSize: 14, color: textColor),
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: '请输入管理密钥',
                      hintStyle: TextStyle(color: hintColor),
                      filled: true,
                      fillColor: inputBg,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: focusedBorder,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureToken
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: hintColor,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _testing ? null : _testConnection,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder, width: 0.5)),
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF378ADD)))
                      : const Text('测试连接',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF378ADD))),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? const Color(0xFFF0FDF4)
                      : (isDark ? const Color(0xFF450a0a) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _testSuccess
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFE24B4A),
                      width: 0.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: _testSuccess
                                ? const Color(0xFF1D9E75)
                                : const Color(0xFFE24B4A),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_testResult!,
                            style: TextStyle(
                                fontSize: 13,
                                color: _testSuccess
                                    ? const Color(0xFF166534)
                                    : (isDark
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFF991B1B))))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _saving ? null : _saveSettings,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    color: const Color(0xFF378ADD),
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('保存',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // ── 控制台面板更新 ────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('控制台面板',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('版本来源',
                          style: TextStyle(fontSize: 13, color: textColor)),
                      const Spacer(),
                      Text(
                        _webPanelVersion ?? '内置版本',
                        style: TextStyle(fontSize: 12, color: hintColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_downloading) ...[
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _checkingUpdate ? null : _checkForUpdate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFF378ADD), width: 0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _checkingUpdate
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF378ADD)))
                                : const Text('检查更新',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF378ADD))),
                          ),
                        ),
                        if (_latestVersionInfo != null &&
                            _latestVersionInfo!.tag != _webPanelVersion) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '发现 ${_latestVersionInfo!.tag}',
                              style:
                                  TextStyle(fontSize: 12, color: hintColor),
                            ),
                          ),
                          GestureDetector(
                            onTap: _doUpdate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF378ADD),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('立即更新',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.white)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (_downloading) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: isDark
                            ? const Color(0xFF15191E)
                            : const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF378ADD)),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '正在下载… ${(_downloadProgress * 100).toInt()}%',
                      style: TextStyle(fontSize: 12, color: hintColor),
                    ),
                  ],
                  if (_updateMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _updateMessage!,
                      style: TextStyle(
                          fontSize: 12,
                          color: _updateMessageIsError
                              ? const Color(0xFFE24B4A)
                              : const Color(0xFF1D9E75)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ─────────────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('开发者选项',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('启用流量编辑',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    subtitle: Text('在首页长按提供商流量条可临时修改数值',
                        style: TextStyle(fontSize: 11, color: hintColor)),
                    value: _developerMode,
                    onChanged: _toggleDeveloperMode,
                    activeColor: const Color(0xFF378ADD),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: Text('显示主题悬浮球',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    subtitle: Text('屏幕上显示可拖动的深浅色切换按钮，长按拖动，点击切换',
                        style: TextStyle(fontSize: 11, color: hintColor)),
                    value: _showBall,
                    onChanged: _toggleShowBall,
                    activeColor: const Color(0xFF378ADD),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: Text('显示日志选项卡',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    subtitle: Text('在底部导航栏显示日志页面入口',
                        style: TextStyle(fontSize: 11, color: hintColor)),
                    value: _showLogs,
                    onChanged: _toggleShowLogs,
                    activeColor: const Color(0xFF378ADD),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── 关于 ──────────────────────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder, width: 0.5),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF378ADD).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.info_outline_rounded,
                          size: 18, color: Color(0xFF378ADD)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('关于 Proxly',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textColor)),
                          const SizedBox(height: 2),
                          Text('功能介绍、版本日志、开源协议',
                              style: TextStyle(
                                  fontSize: 11, color: hintColor)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: hintColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
