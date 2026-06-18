import 'token_store_memory.dart'
  if (dart.library.html) 'token_store_web.dart';

abstract class TokenStore {
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool persist = true,
  });
  Future<void> clear();
}

class DefaultTokenStore extends TokenStoreImpl {
  DefaultTokenStore() : super();
}
