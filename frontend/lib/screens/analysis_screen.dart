import 'package:flutter/material.dart';

import '../api/ai_jobs_service.dart';
import '../api/dashboard_service.dart';
import '../api/r2v_api.dart';
import '../api/scan_jobs_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Future<_AnalyticsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_AnalyticsData> _loadData() async {
    final results = await Future.wait([
      r2vDashboard.me(),
      r2vAiJobs.listJobs(limit: 6),
      r2vScanJobs.listJobs(limit: 6),
    ]);
    return _AnalyticsData(
      stats: results[0] as DashboardStats,
      aiJobs: results[1] as List<AiJob>,
      scanJobs: results[2] as List<ScanJob>,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0D14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Analytics Dashboard", style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
        // Always show a working back button. On a fresh/refreshed load of
        // /analysis the Navigator has nothing to pop, so the default auto-leading
        // would vanish — fall back to /home instead of leaving no way back.
        leading: IconButton(
          tooltip: "Back",
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              nav.pushReplacementNamed('/home');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_AnalyticsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFF72585), size: 42),
                    const SizedBox(height: 12),
                    Text("Unable to load analytics", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _refresh, child: const Text("Try again")),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Performance Overview",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 24),
                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _buildStatCard("Created Assets", _formatCount(data.stats.assets), "Marketplace", const Color(0xFF8A4FFF), isDark, Icons.view_in_ar_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("Model Downloads", _formatCount(data.stats.downloads), "Recorded", const Color(0xFF4CC9F0), isDark, Icons.download_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("AI Jobs", _formatCount(data.stats.aiJobs), "Generated", const Color(0xFFF72585), isDark, Icons.auto_awesome_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("Scan Jobs", _formatCount(data.stats.scanJobs), "Reconstruction", const Color(0xFF22C55E), isDark, Icons.camera_alt_rounded)),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildStatCard("Created Assets", _formatCount(data.stats.assets), "Marketplace", const Color(0xFF8A4FFF), isDark, Icons.view_in_ar_rounded),
                      const SizedBox(height: 16),
                      _buildStatCard("Model Downloads", _formatCount(data.stats.downloads), "Recorded", const Color(0xFF4CC9F0), isDark, Icons.download_rounded),
                      const SizedBox(height: 16),
                      _buildStatCard("AI Jobs", _formatCount(data.stats.aiJobs), "Generated", const Color(0xFFF72585), isDark, Icons.auto_awesome_rounded),
                      const SizedBox(height: 16),
                      _buildStatCard("Scan Jobs", _formatCount(data.stats.scanJobs), "Reconstruction", const Color(0xFF22C55E), isDark, Icons.camera_alt_rounded),
                    ],
                  ),
                const SizedBox(height: 32),
                _ActivityMixChart(values: data.chartValues, isDark: isDark),
                const SizedBox(height: 32),
                Text(
                  "Recent Jobs",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                _buildRecentModelsList(isDark, data.recentItems),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color accent, bool isDark, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)]
              : [Colors.white, Colors.white.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(subtitle, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(value, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildRecentModelsList(bool isDark, List<_RecentAnalyticsItem> items) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _listDecoration(isDark),
        child: Text("No jobs recorded yet.", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
      );
    }

    return Container(
      decoration: _listDecoration(isDark),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (context, index) => Divider(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color),
            ),
            title: Text(item.title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w600)),
            subtitle: Text(item.subtitle, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(item.status, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _listDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
      boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return "${(count / 1000000).toStringAsFixed(1)}M";
    if (count >= 1000) return "${(count / 1000).toStringAsFixed(1)}K";
    return count.toString();
  }
}

class _AnalyticsData {
  final DashboardStats stats;
  final List<AiJob> aiJobs;
  final List<ScanJob> scanJobs;

  const _AnalyticsData({
    required this.stats,
    required this.aiJobs,
    required this.scanJobs,
  });

  List<int> get chartValues => [stats.assets, stats.downloads, stats.aiJobs, stats.scanJobs];

  List<_RecentAnalyticsItem> get recentItems {
    final ai = aiJobs.map((job) {
      return _RecentAnalyticsItem(
        title: job.prompt?.isNotEmpty == true ? job.prompt! : "AI generation ${_shortId(job.id)}",
        subtitle: "AI job ${job.progress}%",
        status: job.status,
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFF72585),
      );
    });
    final scans = scanJobs.map((job) {
      return _RecentAnalyticsItem(
        title: "Scan reconstruction ${_shortId(job.id)}",
        subtitle: "Scan job ${job.progress}%",
        status: job.status,
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFF22C55E),
      );
    });
    return [...ai, ...scans].take(8).toList();
  }

  String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
}

