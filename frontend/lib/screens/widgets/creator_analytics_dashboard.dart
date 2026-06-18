import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/freelance_service.dart';

class CreatorAnalyticsDashboard extends StatefulWidget {
  const CreatorAnalyticsDashboard({super.key});

  @override
  State<CreatorAnalyticsDashboard> createState() =>
      _CreatorAnalyticsDashboardState();
}

class _CreatorAnalyticsDashboardState extends State<CreatorAnalyticsDashboard> {
  late final Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = FreelanceService(ApiClient()).dashboard();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWeb = MediaQuery.sizeOf(context).width >= 900;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!['analytics'] as Map<String, dynamic>;
        final clients = (data['top_clients'] as List? ?? []).cast<Map>();
        final gigs = (data['most_viewed_gigs'] as List? ?? []).cast<Map>();
        return SingleChildScrollView(
          padding: EdgeInsets.all(isWeb ? 40 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('Analytics Overview', isDark, isWeb),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _metric(
                    'TOTAL EARNINGS',
                    '\$${data['total_earnings']}',
                    Icons.payments,
                    isDark,
                  ),
                  _metric(
                    'ACTIVE ORDERS',
                    '${data['active_orders']}',
                    Icons.assignment,
                    isDark,
                  ),
                  _metric(
                    'COMPLETED',
                    '${data['completed']}',
                    Icons.check_circle,
                    isDark,
                  ),
                  _metric(
                    'PROFILE VIEWS',
                    '${data['profile_views']}',
                    Icons.visibility,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _panel(
                isDark,
                title: 'Top Clients',
                children: clients.isEmpty
                    ? [
                        _emptyHint(
                          'No clients yet',
                          'Clients will appear here once you complete orders.',
                          isDark,
                        ),
                      ]
                    : clients
                        .map(
                          (client) => _row(
                            title: client['name']?.toString() ?? '',
                            subtitle:
                                '${client['role']} • ${client['projects']} projects',
                            trailing: '\$${client['earnings']}',
                            image: client['avatar']?.toString(),
                            isDark: isDark,
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              _panel(
                isDark,
                title: 'Most Viewed Gigs',
                children: gigs.isEmpty
                    ? [
                        _emptyHint(
                          'No gigs yet',
                          'Your published gigs and their views will appear here.',
                          isDark,
                        ),
                      ]
                    : gigs
                        .map(
                          (gig) => _row(
                            title: gig['title']?.toString() ?? '',
                            subtitle:
                                '${gig['views']} views • ${gig['sales']} sales',
                            trailing: gig['price']?.toString() ?? '',
                            image: gig['image']?.toString(),
                            isDark: isDark,
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _title(String text, bool isDark, bool isWeb) => Text(
    text,
    style: TextStyle(
      color: isDark ? Colors.white : const Color(0xFF1E293B),
      fontSize: isWeb ? 32 : 26,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _metric(String title, String value, IconData icon, bool isDark) {
    return SizedBox(
      width: 240,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _glass(isDark),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFBC70FF)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _glass(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required String trailing,
    required String? image,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: image != null && image.isNotEmpty
                ? NetworkImage(image)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFFBC70FF),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(String title, String message, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
            fontSize: 12.5,
          ),
        ),
      ],
    ),
  );

  BoxDecoration _glass(bool isDark) => BoxDecoration(
    color: isDark
        ? Colors.black.withOpacity(0.25)
        : Colors.white.withOpacity(0.85),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
    ),
  );
}
