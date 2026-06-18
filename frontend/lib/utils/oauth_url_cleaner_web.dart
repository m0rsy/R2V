// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Strip the OAuth tokens out of the browser address bar after they have been
/// read and persisted. The redirect lands on
///   https://site/#/oauth/callback?provider=google&access_token=...&refresh_token=...
/// and we replace it (no new history entry) with a clean route so the tokens
/// are never left visible, shareable, or restorable via Back. Tokens are never
/// logged.
void clearOAuthTokensFromUrl() {
  try {
    html.window.history.replaceState(null, '', '#/home');
  } catch (_) {
    // Best-effort only: navigation still proceeds even if the URL can't be
    // rewritten (e.g. sandboxed iframe).
  }
}
