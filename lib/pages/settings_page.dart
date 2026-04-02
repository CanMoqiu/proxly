import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/clash_service.dart';
import '../services/web_panel_service.dart';
import 'about_page.dart';
import 'developer_options_page.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _builtinPanelVersion = 'v3.0.0';

  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;

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
        _webPanelVersion = panelVersion;
      });
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ProxlyApp.setThemeModeOf(context, mode); // 同步更新静态变量 + 触发父级重建
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await prefs.setString('theme_mode', str);
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
        if (info.tag == (_webPanelVersion ?? _builtinPanelVersion)) {
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('设置',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 24),

            // ── 外观主题卡片 ─────────────────────────────────────────────────
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
                  Text('外观主题',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor)),
                  const SizedBox(height: 14),
                  // 浅色 / 深色 按钮
                  Row(
                    children: [
                      _ThemeButton(
                        label: '浅色',
                        icon: Icons.light_mode_rounded,
                        selected: ProxlyApp.activeThemeMode == ThemeMode.light,
                        enabled: ProxlyApp.activeThemeMode != ThemeMode.system,
                        isDark: isDark,
                        onTap: () => _setTheme(ThemeMode.light),
                      ),
                      const SizedBox(width: 10),
                      _ThemeButton(
                        label: '深色',
                        icon: Icons.dark_mode_rounded,
                        selected: ProxlyApp.activeThemeMode == ThemeMode.dark,
                        enabled: ProxlyApp.activeThemeMode != ThemeMode.system,
                        isDark: isDark,
                        onTap: () => _setTheme(ThemeMode.dark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 跟随系统 开关
                  Row(
                    children: [
                      Text('跟随系统',
                          style: TextStyle(fontSize: 13, color: textColor)),
                      const Spacer(),
                      Switch(
                        value: ProxlyApp.activeThemeMode == ThemeMode.system,
                        onChanged: (v) => _setTheme(
                            v ? ThemeMode.system : ThemeMode.light),
                        activeColor: const Color(0xFF378ADD),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 连接配置卡片 ─────────────────────────────────────────────────
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('外部控制密钥（可选）',
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
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
                  // 测试结果内嵌
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _testSuccess
                                ? const Color(0xFF1D9E75)
                                : const Color(0xFFE24B4A),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _testSuccess
                                  ? const Color(0xFF1D9E75)
                                  : const Color(0xFFE24B4A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 按钮行
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _testing ? null : _testConnection,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFF378ADD), width: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF378ADD)))
                                  : const Text('测试连接',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF378ADD))),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _saving ? null : _saveSettings,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF378ADD),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('保存',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 控制台面板 ───────────────────────────────────────────────────
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
                  Row(
                    children: [
                      Text('控制台面板',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor)),
                      const Spacer(),
                      Text(
                        _webPanelVersion ?? _builtinPanelVersion,
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
                            _latestVersionInfo!.tag !=
                                (_webPanelVersion ?? _builtinPanelVersion)) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '发现 ${_latestVersionInfo!.tag}',
                              style: TextStyle(fontSize: 12, color: hintColor),
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
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF378ADD)),
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

            // ── 开发者选项（二级菜单） ────────────────────────────────────────
            _NavRow(
              icon: Icons.code_rounded,
              title: '开发者选项',
              subtitle: '调试与实验性功能',
              cardBg: cardBg,
              cardBorder: cardBorder,
              textColor: textColor,
              hintColor: hintColor,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DeveloperOptionsPage()),
              ),
            ),
            const SizedBox(height: 12),

            // ── 关于 ─────────────────────────────────────────────────────────
            _NavRow(
              icon: Icons.info_outline_rounded,
              title: '关于 Proxly',
              subtitle: '功能介绍、版本日志、开源协议',
              cardBg: cardBg,
              cardBorder: cardBorder,
              textColor: textColor,
              hintColor: hintColor,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 主题选择按钮 ────────────────────────────────────────────────────────────

class _ThemeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF378ADD);
    final disabledBg =
        isDark ? const Color(0xFF1D232A) : const Color(0xFFF5F5F5);
    final disabledText =
        isDark ? const Color(0xFF3A4250) : const Color(0xFFCBD5E1);

    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.12)
                : enabled
                    ? Colors.transparent
                    : disabledBg,
            border: Border.all(
              color: selected ? activeColor : disabledText,
              width: selected ? 1.2 : 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? activeColor
                      : enabled
                          ? (isDark
                              ? const Color(0xFF747E8B)
                              : const Color(0xFF94A3B8))
                          : disabledText),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? activeColor
                        : enabled
                            ? (isDark
                                ? const Color(0xFF747E8B)
                                : const Color(0xFF94A3B8))
                            : disabledText,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 通用导航行组件 ──────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder, width: 0.5),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF378ADD).withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF378ADD)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: hintColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: hintColor),
          ],
        ),
      ),
    );
  }
}
