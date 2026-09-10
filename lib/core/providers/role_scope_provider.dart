import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_state.dart';

class RoleScope {
  const RoleScope({
    required this.canSeeRnd,
    required this.canSeeProduction,
    required this.canSeeAll,
    required this.availableModes,
    required this.isAdmin,
  });

  const RoleScope.admin()
      : canSeeRnd = true,
        canSeeProduction = true,
        canSeeAll = true,
        availableModes = const ['rnd', 'production'],
        isAdmin = true;

  const RoleScope.none()
      : canSeeRnd = false,
        canSeeProduction = false,
        canSeeAll = false,
        availableModes = const [],
        isAdmin = false;

  final bool canSeeRnd;
  final bool canSeeProduction;
  final bool canSeeAll;
  final List<String> availableModes;
  final bool isAdmin;

  String? get batchModeFilter {
    if (canSeeAll) return null;
    if (canSeeRnd) return 'rnd';
    if (canSeeProduction) return 'production';
    return 'production';
  }

  bool? get isTestingFilter {
    if (canSeeAll) return null;
    if (canSeeRnd) return true;
    if (canSeeProduction) return false;
    return false;
  }
}

final roleScopeProvider = Provider<RoleScope>((ref) {
  final authState = ref.watch(authStateProvider);

  // SSO admin users see everything
  if (authState.user?.role == UserRole.user) {
    return const RoleScope.admin();
  }

  final operator = authState.activeOperator;
  if (operator == null) {
    return const RoleScope.none();
  }

  final roleNames = operator.roleNames;
  final canSeeRnd = roleNames.contains('researcher');
  final canSeeProduction = roleNames.contains('production');
  final canSeeAll = canSeeRnd && canSeeProduction;

  final modes = <String>[];
  if (canSeeRnd) modes.add('rnd');
  if (canSeeProduction) modes.add('production');

  return RoleScope(
    canSeeRnd: canSeeRnd,
    canSeeProduction: canSeeProduction,
    canSeeAll: canSeeAll,
    availableModes: modes,
    isAdmin: false,
  );
});
