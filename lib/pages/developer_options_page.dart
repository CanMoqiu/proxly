import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  bool _developerMode = false;
  bool _showBall = false;
  bool _showLogs = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _developerMode = prefs.getBool('developer_mode') ?? false;
        _showBall = prefs.getBool('show_floating_ball') ?? false;
        _showLogs = prefs.getBool('show_logs') ?? false;
        _loaded = true;
      });
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
    final dividerColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
    final textColor = isDark ? const Color(0xFFE1E1E1) : const Color(0xFF1C1B1F);
    final hintColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6E6E6E);

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
        title: Text(
          '开发者选项',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder, width: 0.5),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: Text('启用流量编辑',
                    style: TextStyle(fontSize: 13, color: textColor)),
                subtitle: Text('在首页长按提供商流量条可临时修改数值',
                    style: TextStyle(fontSize: 11, color: hintColor)),
                value: _developerMode,
                onChanged: _toggleDeveloperMode,
                activeColor: const Color(0xFF1A73E8),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              Divider(height: 0, color: cardBorder),
              SwitchListTile(
                title: Text('显示主题悬浮球',
                    style: TextStyle(fontSize: 13, color: textColor)),
                subtitle: Text('屏幕上显示可拖动的深浅色切换按钮，长按拖动，点击切换',
                    style: TextStyle(fontSize: 11, color: hintColor)),
                value: _showBall,
                onChanged: _toggleShowBall,
                activeColor: const Color(0xFF1A73E8),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              Divider(height: 0, color: cardBorder),
              SwitchListTile(
                title: Text('显示日志选项卡',
                    style: TextStyle(fontSize: 13, color: textColor)),
                subtitle: Text('在底部导航栏显示日志页面入口',
                    style: TextStyle(fontSize: 11, color: hintColor)),
                value: _showLogs,
                onChanged: _toggleShowLogs,
                activeColor: const Color(0xFF1A73E8),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
