import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/freelance_service.dart';

class CreatorWalletDashboard extends StatefulWidget {
  const CreatorWalletDashboard({super.key});

  @override
  State<CreatorWalletDashboard> createState() => _CreatorWalletDashboardState();
}

class _CreatorWalletDashboardState extends State<CreatorWalletDashboard> {
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
        final data = snapshot.data!['wallet'] as Map<String, dynamic>;
        final transactions = (data['transactions'] as List? ?? []).cast<Map>();
        return SingleChildScrollView(
          padding: EdgeInsets.all(isWeb ? 40 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financials',
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
                  _card(
                    'AVAILABLE BALANCE',
                    '\$${data['available_balance']}',
                    Icons.account_balance_wallet,
                    isDark,
                  ),
                  _card(
                    'ESCROW FUNDS',
                    '\$${data['escrow_amount']}',
                    Icons.shield,
                    isDark,
                  ),
                  _card(
                    'PENDING CREDITS',
                    '\$${data['pending_credits']}',
                    Icons.watch_later,
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
                      'Transaction History',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (transactions.isEmpty)
                      _emptyHint(
                        'No transactions yet',
                        'Payments, escrow releases, and credits will appear here.',
                        isDark,
                      )
                    else
                      ...transactions.map((tx) => _transaction(tx, isDark)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String title, String value, IconData icon, bool isDark) =>
      SizedBox(
        width: 280,
        child: Container(
          padding: const EdgeInsets.all(22),
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
                    const SizedBox(height: 6),
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

  Widget _transaction(Map tx, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        const Icon(Icons.receipt_long, color: Color(0xFFBC70FF)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx['title']?.toString() ?? '',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${tx['client']} • ${tx['status']}',
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
          '\$${tx['amount']}',
          style: const TextStyle(
            color: Color(0xFFBC70FF),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _emptyHint(String title, String message, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
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
