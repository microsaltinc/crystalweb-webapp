import '../../features/operators/models/operator.dart';

enum UserRole { user, operator }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.groups = const [],
  });

  final String id;
  final String email;
  final String name;
  final UserRole role;
  /// Google Workspace group memberships synced from SAML assertion
  final List<String> groups;

  bool get isMicrosaltDomain => email.endsWith('@microsaltinc.com');

  String get firstName => name.split(' ').first;
  String get lastName => name.split(' ').length > 1 ? name.split(' ').last : '';
}

class AuthState {
  const AuthState._({this.token, this.userToken, this.user, this.activeOperator});

  const AuthState.unauthenticated() : this._();

  /// Legacy constructor — maps to session-only (no operator).
  AuthState.authenticated({
    required String token,
    required AuthUser user,
  }) : this._(token: token, userToken: token, user: user);

  /// Has SSO token + user, but no operator selected yet.
  AuthState.sessionOnly({
    required String token,
    required AuthUser user,
  }) : this._(token: token, userToken: token, user: user);

  /// Fully authenticated: SSO token + user + active operator with PIN verified.
  AuthState.withOperator({
    required String token,
    required String userToken,
    required AuthUser user,
    required Operator operator,
  }) : this._(token: token, userToken: userToken, user: user, activeOperator: operator);

  final String? token;
  /// The original SSO user token, preserved across operator delegation.
  final String? userToken;
  final AuthUser? user;
  final Operator? activeOperator;

  /// Fully authenticated: has token, user, AND active operator.
  bool get isAuthenticated =>
      token != null && user != null && activeOperator != null;

  /// Has a valid session (token + user) but no operator selected yet.
  bool get isSessionOnly =>
      token != null && user != null && activeOperator == null;

  bool get isOperator => user?.role == UserRole.operator;
}
