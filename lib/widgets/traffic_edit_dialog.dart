import 'package:flutter/material.dart';
import '../services/clash_service.dart';

class TrafficEditDialog extends StatefulWidget {
  final ProviderTraffic provider;

  const TrafficEditDialog({
    super.key,
    required this.provider,
  });

  @override
  State<TrafficEditDialog> createState() => _TrafficEditDialogState();
}

class _TrafficEditDialogState extends State<TrafficEditDialog> {
  late int tempUsedBytes;
  late int currentTotal;
  String usedUnit = 'GB';
  late double tempUsedValue;
  late TextEditingController usedController;

  @override
  void initState() {
    super.initState();
    tempUsedBytes = widget.provider.used;
    currentTotal = widget.provider.total;
    usedUnit = tempUsedBytes >= 1024 * 1024 * 1024 ? 'GB' : 'MB';
    tempUsedValue = _bytesToValue(tempUsedBytes);
    usedController = TextEditingController(text: tempUsedValue.toStringAsFixed(2));
  }

  @override
  void dispose() {
    usedController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  double _bytesToValue(int bytes) {
    if (usedUnit == 'GB') return bytes / (1024 * 1024 * 1024);
    return bytes / (1024 * 1024);
  }

  int _valueToBytes(double value) {
    if (usedUnit == 'GB') return (value * 1024 * 1024 * 1024).round();
    return (value * 1024 * 1024).round();
  }

  void _updateFromValue(String text) {
    final val = double.tryParse(text);
    if (val != null && val >= 0) {
      setState(() {
        tempUsedValue = val;
        tempUsedBytes = _valueToBytes(val).clamp(0, currentTotal);
      });
    }
  }

  void _updateFromPercent(double percent) {
    setState(() {
      tempUsedBytes = (percent * currentTotal).round().clamp(0, currentTotal);
      tempUsedValue = _bytesToValue(tempUsedBytes);
      usedController.text = tempUsedValue.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPercent =
        currentTotal > 0 ? (tempUsedBytes / currentTotal).clamp(0.0, 1.0) : 0.0;
    final displayPercent = (currentPercent * 100).toInt();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF191E24) : Colors.white;
    final textColor = isDark ? const Color(0xFFA6ADBB) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF747E8B) : const Color(0xFF64748B);

    return AlertDialog(
      backgroundColor: bgColor,
      title: Text('修改 ${widget.provider.name} 流量',
          style: TextStyle(fontSize: 16, color: textColor)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总流量: ${_formatBytes(currentTotal)}',
                style: TextStyle(fontSize: 13, color: hintColor)),
            const SizedBox(height: 12),
            Text('已用流量:', style: TextStyle(fontSize: 13, color: textColor)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: usedController,
                    onChanged: _updateFromValue,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF15191E)
                                : Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : Colors.grey.shade400),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: usedUnit,
                  underline: const SizedBox(),
                  dropdownColor: bgColor,
                  style: TextStyle(color: textColor, fontSize: 16),
                  items: const [
                    DropdownMenuItem(value: 'MB', child: Text('MB')),
                    DropdownMenuItem(value: 'GB', child: Text('GB')),
                  ],
                  onChanged: (newUnit) {
                    if (newUnit != null && newUnit != usedUnit) {
                      setState(() {
                        usedUnit = newUnit;
                        tempUsedValue = _bytesToValue(tempUsedBytes);
                        usedController.text =
                            tempUsedValue.toStringAsFixed(2);
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('占比快速调节:', style: TextStyle(fontSize: 13, color: textColor)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: currentPercent,
                    onChanged: _updateFromPercent,
                    min: 0,
                    max: 1,
                    activeColor: const Color(0xFF378ADD),
                    inactiveColor:
                        isDark ? const Color(0xFF15191E) : null,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$displayPercent%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Color(0xFF747E8B))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, tempUsedBytes),
          child: const Text('确定', style: TextStyle(color: Color(0xFF378ADD))),
        ),
      ],
    );
  }
}
