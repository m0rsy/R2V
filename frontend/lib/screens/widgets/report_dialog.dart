import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/r2v_api.dart';

const _reasons = <String>[
  'inappropriate',
  'copyright',
  'spam',
  'harassment',
  'scam',
  'other',
];

String _reasonLabel(String r) {
  switch (r) {
    case 'inappropriate':
      return 'Inappropriate content';
    case 'copyright':
      return 'Copyright violation';
    case 'spam':
      return 'Spam';
    case 'harassment':
      return 'Harassment / abuse';
    case 'scam':
      return 'Scam / fraud';
    default:
      return 'Other';
  }
}

/// Opens the shared report dialog. [targetType] must be one of
/// asset | model | freelancer | user | order | other.
Future<void> showReportDialog(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? targetLabel,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ReportDialog(
      targetType: targetType,
      targetId: targetId,
      targetLabel: targetLabel,
    ),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.targetType,
    required this.targetId,
    this.targetLabel,
  });

  final String targetType;
  final String targetId;
  final String? targetLabel;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  static const _violet = Color(0xFF8A4FFF);
  static const _panel = Color(0xFF161021);
  static const _border = Color(0x1AFFFFFF);

  String _reason = _reasons.first;
  final _description = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await r2vReports.submit(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _reason,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Our team will review it.'),
          backgroundColor: Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not submit report';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Color(0xFFEF4444), size: 22),
          const SizedBox(width: 10),
          Text(
            widget.targetLabel == null ? 'Report' : 'Report ${widget.targetLabel}',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reason',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _reason,
              dropdownColor: _panel,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(),
              items: [
                for (final r in _reasons)
                  DropdownMenuItem(value: r, child: Text(_reasonLabel(r))),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
            const SizedBox(height: 14),
            const Text('Details (optional)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(hint: 'Add any helpful context…'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _violet),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Submit report'),
        ),
      ],
    );
  }

  InputDecoration _decoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _violet),
        ),
      );
}
