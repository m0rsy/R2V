import 'api_client.dart';

class BillingService {
  BillingService(this._api);

  final ApiClient _api;

  Future<String> checkoutSubscription() async {
    final data = await _api.postJson('/billing/checkout/subscription', auth: true);
    return data['checkout_url']?.toString() ?? '';
  }
}
