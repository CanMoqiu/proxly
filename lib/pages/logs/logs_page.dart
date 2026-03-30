import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kernel_logs_tab.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _host = '';
  String _token = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _host = prefs.getString('clash_host') ?? '';
        _token = prefs.getString('clash_token') ?? '';
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);

    if (!_ready) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF378ADD)));
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text('日志',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: textPrimary)),
          ),
          Expanded(child: KernelLogsTab(host: _host, token: _token)),
        ],
      ),
    );
  }
}
