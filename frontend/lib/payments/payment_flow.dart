import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'payment_service.dart';
import 'payment_webview.dart';
import 'payment_result_screen.dart';

class PaymentFlow {
  final PaymentService service;

  PaymentFlow(this.service);

  Future<void> start({
    required BuildContext context,
    required int userId,
    required String planId,
    LaunchMode webLaunchMode = LaunchMode.platformDefault, // change to inAppWebView if you want
  }) async {
    // 1) start payment
    final startRes = await service.startPayment(userId: userId, planId: planId);

    // 2) open provider UI
    if (kIsWeb) {
      final ok = await launchUrl(Uri.parse(startRes.paymentUrl), mode: webLaunchMode);
      if (!ok) throw Exception('Could not open payment URL');
      // user pays in another tab, then comes back manually
    } else {
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PaymentWebView(url: startRes.paymentUrl)),
      );
    }

    // 3) poll for final status
    final status = await _pollUntilDone(startRes.orderId);

    if (!context.mounted) return;

    // 4) show result screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentResultScreen(orderId: startRes.orderId, status: status),
      ),
    );
  }

  Future<String> _pollUntilDone(String orderId) async {
    final start = DateTime.now();
    String status = 'pending';

    while (DateTime.now().difference(start) < const Duration(seconds: 60)) {
      final res = await service.fetchStatus(orderId);
      status = res.status;

      if (_isFinal(status)) return status;
      await Future.delayed(const Duration(seconds: 2));
    }

    return status; // probably pending if webhook is slow
  }

  bool _isFinal(String s) => s == 'paid' || s == 'failed' || s == 'canceled';
}
