import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum _UpdateState {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  failed,
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _version = '26.2.2';
  static const _appName = 'Proxly';
  static const _description =
      'Proxly 是一款专为 OpenClash / Mihomo 设计的 Android 监控面板，'
      '让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。';
  static const _githubRepo = 'CanMoqiu/proxly';

  _UpdateState _updateState = _UpdateState.idle;
  double _downloadProgress = 0;
  String? _latestTag;
  String? _apkUrl;

  Future<void> _checkUpdate() async {
    if (_updateState == _UpdateState.checking ||
        _updateState == _UpdateState.downloading ||
        _updateState == _UpdateState.installing) {
      return;
    }
    setState(() => _updateState = _UpdateState.checking);
    try {
      final res = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_githubRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String? ?? '';
      final currentTag = 'v$_version';
      if (tag.isEmpty || tag == currentTag) {
        setState(() => _updateState = _UpdateState.upToDate);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _updateState = _UpdateState.idle);
        });
      } else {
        final assets =
            (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final apkAsset = assets.firstWhere(
          (a) => (a['name'] as String? ?? '').endsWith('.apk'),
          orElse: () => <String, dynamic>{},
        );
        setState(() {
          _latestTag = tag;
          _apkUrl = apkAsset['browser_download_url'] as String?;
          _updateState = _UpdateState.available;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _updateState = _UpdateState.failed);
    }
  }

  Future<void> _downloadAndInstall() async {
    final url = _apkUrl;
    if (url == null) return;
    setState(() {
      _updateState = _UpdateState.downloading;
      _downloadProgress = 0;
    });
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      final total = response.contentLength ?? -1;
      int received = 0;
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      }
      client.close();
      if (!mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/proxly-update.apk');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _updateState = _UpdateState.installing);
      await OpenFile.open(file.path);
    } catch (_) {
      if (mounted) setState(() => _updateState = _UpdateState.failed);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildUpdateButton(Color hintColor) {
    const blue = Color(0xFF378ADD);
    const red = Color(0xFFE24B4A);

    Widget pill({
      required Color borderColor,
      Color? fillColor,
      required Widget child,
      VoidCallback? onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: child,
        ),
      );
    }

    Widget row(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);

    switch (_updateState) {
      case _UpdateState.idle:
        return pill(
          borderColor: blue,
          onTap: _checkUpdate,
          child: const Text('检查更新',
              style: TextStyle(fontSize: 13, color: blue)),
        );
      case _UpdateState.checking:
        return pill(
          borderColor: hintColor,
          child: row([
            SizedBox(
              width: 12,
              height: 12,
              child:
                  CircularProgressIndicator(strokeWidth: 1.5, color: hintColor),
            ),
            const SizedBox(width: 6),
            Text('检查中…', style: TextStyle(fontSize: 13, color: hintColor)),
          ]),
        );
      case _UpdateState.upToDate:
        return pill(
          borderColor: hintColor,
          child: row([
            Icon(Icons.check_rounded, size: 14, color: hintColor),
            const SizedBox(width: 4),
            Text('无更新', style: TextStyle(fontSize: 13, color: hintColor)),
          ]),
        );
      case _UpdateState.available:
        return pill(
          borderColor: blue,
          fillColor: blue,
          onTap: _downloadAndInstall,
          child: row([
            const Icon(Icons.download_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text('下载中 $_latestTag',
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ]),
        );
      case _UpdateState.downloading:
        return Column(
          children: [
            pill(
              borderColor: blue,
              child: row([
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: blue,
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _downloadProgress > 0
                      ? '${(_downloadProgress * 100).toInt()}%'
                      : '连接中…',
                  style: const TextStyle(fontSize: 13, color: blue),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  backgroundColor: blue.withValues(alpha: 0.15),
                  color: blue,
                  minHeight: 3,
                ),
              ),
            ),
          ],
        );
      case _UpdateState.installing:
        return pill(
          borderColor: hintColor,
          child: row([
            SizedBox(
              width: 12,
              height: 12,
              child:
                  CircularProgressIndicator(strokeWidth: 1.5, color: hintColor),
            ),
            const SizedBox(width: 6),
            Text('准备安装…', style: TextStyle(fontSize: 13, color: hintColor)),
          ]),
        );
      case _UpdateState.failed:
        return pill(
          borderColor: red,
          onTap: _checkUpdate,
          child: const Text('检查失败，请重试',
              style: TextStyle(fontSize: 13, color: red)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1D232A) : const Color(0xFFFAFAFA);
    final cardBg = isDark ? const Color(0xFF191E24) : Colors.white;
    final cardBorder =
        isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);
    final textColor =
        isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor =
        isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final dividerColor =
        isDark ? const Color(0xFF2A3140) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('关于',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
        children: [
          // ── App 标识 ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF378ADD).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF378ADD).withValues(alpha: 0.25),
                        width: 0.8),
                  ),
                  child: const Icon(Icons.hub_rounded,
                      size: 38, color: Color(0xFF378ADD)),
                ),
                const SizedBox(height: 14),
                Text(_appName,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: textColor)),
                const SizedBox(height: 4),
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(const ClipboardData(text: _version));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('版本号已复制'),
                      duration: Duration(seconds: 1),
                    ));
                  },
                  child: Text('版本 $_version',
                      style: TextStyle(fontSize: 13, color: hintColor)),
                ),
                const SizedBox(height: 12),
                _buildUpdateButton(hintColor),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: hintColor, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 链接 ──
          _SectionTitle('链接', textColor),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              child: Column(
                children: [
                  _LinkRow(
                    icon: Icons.menu_book_outlined,
                    title: '功能介绍',
                    subtitle: '在 GitHub 查看完整功能说明',
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () =>
                        _openUrl('https://github.com/$_githubRepo#readme'),
                    isLast: false,
                  ),
                  _LinkRow(
                    icon: Icons.history_rounded,
                    title: '更新日志',
                    subtitle: '在 GitHub Releases 查看所有版本',
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () => _openUrl(
                        'https://github.com/$_githubRepo/releases'),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 开源协议 ──
          _SectionTitle('开源协议', textColor),
          const SizedBox(height: 10),
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
                Text('MIT License',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor)),
                const SizedBox(height: 8),
                Text(
                  'Copyright © 2026 Proxly\n\n'
                  '本软件以 MIT 协议开源，允许任何人免费使用、复制、修改、合并、'
                  '发布、分发、再授权及销售本软件的副本，但须保留上述版权声明与本许可声明。\n\n'
                  '本软件按"原样"提供，不附带任何明示或暗示的担保。',
                  style: TextStyle(fontSize: 12, color: hintColor, height: 1.65),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 第三方依赖 ──
          _SectionTitle('第三方依赖', textColor),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            child: const Column(
              children: [
                _DepRow('Zashboard', 'MIT · Zephyruso'),
                _DepRow('flutter_inappwebview', 'Apache-2.0'),
                _DepRow('dartssh2', 'MIT'),
                _DepRow('archive', 'BSD-3-Clause'),
                _DepRow('path_provider', 'BSD-3-Clause'),
                _DepRow('shared_preferences', 'BSD-3-Clause'),
                _DepRow('flutter_svg', 'MIT'),
                _DepRow('http', 'BSD-3-Clause'),
                _DepRow('open_file', 'MIT'),
                _DepRow('url_launcher', 'BSD-3-Clause', isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 底部声明 ──
          Center(
            child: Text(
              'Proxly 与 Clash / OpenClash / Mihomo 项目无官方关联',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 小组件 ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      );
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color hintColor;
  final Color dividerColor;
  final VoidCallback onTap;
  final bool isLast;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.hintColor,
    required this.dividerColor,
    required this.onTap,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF378ADD).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: const Color(0xFF378ADD)),
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
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11, color: hintColor)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: hintColor),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: dividerColor),
      ],
    );
  }
}

class _DepRow extends StatelessWidget {
  final String name;
  final String license;
  final bool isLast;
  const _DepRow(this.name, this.license, {this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor =
        isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final dividerColor =
        isDark ? const Color(0xFF2A3140) : const Color(0xFFE2E8F0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                  child: Text(name,
                      style: TextStyle(fontSize: 13, color: textColor))),
              Text(license, style: TextStyle(fontSize: 11, color: hintColor)),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: dividerColor),
      ],
    );
  }
}
