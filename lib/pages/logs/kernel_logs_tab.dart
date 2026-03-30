import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KernelLogsTab extends StatefulWidget {
  final String host;
  final String token;

  const KernelLogsTab({super.key, required this.host, required this.token});

  @override
  State<KernelLogsTab> createState() => _KernelLogsTabState();
}

class _KernelLogsTabState extends State<KernelLogsTab>
    with AutomaticKeepAliveClientMixin {
  static const _maxEntries = 500;

  final List<_LogEntry> _entries = [];
  final ScrollController _scroll = ScrollController();

  WebSocket? _ws;
  bool _connected = false;
  bool _autoScroll = true;
  String _level = 'debug';
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _ws?.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    _ws?.close();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _error = null;
    });

    if (widget.host.isEmpty) {
      setState(() => _error = '请先在设置页填写 Clash 地址');
      return;
    }

    final tokenParam =
        widget.token.isNotEmpty ? '&token=${widget.token}' : '';
    final uri = 'ws://${widget.host}/logs?level=$_level$tokenParam';

    try {
      final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 6));
      if (!mounted) {
        ws.close();
        return;
      }
      _ws = ws;
      setState(() => _connected = true);

      ws.listen(
        (data) {
          if (!mounted) return;
          try {
            final map = jsonDecode(data as String) as Map<String, dynamic>;
            final entry = _LogEntry(
              type: map['type'] as String? ?? 'info',
              payload: map['payload'] as String? ?? '',
              time: DateTime.tryParse(map['time'] as String? ?? '') ??
                  DateTime.now(),
            );
            setState(() {
              _entries.add(entry);
              if (_entries.length > _maxEntries) _entries.removeAt(0);
            });
            if (_autoScroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
          } catch (_) {}
        },
        onDone: () {
          if (mounted) setState(() => _connected = false);
        },
        onError: (_) {
          if (mounted) setState(() => _connected = false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = '无法连接：$e');
    }
  }

  void _clear() => setState(() => _entries.clear());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);
    final cardBorder =
        isDark ? const Color(0xFF15191E) : const Color(0xFFE2E8F0);

    return Column(
      children: [
        // ── 工具栏 ───────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: cardBorder, width: 0.5)),
          ),
          child: Row(
            children: [
              // 日志级别选择
              _LevelPill(
                value: _level,
                onChanged: (v) {
                  setState(() => _level = v);
                  _connect();
                },
              ),
              const Spacer(),
              // 自动滚动开关
              GestureDetector(
                onTap: () => setState(() => _autoScroll = !_autoScroll),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom_rounded
                        : Icons.pause_rounded,
                    size: 20,
                    color: _autoScroll
                        ? const Color(0xFF378ADD)
                        : textSecondary,
                  ),
                ),
              ),
              // 清空日志
              GestureDetector(
                onTap: _clear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 20, color: textSecondary),
                ),
              ),
              // 重新连接
              GestureDetector(
                onTap: _connect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color:
                        _connected ? const Color(0xFF1D9E75) : textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── 状态 / 错误提示 ──────────────────────────────────────────────────
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!,
                style: TextStyle(
                    fontSize: 13, color: const Color(0xFFE24B4A))),
          ),

        // ── 日志列表 ─────────────────────────────────────────────────────────
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    _connected ? '等待日志…' : '未连接',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) =>
                      _LogRow(entry: _entries[i], isDark: isDark),
                ),
        ),
      ],
    );
  }
}

// ─── 日志条目数据模型 ──────────────────────────────────────────────────────────

class _LogEntry {
  final String type;
  final String payload;
  final DateTime time;

  const _LogEntry(
      {required this.type, required this.payload, required this.time});
}

// ─── 日志行组件 ────────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final _LogEntry entry;
  final bool isDark;

  const _LogRow({required this.entry, required this.isDark});

  static Color _levelColor(String type) => switch (type) {
        'debug' => const Color(0xFF747E8B),
        'info' => const Color(0xFF378ADD),
        'warning' => const Color(0xFFF59E0B),
        'error' => const Color(0xFFE24B4A),
        _ => const Color(0xFF747E8B),
      };

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(entry.type);
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}';

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(
            ClipboardData(text: '[$timeStr][${entry.type}] ${entry.payload}'));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已复制'),
          duration: Duration(seconds: 1),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(timeStr,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF4A5568)
                        : const Color(0xFFB0BCC8),
                    fontFamily: 'monospace')),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.type,
                  style: TextStyle(
                      fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(entry.payload,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFA6ADBB)
                          : const Color(0xFF374151))),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 日志级别选择胶囊 ──────────────────────────────────────────────────────────

class _LevelPill extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LevelPill({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const levels = ['debug', 'info', 'warning', 'error'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: levels.map((l) {
        final active = l == value;
        return GestureDetector(
          onTap: () => onChanged(l),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF378ADD)
                  : (isDark
                      ? const Color(0xFF1D232A)
                      : const Color(0xFFF5F5F5)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l,
                style: TextStyle(
                    fontSize: 11,
                    color: active
                        ? Colors.white
                        : (isDark
                            ? const Color(0xFF747E8B)
                            : const Color(0xFF94A3B8)))),
          ),
        );
      }).toList(),
    );
  }
}
