import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';
import 'proxy_page.dart';
import 'settings_page.dart';
import 'logs/logs_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _showLogs = prefs.getBool('show_logs') ?? false);
    }
  }

  List<Widget> get _pages {
    return [
      const HomePage(),
      const ProxyPage(asTab: true),
      if (_showLogs) const LogsPage(),
      const SettingsPage(),
    ];
  }

  List<BottomNavigationBarItem> get _navItems => [
        const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded), label: '首页'),
        const BottomNavigationBarItem(
            icon: Icon(Icons.hub_outlined),
            activeIcon: Icon(Icons.hub_rounded),
            label: '代理'),
        if (_showLogs)
          const BottomNavigationBarItem(
              icon: Icon(Icons.article_outlined),
              activeIcon: Icon(Icons.article_rounded),
              label: '日志'),
        const BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded), label: '设置'),
      ];

  int get _maxIndex => _showLogs ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: isDark ? const Color(0xFF191E24) : Colors.white,
        unselectedItemColor:
            isDark ? const Color(0xFF747E8B) : Colors.black54,
        currentIndex: _currentIndex,
        onTap: (index) async {
          setState(() => _currentIndex = index);
          final prefs = await SharedPreferences.getInstance();
          if (mounted) {
            final showLogs = prefs.getBool('show_logs') ?? false;
            setState(() {
              _showLogs = showLogs;
              if (_currentIndex > _maxIndex) _currentIndex = _maxIndex;
            });
          }
        },
        selectedItemColor: const Color(0xFF378ADD),
        items: _navItems,
      ),
    );
  }
}
