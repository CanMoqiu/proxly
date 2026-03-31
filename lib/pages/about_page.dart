import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _version = '26.2.2';
  static const _appName = 'Proxly';
  static const _description = 'Proxly 是一款专为 OpenClash / Mihomo 设计的 Android 监控面板，'
      '让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。';

  static const _changelog = [
    _ChangelogItem(
      version: '26.2.2',
      date: '2026-04-01',
      items: [
        '代理页左上角新增规则视图入口，点击可在代理与规则之间切换',
      ],
    ),
    _ChangelogItem(
      version: '26.2.1',
      date: '2026-03-31',
      items: [
        '内置 Zashboard 更新至 v3.0.0',
        '代理页支持从 JSON 文件导入 Zashboard 配置',
        '修复首次安装控制台无限加载（屏蔽 Service Worker 在隐藏 WebView 中的注册）',
        '修复 Zashboard 用户配置重启后丢失',
        '修复 WebView 渲染掉帧',
        '修复开发者模式下流量编辑长按无响应',
        '开发者功能首次安装默认关闭',
      ],
    ),
    _ChangelogItem(
      version: '26.2',
      date: '2026-03-30',
      items: [
        '新设备首次启动显示设置向导，引导完成连接配置',
        '代理页迁移到底部导航栏，随时可访问',
        '支持在线下载并更新 Zashboard 控制台面板',
        '更新后自动保留 Zashboard 用户配置',
        '出站链路：连接详情弹窗，展示完整元数据',
        '出站链路：精简/完整链路切换（持久化）',
        '出站链路：实时时间刷新、按分钟显示',
        '关于页面',
      ],
    ),
    _ChangelogItem(
      version: '26.1',
      date: '2026-03-30',
      items: [
        '出站链路卡片：实时连接列表，支持排序与 IP 筛选',
        '每条连接显示代理链、规则、实时速度与累计流量',
        '长按提供商流量条可临时修改数值（开发者模式）',
        '控制台内置 Zashboard，支持深浅色主题同步',
        '悬浮主题切换球',
        '一键重启 Clash（SSH）',
        '修复 Jetifier / Manifest merger 编译问题',
      ],
    ),
  ];

  static const _features = [
    _Feature(
      icon: Icons.bar_chart_rounded,
      title: '实时流量监控',
      desc: '速度图表、累计上传/下载，每秒刷新',
    ),
    _Feature(
      icon: Icons.hub_outlined,
      title: '代理控制台',
      desc: '内置 Zashboard，支持在线更新面板版本',
    ),
    _Feature(
      icon: Icons.lan_outlined,
      title: '出站链路',
      desc: '实时连接列表，可查看完整代理链与元数据',
    ),
    _Feature(
      icon: Icons.data_usage_rounded,
      title: '订阅流量',
      desc: '展示各订阅剩余用量与到期时间',
    ),
    _Feature(
      icon: Icons.refresh_rounded,
      title: '一键重启',
      desc: '通过 SSH 远程重启 OpenClash 内核',
    ),
    _Feature(
      icon: Icons.article_outlined,
      title: '内核日志',
      desc: 'WebSocket 实时日志，支持级别筛选',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1D232A) : const Color(0xFFFAFAFA);
    final cardBg = isDark ? const Color(0xFF191E24) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);
    final textColor = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final dividerColor = isDark ? const Color(0xFF2A3140) : const Color(0xFFE2E8F0);

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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor)),
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
                    color: const Color(0xFF378ADD).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF378ADD).withOpacity(0.25),
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
                      style:
                          TextStyle(fontSize: 13, color: hintColor)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: hintColor,
                        height: 1.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 功能介绍 ──
          _SectionTitle('功能介绍', textColor),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            child: Column(
              children: List.generate(_features.length, (i) {
                final f = _features[i];
                final isLast = i == _features.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF378ADD).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(f.icon,
                                size: 18, color: const Color(0xFF378ADD)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.title,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: textColor)),
                                const SizedBox(height: 2),
                                Text(f.desc,
                                    style: TextStyle(
                                        fontSize: 11, color: hintColor)),
                              ],
                            ),
                          ),
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
              }),
            ),
          ),
          const SizedBox(height: 24),

          // ── 更新日志 ──
          _SectionTitle('更新日志', textColor),
          const SizedBox(height: 10),
          ..._changelog.map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF378ADD).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(log.version,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF378ADD))),
                          ),
                          const SizedBox(width: 8),
                          Text(log.date,
                              style: TextStyle(
                                  fontSize: 12, color: hintColor)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...log.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: hintColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(item,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: textColor,
                                          height: 1.5)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 12),

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
                  style: TextStyle(
                      fontSize: 12, color: hintColor, height: 1.65),
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
            child: Column(
              children: const [
                _DepRow('Zashboard', 'MIT · Zephyruso'),
                _DepRow('flutter_inappwebview', 'Apache-2.0'),
                _DepRow('dartssh2', 'MIT'),
                _DepRow('archive', 'BSD-3-Clause'),
                _DepRow('path_provider', 'BSD-3-Clause'),
                _DepRow('shared_preferences', 'BSD-3-Clause'),
                _DepRow('flutter_svg', 'MIT', isLast: true),
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

// ─── 数据模型 ──────────────────────────────────────────────────────────────────

class _ChangelogItem {
  final String version;
  final String date;
  final List<String> items;
  const _ChangelogItem(
      {required this.version, required this.date, required this.items});
}

class _Feature {
  final IconData icon;
  final String title;
  final String desc;
  const _Feature(
      {required this.icon, required this.title, required this.desc});
}

// ─── 小组件 ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color),
      );
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                  child: Text(name,
                      style: TextStyle(fontSize: 13, color: textColor))),
              Text(license,
                  style: TextStyle(fontSize: 11, color: hintColor)),
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
