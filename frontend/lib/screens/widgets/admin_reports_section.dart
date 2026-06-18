import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/r2v_api.dart';
import '../../api/report_service.dart';
import 'admin_console_widgets.dart';

// --------------------------------------------------------------------------- //
// Shared helpers (self-contained for this section)
// --------------------------------------------------------------------------- //

void _toast(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AdminPalette.red : AdminPalette.green,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Color color = AdminPalette.violet,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AdminPalette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(color: AdminPalette.text)),
      content:
          Text(message, style: const TextStyle(color: AdminPalette.textDim)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: AdminPalette.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

String _statusLabel(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Color _statusColor(String status) {
  switch (status) {
    case 'resolved':
      return AdminPalette.green;
    case 'rejected':
      return AdminPalette.red;
    case 'reviewed':
      return AdminPalette.blue;
    default:
      return AdminPalette.amber;
  }
}

class _ReportFilterChip extends StatelessWidget {
  const _ReportFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AdminPalette.violet.withOpacity(0.18)
          : Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AdminPalette.violet : AdminPalette.border,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? AdminPalette.violet : AdminPalette.textDim,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              )),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Reports / Moderation section
// --------------------------------------------------------------------------- //

class AdminReportsSection extends StatefulWidget {
  const AdminReportsSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  State<AdminReportsSection> createState() => _AdminReportsSectionState();
}

class _AdminReportsSectionState extends State<AdminReportsSection> {
  String _filter = 'pending';
  late Future<AdminReports> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = r2vReports.adminReports(status: _filter);
  }

  @override
  void didUpdateWidget(covariant AdminReportsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  void _reload() =>
      setState(() => _future = r2vReports.adminReports(status: _filter));

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _future = r2vReports.adminReports(status: _filter);
    });
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context, e is ApiException ? e.message : 'Action failed',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(ReportItem r) async {
    final ok = await _confirm(
      context,
      title: 'Resolve report',
      message: 'Mark this ${r.targetType} report as resolved?',
      confirmLabel: 'Resolve',
      color: AdminPalette.green,
    );
    if (!ok) return;
    await _runAction(() => r2vReports.resolve(r.id), 'Report resolved');
  }

  Future<void> _reject(ReportItem r) async {
    final ok = await _confirm(
      context,
      title: 'Reject report',
      message: 'Reject this ${r.targetType} report? No action will be taken.',
      confirmLabel: 'Reject',
      color: AdminPalette.red,
    );
    if (!ok) return;
    await _runAction(() => r2vReports.reject(r.id), 'Report rejected');
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<AdminReports>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Total',
                value: '${data.total}',
                icon: Icons.flag_outlined,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Pending',
                value: '${data.pending}',
                icon: Icons.hourglass_top_rounded,
                color: AdminPalette.amber,
              ),
              AdminMetricCard(
                label: 'Resolved',
                value: '${data.resolved}',
                icon: Icons.verified_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Rejected',
                value: '${data.rejected}',
                icon: Icons.block_rounded,
                color: AdminPalette.red,
              ),
            ]),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              children: [
                for (final f in const ['pending', 'resolved', 'rejected', 'all'])
                  _ReportFilterChip(
                    label: _statusLabel(f),
                    selected: _filter == f,
                    onTap: () => _setFilter(f),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (data.reports.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No reports',
                  message:
                      'User-submitted reports will appear here for review.',
                ),
              )
            else
              for (final r in data.reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ReportCard(
                    report: r,
                    busy: _busy,
                    onResolve: () => _resolve(r),
                    onReject: () => _reject(r),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onResolve,
    required this.onReject,
  });

  final ReportItem report;
  final bool busy;
  final VoidCallback onResolve;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = report.status == 'pending';
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AdminPalette.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminPalette.blue.withOpacity(0.3)),
                ),
                child: Text(report.targetType.toUpperCase(),
                    style: const TextStyle(
                        color: AdminPalette.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(report.reason,
                    style: const TextStyle(
                        color: AdminPalette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              AdminStatusPill(
                label: _statusLabel(report.status),
                color: _statusColor(report.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Target: ${report.targetId}',
              style:
                  const TextStyle(color: AdminPalette.textDim, fontSize: 12)),
          Text('Reporter: ${report.reporterUsername ?? report.reporterId}',
              style:
                  const TextStyle(color: AdminPalette.textDim, fontSize: 12)),
          if (report.description != null && report.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(report.description!,
                style: const TextStyle(
                    color: AdminPalette.text, fontSize: 13, height: 1.4)),
          ],
          if (pending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onResolve,
                    style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.green),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Resolve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminPalette.red,
                      side: const BorderSide(color: AdminPalette.red),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
