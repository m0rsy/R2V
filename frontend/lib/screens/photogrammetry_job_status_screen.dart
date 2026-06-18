import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../api/photogrammetry_api_service.dart';
import '../api/r2v_api.dart';
import 'photo_scan_guided.dart';

class PhotogrammetryJobStatusScreen extends StatefulWidget {
  const PhotogrammetryJobStatusScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

  @override
  State<PhotogrammetryJobStatusScreen> createState() => _PhotogrammetryJobStatusScreenState();
}

class _PhotogrammetryJobStatusScreenState extends State<PhotogrammetryJobStatusScreen> {
  Timer? _poller;
  PhotogrammetryJobStatus? _status;
  String? _error;
  bool _isLoading = true;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await r2vPhotogrammetry.getJobStatus(widget.jobId);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _error = null;
        _isLoading = false;
      });
      if (status.isCompleted && !_navigated) {
        _navigated = true;
        _poller?.cancel();
        Navigator.pushReplacementNamed(
          context,
          '/photogrammetry/output',
          arguments: {'jobId': widget.jobId},
        );
      } else if (status.isFailed) {
        _poller?.cancel();
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load photogrammetry status right now.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = (_status?.progress ?? 0).clamp(0, 100) / 100;
    final statusLabel = _friendlyStatus(_status?.status ?? 'pending');
    final statusColor = _statusColor(_status?.status ?? 'pending');

    return Stack(
      children: [
        const Positioned.fill(child: NebulaMeshBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusTopBar(
                        title: 'Reconstruction Job',
                        subtitle: 'Live photogrammetry pipeline progress',
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: _isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            _GlassBadge(text: statusLabel, color: statusColor),
                                            _GlassBadge(
                                              text: '${_status?.progress ?? 0}%',
                                              color: const Color(0xFF4CC9F0),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        Text(
                                          'Job ${widget.jobId}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _statusMessage(_status?.status ?? 'pending'),
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.72),
                                            fontSize: 15,
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 28),
                                        Container(
                                          padding: const EdgeInsets.all(18),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(22),
                                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.tune_rounded,
                                                    color: Color(0xFFBC70FF),
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'Pipeline Progress',
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.92),
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 18),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(999),
                                                child: LinearProgressIndicator(
                                                  value: progressValue == 0 ? null : progressValue,
                                                  minHeight: 14,
                                                  backgroundColor: Colors.white.withOpacity(0.08),
                                                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                '${_status?.progress ?? 0}% complete',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.65),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _InfoPanel(
                                                  icon: Icons.inventory_2_rounded,
                                                  title: 'What Happens Next',
                                                  body: _status?.isCompleted == true
                                                      ? 'Outputs are ready. Moving you to downloads automatically.'
                                                      : 'The backend is unpacking photos, preprocessing them, and running reconstruction stages in sequence.',
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: _InfoPanel(
                                                  icon: Icons.error_outline_rounded,
                                                  title: 'Latest Message',
                                                  body: _status?.error?.isNotEmpty == true
                                                      ? _status!.error!
                                                      : (_error ?? 'No errors reported. Polling every 3 seconds.'),
                                                  accent: _status?.error?.isNotEmpty == true || _error != null
                                                      ? const Color(0xFFFF7B7B)
                                                      : const Color(0xFF22C55E),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _friendlyStatus(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'processing':
        return 'Processing';
      default:
        return 'Pending';
    }
  }

  String _statusMessage(String status) {
    switch (status) {
      case 'completed':
        return 'The reconstruction finished successfully and the output package is ready.';
      case 'failed':
        return 'The job stopped before producing outputs. Check the latest message below.';
      case 'processing':
        return 'Your photo set is currently moving through the reconstruction pipeline.';
      default:
        return 'The job is queued and waiting for processing to begin.';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF22C55E);
      case 'failed':
        return const Color(0xFFFF7B7B);
      case 'processing':
        return const Color(0xFFBC70FF);
      default:
        return const Color(0xFF4CC9F0);
    }
  }
}

class _StatusTopBar extends StatelessWidget {
  const _StatusTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.sensors_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.body,
    this.accent = const Color(0xFFBC70FF),
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withOpacity(0.74),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
