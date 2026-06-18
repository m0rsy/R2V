import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/freelance_service.dart';

class CreatorOrderManagementDashboard extends StatefulWidget {
  const CreatorOrderManagementDashboard({super.key});

  @override
  State<CreatorOrderManagementDashboard> createState() =>
      _CreatorOrderManagementDashboardState();
}

class _CreatorOrderManagementDashboardState
    extends State<CreatorOrderManagementDashboard> {
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
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!['orders'] as Map<String, dynamic>;
        final orders = (data['orders'] as List? ?? []).cast<Map>();
        final timeline = (data['timeline'] as List? ?? []).cast<Map>();
        return SingleChildScrollView(
          padding: EdgeInsets.all(isWeb ? 40 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order Management',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: isWeb ? 32 : 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _metric(
                    'TOTAL ORDERS',
                    '${data['total_orders']}',
                    Icons.shopping_cart,
                    isDark,
                  ),
                  _metric(
                    'ACTIVE PROJECTS',
                    '${data['active_projects']}',
                    Icons.rocket_launch,
                    isDark,
                  ),
                  _metric(
                    'COMPLETED MILESTONES',
                    '${data['completed_milestones']}',
                    Icons.check_circle,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: _glass(isDark),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orders',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (orders.isEmpty)
                      _emptyHint(
                        'No active orders',
                        'Start a project with a freelancer and it will appear here.',
                        isDark,
                      )
                    else
                      ...orders.map((order) => _order(order, isDark)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: _glass(isDark),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Milestone Timeline',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...timeline.map((step) => _timeline(step, isDark)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String title, String value, IconData icon, bool isDark) =>
      SizedBox(
        width: 280,
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
                    Text(
                      value,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 26,
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

  Widget _order(Map order, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              order['is_archived'] == true ? Icons.archive : Icons.work,
              color: const Color(0xFFBC70FF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                order['title']?.toString() ?? '',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              order['tags']?.toString() ?? '',
              style: const TextStyle(
                color: Color(0xFFBC70FF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${order['client']} • ${order['phase']}',
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (order['progress'] as num?)?.toDouble() ?? 0,
          color: const Color(0xFFBC70FF),
          backgroundColor: isDark ? Colors.white12 : Colors.black12,
        ),
      ],
    ),
  );

  Widget _timeline(Map step, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.radio_button_checked,
          color: Color(0xFFBC70FF),
          size: 16,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step['title']?.toString() ?? '',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                step['description']?.toString() ?? '',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

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
