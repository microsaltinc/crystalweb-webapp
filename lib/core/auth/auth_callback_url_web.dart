import 'package:web/web.dart' as web;

void clearAuthCallbackUrl() {
  web.window.history.replaceState(null, '', '/auth-callback');
}
