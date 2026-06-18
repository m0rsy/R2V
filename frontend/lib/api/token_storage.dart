import 'token_pair.dart';
import 'token_storage_stub.dart'
    if (dart.library.html) 'token_storage_web.dart';

/// Token storage abstraction.
///
/// - Web: uses localStorage (persistent) or sessionStorage (non-persistent)
/// - Non-web: in-memory fallback (keeps builds compiling)
abstract class TokenStorage {
  Future<TokenPair?> load();
  Future<void> save(TokenPair tokens, {required bool persist});
  Future<void> clear();

  /// Whether the currently stored tokens are persisted across browser sessions.
  ///
  /// Web: true if tokens are in localStorage, false if in sessionStorage.
  /// Non-web: always true.
  Future<bool> isPersistent();

  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
}

TokenStorage createTokenStorage() => TokenStorageImpl();
