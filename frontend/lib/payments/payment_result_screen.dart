import 'package:flutter/material.dart';

class PaymentResultScreen extends StatelessWidget {
  final String orderId;
  final String status; // paid/failed/canceled/pending

  const PaymentResultScreen({
    super.key,
    required this.orderId,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = status == 'paid';
    final isFailed = status == 'failed';
    final isCanceled = status == 'canceled';

    String title = "Payment status";
    String subtitle = "Order: $orderId";
    IconData icon = Icons.info;

    if (isPaid) {
      title = "Payment successful ✅";
      icon = Icons.check_circle;
    } else if (isFailed) {
      title = "Payment failed ❌";
      icon = Icons.cancel;
    } else if (isCanceled) {
      title = "Payment canceled";
      icon = Icons.info_outline;
    } else {
      title = "Payment pending…";
      icon = Icons.hourglass_bottom;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Payment")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 18),
            Icon(icon, size: 64),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(0.7))),
            const Spacer(),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Back"),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
