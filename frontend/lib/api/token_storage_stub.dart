import 'token_pair.dart';
import 'token_storage.dart';

class TokenStorageImpl implements TokenStorage {
  TokenPair? _tokens;

  @override
  Future<TokenPair?> load() async => _tokens;

  @override
  Future<void> save(TokenPair tokens, {required bool persist}) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<bool> isPersistent() async => true;

  @override
  Future<String?> getAccessToken() async => _tokens?.accessToken;

  @override
  Future<String?> getRefreshToken() async => _tokens?.refreshToken;
}
