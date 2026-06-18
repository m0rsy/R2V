import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Pretty-prints a snake_case status into a Title Case label.
String prettyStatus(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// A small colored status pill, color-coded via [AppColors.status].
/// Generic replacement for the per-screen status chips/pills.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.label, this.dense = false});

  final String status;
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.statusColor(status, Theme.of(context).colorScheme.primary);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        label ?? prettyStatus(status),
        style: TextStyle(
          color: c,
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