class _RecentAnalyticsItem {
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color color;

  const _RecentAnalyticsItem({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.color,
  });
}

/// Premium, interactive "Activity Mix" mini-chart. Four rounded gradient bars
/// (Assets / Downloads / AI / Scans) that respond to hover (web) and tap/
/// long-press (touch): the active bar brightens with a glow, neighbours stay
/// bright, the rest dim, a tooltip floats above the active bar, and the header's
/// top-right value reflects the active metric. Zero values still render a small
/// baseline bar so every category stays visible.
class _ActivityMixChart extends StatefulWidget {
  final List<int> values; // [assets, downloads, aiJobs, scanJobs]
  final bool isDark;
  const _ActivityMixChart({required this.values, required this.isDark});

  @override
  State<_ActivityMixChart> createState() => _ActivityMixChartState();
}

class _ActivityMixChartState extends State<_ActivityMixChart>
    with SingleTickerProviderStateMixin {
  static const List<Color> _colors = [
    Color(0xFF8A4FFF), // Assets — purple
    Color(0xFF4CC9F0), // Downloads — cyan/blue
    Color(0xFFF72585), // AI — pink/purple
    Color(0xFF22C55E), // Scans — green
  ];
  static const List<String> _short = ["Assets", "Downloads", "AI", "Scans"];
  static const List<String> _full = ["Assets", "Downloads", "AI Jobs", "Scans"];

  int? _active;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final values = widget.values;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final cardHeight = isMobile ? 244.0 : 288.0;
    final barW = isMobile ? 30.0 : 40.0;
    final maxValue = values.fold<int>(1, (m, v) => v > m ? v : m);
    final accent = _active != null ? _colors[_active!] : const Color(0xFF8A4FFF);

    return Container(
      height: cardHeight,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)]
              : [Colors.white, Colors.white.withOpacity(0.85)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.10 : 0.06),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Subtle inner glow that follows the active accent colour.
            Positioned(
              right: -50,
              top: -50,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withOpacity(isDark ? 0.18 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(isDark, values),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      values.length,
                      (i) => Expanded(
                        child: _barColumn(i, values, maxValue, barW, isDark),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark, List<int> values) {
    final hasActive = _active != null;
    final rightText = hasActive
        ? "${values[_active!]} ${_full[_active!]}"
        : "${values.fold<int>(0, (a, b) => a + b)} total";
    final rightColor = hasActive
        ? _colors[_active!]
        : (isDark ? Colors.white70 : Colors.black54);

    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final t = 0.35 + _pulse.value * 0.65;
            return Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8A4FFF),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8A4FFF).withOpacity(t),
                    blurRadius: 8,
                    spreadRadius: 1.5 * _pulse.value,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          "Activity Mix",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            rightText,
            key: ValueKey(rightText),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: rightColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _barColumn(
      int i, List<int> values, int maxValue, double barW, bool isDark) {
    final color = _colors[i];
    final value = values[i];
    final isActive = _active == i;

    // Prominence drives brightness: active = full, neighbour = bright,
    // others = dim, nothing-active = neutral.
    double prominence;
    if (_active == null) {
      prominence = 0.85;
    } else if (isActive) {
      prominence = 1.0;
    } else if ((_active! - i).abs() == 1) {
      prominence = 0.7;
    } else {
      prominence = 0.38;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _active = i),
      onExit: (_) => setState(() => _active = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _active = isActive ? null : i),
        onLongPress: () => setState(() => _active = i),
        child: LayoutBuilder(
          builder: (context, c) {
            const tooltipReserve = 46.0;
            final maxBarH = (c.maxHeight - tooltipReserve).clamp(24.0, 320.0);
            final frac = maxValue <= 0 ? 0.0 : value / maxValue;
            final targetH = (maxBarH * frac).clamp(6.0, maxBarH); // 6px baseline

            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    clipBehavior: Clip.none,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 650),
                        curve: Curves.easeOutCubic,
                        builder: (_, grow, __) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                            width: barW,
                            height: targetH * grow,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  color.withOpacity(prominence),
                                  color.withOpacity(prominence * 0.35),
                                ],
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: color.withOpacity(0.5),
                                        blurRadius: 18,
                                        spreadRadius: -2,
                                      ),
                                    ]
                                  : const [],
                            ),
                          );
                        },
                      ),
                      if (isActive)
                        Positioned(
                          bottom: targetH + 8,
                          child: _tooltip(i, value, color, isDark),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 16,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: isActive
                          ? color
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                    child: Text(_short[i]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tooltip(int i, int value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1030) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$value",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            _full[i],
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
