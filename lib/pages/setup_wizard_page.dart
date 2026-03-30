import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/clash_service.dart';
import 'main_shell.dart';

/// 首次启动引导页：帮助新用户快速完成 Clash 连接配置。
/// 当 SharedPreferences 中 clash_host 为空时，由 main.dart 展示此页。
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key});

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void dispose() {
    _pageController.dispose();
    _hostController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _nextStep() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = 1);
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
    } catch (_) {
      setState(() {
        _testSuccess = false;
        _testResult = '无法连接，请检查地址是否正确';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _finish() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写 OpenClash 地址'),
          backgroundColor: Color(0xFFE24B4A),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('clash_host', host);
      await prefs.setString('clash_token', _tokenController.text.trim());
      await ClashService.instance.loadConfig();
      if (!mounted) return;
      // 配置保存完成，替换路由栈，进入主界面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: const Color(0xFFE24B4A),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  /// 跳过向导，直接进入主界面（不保存任何配置）
  void _skip() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1D232A) : const Color(0xFFFAFAFA);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomePage(onNext: _nextStep, onSkip: _skip),
            _ConfigPage(
              hostController: _hostController,
              tokenController: _tokenController,
              obscureToken: _obscureToken,
              onToggleObscure: () =>
                  setState(() => _obscureToken = !_obscureToken),
              testing: _testing,
              saving: _saving,
              testResult: _testResult,
              testSuccess: _testSuccess,
              onTest: _testConnection,
              onFinish: _finish,
            ),
          ],
        ),
      ),
      // 步骤指示器
      bottomNavigationBar: Container(
        height: 36,
        color: bgColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (i) {
            final active = i == _currentStep;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF378ADD)
                    : (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── 第一步：欢迎页 ────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _WelcomePage({required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // 应用图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF378ADD).withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: const Color(0xFF378ADD).withOpacity(0.25), width: 0.8),
            ),
            child: const Icon(Icons.hub_rounded,
                size: 42, color: Color(0xFF378ADD)),
          ),
          const SizedBox(height: 24),
          Text(
            '欢迎使用 Proxly',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Proxly 是专为 OpenClash / Mihomo 设计的 Android 监控面板，'
            '让你在手机上实时掌握代理状态、流量用量与连接详情。',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: hintColor, height: 1.65),
          ),
          const SizedBox(height: 32),
          // 功能亮点列表
          ..._highlights.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF378ADD).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(h.icon,
                          size: 19, color: const Color(0xFF378ADD)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.title,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textColor)),
                          Text(h.desc,
                              style:
                                  TextStyle(fontSize: 11, color: hintColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const Spacer(flex: 3),
          // 开始配置按钮
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: onNext,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF378ADD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    '开始配置',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 跳过按钮
          GestureDetector(
            onTap: onSkip,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '跳过',
                style: TextStyle(fontSize: 13, color: hintColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _highlights = [
    _Highlight(
      icon: Icons.bar_chart_rounded,
      title: '实时流量监控',
      desc: '速度图表、上传/下载总量，每秒刷新',
    ),
    _Highlight(
      icon: Icons.lan_outlined,
      title: '出站链路',
      desc: '查看所有活跃连接及完整代理链',
    ),
    _Highlight(
      icon: Icons.hub_outlined,
      title: '代理控制台',
      desc: '内置 Zashboard，切换代理节点',
    ),
  ];
}

class _Highlight {
  final IconData icon;
  final String title;
  final String desc;
  const _Highlight(
      {required this.icon, required this.title, required this.desc});
}

// ─── 第二步：连接配置页 ────────────────────────────────────────────────────────

class _ConfigPage extends StatelessWidget {
  final TextEditingController hostController;
  final TextEditingController tokenController;
  final bool obscureToken;
  final VoidCallback onToggleObscure;
  final bool testing;
  final bool saving;
  final String? testResult;
  final bool testSuccess;
  final VoidCallback onTest;
  final VoidCallback onFinish;

  const _ConfigPage({
    required this.hostController,
    required this.tokenController,
    required this.obscureToken,
    required this.onToggleObscure,
    required this.testing,
    required this.saving,
    required this.testResult,
    required this.testSuccess,
    required this.onTest,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF191E24) : Colors.white;
    final cardBorder =
        isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);
    final inputBg =
        isDark ? const Color(0xFF1D232A) : const Color(0xFFF5F5F5);
    final labelColor =
        isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final textColor =
        isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor =
        isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cardBorder, width: 0.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF378ADD), width: 1),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '连接配置',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 6),
          Text(
            '填写你的 OpenClash 控制器地址和密钥，稍后可在设置页随时修改',
            style: TextStyle(fontSize: 13, color: hintColor, height: 1.5),
          ),
          const SizedBox(height: 28),
          // ── 地址 + 密钥输入卡片 ──────────────────────────────────────────────
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
                  controller: hostController,
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
                Text('外部控制管理密钥',
                    style: TextStyle(
                        fontSize: 11, color: labelColor, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                TextField(
                  controller: tokenController,
                  obscureText: obscureToken,
                  style: TextStyle(fontSize: 14, color: textColor),
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: '请输入管理密钥（可选）',
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
                          obscureToken
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: hintColor,
                          size: 20),
                      onPressed: onToggleObscure,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 测试连接 ─────────────────────────────────────────────────────────
          GestureDetector(
            onTap: testing ? null : onTest,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder, width: 0.5)),
              padding: const EdgeInsets.all(14),
              child: Center(
                child: testing
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
          // ── 测试结果提示 ─────────────────────────────────────────────────────
          if (testResult != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: testSuccess
                    ? const Color(0xFFF0FDF4)
                    : (isDark
                        ? const Color(0xFF450a0a)
                        : const Color(0xFFFEF2F2)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: testSuccess
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFE24B4A),
                    width: 0.5),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: testSuccess
                              ? const Color(0xFF1D9E75)
                              : const Color(0xFFE24B4A),
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(testResult!,
                          style: TextStyle(
                              fontSize: 13,
                              color: testSuccess
                                  ? const Color(0xFF166534)
                                  : (isDark
                                      ? const Color(0xFFFCA5A5)
                                      : const Color(0xFF991B1B))))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // ── 完成按钮 ─────────────────────────────────────────────────────────
          GestureDetector(
            onTap: saving ? null : onFinish,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: const Color(0xFF378ADD),
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text(
                        '完成，进入应用',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '以上信息也可以在设置页随时修改',
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
          ),
        ],
      ),
    );
  }
}
