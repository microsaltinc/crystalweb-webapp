import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_callback_parameters.dart';
import 'core/auth/auth_callback_url.dart';
import 'core/auth/auth_provider.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final currentUri = Uri.base;
  final initialAuthToken = authCallbackParameters(currentUri)['token'];
  if (currentUri.path == '/auth-callback' &&
      (currentUri.fragment.isNotEmpty ||
          currentUri.queryParameters.containsKey('token'))) {
    // Capture the credential before GoRouter interprets the fragment and
    // remove it from browser history before any asynchronous work.
    clearAuthCallbackUrl();
  }

  runApp(ProviderScope(child: CrystalApp(initialAuthToken: initialAuthToken)));
}

class CrystalApp extends ConsumerStatefulWidget {
  const CrystalApp({super.key, this.initialAuthToken});

  final String? initialAuthToken;

  @override
  ConsumerState<CrystalApp> createState() => _CrystalAppState();
}

class _CrystalAppState extends ConsumerState<CrystalApp> {
  bool _authReady = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final authService = ref.read(authServiceProvider);
      final initialAuthToken = widget.initialAuthToken;
      final restored = initialAuthToken?.isNotEmpty ?? false
          ? await authService.completeSamlAuth(initialAuthToken!)
          : await authService.restoreSession();
      if (!mounted) return;
      ref.read(authStateProvider.notifier).restore(restored);
    } catch (_) {
      if (!mounted) return;
      ref.read(authStateProvider.notifier).setUnauthenticated();
    } finally {
      if (mounted) setState(() => _authReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authReady) {
      return MaterialApp(
        title: 'CrystalApp',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'CrystalApp',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
