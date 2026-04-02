import 'package:flutter/material.dart';
import '../services/clash_service.dart';

class ConnectionDetailSheet extends StatelessWidget {
  final ConnectionEntry conn;
  final int upSpeed;
  final int downSpeed;

  const ConnectionDetailSheet({
    super.key,
    required this.conn,
    required this.upSpeed,
    required this.downSpeed,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec}B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)}KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  String _formatElapsed(DateTime startTime) {
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inSeconds < 60) return '新连接';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}分钟前';
    return '${elapsed.inHours}小时前';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textPrimary =
        isDark ? const Color(0xFFE1E1E1) : const Color(0xFF1C1B1F);
    final textSecondary =
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6E6E6E);
    final dividerColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
    final sectionBg =
        isDark ? const Color(0xFF282828) : const Color(0xFFF5F5F5);
    final connectorColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFBDBDBD);

    final chainLower = conn.chain.toLowerCase();
    final nodeColor = chainLower.contains('reject')
        ? const Color(0xFFE24B4A)
        : (chainLower.contains('direct') ||
                chainLower.contains('直连') ||
                chainLower.contains('本地'))
            ? const Color(0xFF1D9E75)
            : const Color(0xFF1A73E8);

    final destDisplay = conn.destinationIp.isNotEmpty
        ? (conn.destinationPort.isNotEmpty && conn.destinationPort != '0'
            ? '${conn.destinationIp}:${conn.destinationPort}'
            : conn.destinationIp)
        : '';

    final srcDisplay = conn.sourceIp.isNotEmpty
        ? (conn.sourcePort.isNotEmpty && conn.sourcePort != '0'
            ? '${conn.sourceIp}:${conn.sourcePort}'
            : conn.sourceIp)
        : '';

    final inboundDisplay = conn.inboundIp.isNotEmpty
        ? (conn.inboundPort.isNotEmpty && conn.inboundPort != '0'
            ? '${conn.inboundIp}:${conn.inboundPort}'
            : conn.inboundIp)
        : '';

    // 优先使用 API 实时速度，无数据时降级为轮询计算值
    final effectiveUpSpeed =
        conn.apiUpSpeed > 0 ? conn.apiUpSpeed : upSpeed;
    final effectiveDownSpeed =
        conn.apiDownSpeed > 0 ? conn.apiDownSpeed : downSpeed;

    final infoRows = <_InfoRow>[
      if (destDisplay.isNotEmpty) _InfoRow('目标地址', destDisplay),
      if (conn.remoteDestination.isNotEmpty)
        _InfoRow('远端地址', conn.remoteDestination),
      if (srcDisplay.isNotEmpty) _InfoRow('源地址', srcDisplay),
      if (inboundDisplay.isNotEmpty) _InfoRow('进站地址', inboundDisplay),
      if (conn.inboundName.isNotEmpty) _InfoRow('进站名', conn.inboundName),
      if (conn.sniffHost.isNotEmpty) _InfoRow('嗅探主机', conn.sniffHost),
      if (conn.rule.isNotEmpty) _InfoRow('规则', conn.rule),
      if (conn.process.isNotEmpty) _InfoRow('进程', conn.process),
      if (conn.dnsMode.isNotEmpty) _InfoRow('DNS模式', conn.dnsMode),
      if (conn.type.isNotEmpty) _InfoRow('连接类型', conn.type),
      _InfoRow('传输协议', conn.network),
      _InfoRow('连接ID',
          conn.id.length > 18 ? '${conn.id.substring(0, 18)}…' : conn.id),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: connectorColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主机名 + 协议/类型徽章
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          conn.host,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Badge(conn.network, const Color(0xFF1A73E8)),
                      if (conn.type.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        _Badge(conn.type,
                            isDark
                                ? const Color(0xFF2C2C2C)
                                : const Color(0xFFE0E0E0),
                            textColor: textSecondary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 流量统计行
                  Row(
                    children: [
                      Icon(Icons.arrow_upward,
                          size: 11, color: textSecondary),
                      const SizedBox(width: 2),
                      Text(_formatBytes(conn.upload),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: textPrimary)),
                      const SizedBox(width: 14),
                      Icon(Icons.arrow_downward,
                          size: 11, color: textSecondary),
                      const SizedBox(width: 2),
                      Text(_formatBytes(conn.download),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: textPrimary)),
                      if (effectiveUpSpeed > 0 || effectiveDownSpeed > 0) ...[
                        const SizedBox(width: 14),
                        Text(
                          '↑${_formatSpeed(effectiveUpSpeed)}  ↓${_formatSpeed(effectiveDownSpeed)}',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF378ADD)),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        _formatElapsed(conn.startTime),
                        style:
                            TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 出站链路区块
                  _SectionLabel('出站链路', textSecondary),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(conn.chainList.length, (i) {
                        final isLast = i == conn.chainList.length - 1;
                        final dotColor = isLast ? nodeColor : textSecondary;
                        // 当前节点对应的 provider 名（顺序与 chainList 一致）
                        final providerIdx = conn.providerChains.length > i
                            ? conn.providerChains.reversed.toList()[i]
                            : '';
                        final providerLabel = providerIdx.isNotEmpty
                            ? providerIdx
                            : null;
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 16,
                                child: Column(
                                  children: [
                                    Container(
                                      width: isLast ? 8 : 6,
                                      height: isLast ? 8 : 6,
                                      margin: isLast
                                          ? const EdgeInsets.only(top: 2)
                                          : const EdgeInsets.only(top: 3),
                                      decoration: BoxDecoration(
                                        color: isLast
                                            ? dotColor
                                            : Colors.transparent,
                                        border: isLast
                                            ? null
                                            : Border.all(
                                                color: dotColor, width: 1.5),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (!isLast)
                                      Expanded(
                                        child: Center(
                                          child: Container(
                                            width: 1.5,
                                            color: connectorColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding:
                                      EdgeInsets.only(bottom: isLast ? 0 : 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          conn.chainList[i],
                                          style: TextStyle(
                                            fontSize: isLast ? 13 : 12,
                                            fontWeight: isLast
                                                ? FontWeight.w500
                                                : FontWeight.normal,
                                            color: isLast
                                                ? textPrimary
                                                : textSecondary,
                                          ),
                                        ),
                                      ),
                                      if (providerLabel != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          providerLabel,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: textSecondary
                                                  .withOpacity(0.7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 连接信息区块
                  _SectionLabel('连接信息', textSecondary),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: List.generate(infoRows.length, (i) {
                        final row = infoRows[i];
                        final isLast = i == infoRows.length - 1;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 72,
                                    child: Text(row.label,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: textSecondary)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      row.value,
                                      style: TextStyle(
                                          fontSize: 12, color: textPrimary),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Divider(
                                  height: 0.5,
                                  thickness: 0.5,
                                  indent: 14,
                                  endIndent: 14,
                                  color: dividerColor),
                          ],
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: 11,
            color: color,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w500),
      );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bgColor;
  final Color? textColor;
  const _Badge(this.text, this.bgColor, {this.textColor});

  @override
  Widget build(BuildContext context) {
    final isBlue = bgColor == const Color(0xFF1A73E8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isBlue ? bgColor.withOpacity(0.15) : bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isBlue
            ? Border.all(color: bgColor.withOpacity(0.3), width: 0.5)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: textColor ?? bgColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
