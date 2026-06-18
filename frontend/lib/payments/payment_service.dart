import 'dart:convert';
import 'package:http/http.dart' as http;

class PaymentStartResponse {
  final String orderId;
  final String paymentUrl;

  PaymentStartResponse({required this.orderId, required this.paymentUrl});

  factory PaymentStartResponse.fromJson(Map<String, dynamic> json) {
    return PaymentStartResponse(
      orderId: json['orderId'].toString(),
      paymentUrl: json['paymentUrl'] as String,
    );
  }
}

class PaymentStatusResponse {
  final String orderId;
  final String status; // pending/paid/failed/canceled

  PaymentStatusResponse({required this.orderId, required this.status});

  factory PaymentStatusResponse.fromJson(Map<String, dynamic> json) {
    return PaymentStatusResponse(
      orderId: json['orderId'].toString(),
      status: (json['status'] as String).toLowerCase(),
    );
  }
}

class PaymentService {
  final String baseUrl; // e.g. https://api.yourserver.com

  PaymentService(this.baseUrl);

  Future<PaymentStartResponse> startPayment({
    required int userId,
    required String planId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'planId': planId}),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Start payment failed: ${res.body}');
    }

    return PaymentStartResponse.fromJson(jsonDecode(res.body));
  }

  Future<PaymentStatusResponse> fetchStatus(String orderId) async {
    final res = await http.get(Uri.parse('$baseUrl/payments/status?orderId=$orderId'));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Fetch status failed: ${res.body}');
    }

    return PaymentStatusResponse.fromJson(jsonDecode(res.body));
  }
}
