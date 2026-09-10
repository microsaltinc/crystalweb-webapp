import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/route_names.dart';
import '../../operators/models/operator.dart';

class OperatorPinScreen extends ConsumerStatefulWidget {
  const OperatorPinScreen({
    super.key,
    required this.operatorId,
    required this.operatorName,
    this.managedByName,
    this.hasPin = true,
  });

  final String operatorId;
  final String operatorName;
  final String? managedByName;

  /// Whether the operator already has a PIN set.
  /// If false, the screen lets the user create a new PIN with confirmation.
  final bool hasPin;

  @override
  ConsumerState<OperatorPinScreen> createState() => _OperatorPinScreenState();
}

class _OperatorPinScreenState extends ConsumerState<OperatorPinScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pinFocusNode = FocusNode();
  bool _isValid = false;
  bool _isLoading = false;
  String? _error;

  bool get _isSetMode => !widget.hasPin;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_validate);
    _confirmController.addListener(_validate);
    // Auto-focus the PIN field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  void _validate() {
    setState(() {
      if (_isSetMode) {
        _isValid =
            _pinController.text.length >= 4 &&
            _confirmController.text.length >= 4;
      } else {
        _isValid = _pinController.text.length >= 4;
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isSetMode) {
      await _handleSetPin();
    } else {
      await _handleVerify();
    }
  }

  Future<void> _handleSetPin() async {
    if (_pinController.text != _confirmController.text) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Set the PIN on the backend — explicitly pass token since
      // the interceptor closure may have lost the auth state reference.
      final client = ref.read(apiClientProvider);
      final authState = ref.read(authStateProvider);
      final token = authState.token;
      await client.dio.post(
        '/api/v1/operators/${widget.operatorId}/pin',
        data: {'pin': _pinController.text},
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );

      // Now delegate (verify) with the newly set PIN
      await _verifyAndEnter(token);
    } catch (e) {
      _handleError(e, 'Failed to set PIN');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleVerify() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ref.read(authStateProvider).token;
      await _verifyAndEnter(token);
    } catch (e) {
      _handleError(e, 'Invalid PIN');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Shared: delegate to operator and navigate to batches.
  Future<void> _verifyAndEnter(String? token) async {
    final ssoUser = ref.read(authStateProvider).user;
    final authService = ref.read(authServiceProvider);
    final result = await authService.delegateToOperator(
      operatorId: widget.operatorId,
      pin: _pinController.text,
      currentToken: token,
    );

    if (result.token != null && result.user != null) {
      // Fetch operator details with the NEW token from delegation
      final client = ref.read(apiClientProvider);
      final opResponse = await client.dio.get(
        '/api/v1/operators/${widget.operatorId}',
        options: Options(headers: {'Authorization': 'Bearer ${result.token}'}),
      );
      final operator = Operator.fromJson(
        opResponse.data as Map<String, dynamic>,
      );

      ref
          .read(authStateProvider.notifier)
          .setAuthenticated(
            token: result.token!,
            user: ssoUser ?? result.user!,
            activeOperator: operator,
          );

      if (mounted) {
        context.go(RouteNames.batches);
      }
    } else {
      if (mounted) setState(() => _error = 'Verification failed');
    }
  }

  void _handleError(Object e, String fallbackMsg) {
    if (e is DioException && e.response != null) {
      dev.log(
        'PIN request failed with status ${e.response?.statusCode}',
        name: 'OperatorPin',
      );
    }
    if (mounted) {
      final action = fallbackMsg == 'Invalid PIN' ? 'verify PIN' : 'set PIN';
      setState(() => _error = userFacingError(e, action: action));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RouteNames.operatorSelect),
        ),
        title: Text(_isSetMode ? 'Set PIN' : 'Operator Login'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.operatorName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (widget.managedByName != null &&
                  widget.managedByName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'account managed by ${widget.managedByName} (Microsalt)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _isSetMode
                    ? 'Create a 4-6 digit PIN for this operator'
                    : 'Enter your PIN to continue',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _pinController,
                  focusNode: _pinFocusNode,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  obscureText: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '----',
                    counterText: '',
                    labelText: _isSetMode ? 'New PIN' : null,
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                  onSubmitted: (_) {
                    if (_isValid && !_isLoading) _handleSubmit();
                  },
                ),
              ),
              if (_isSetMode) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _confirmController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      hintText: '----',
                      counterText: '',
                      labelText: 'Confirm PIN',
                    ),
                    style: Theme.of(context).textTheme.headlineMedium,
                    onSubmitted: (_) {
                      if (_isValid && !_isLoading) _handleSubmit();
                    },
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _isValid ? _handleSubmit : null,
                  child: Text(_isSetMode ? 'Set PIN' : 'Verify'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
