import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/role_scope_provider.dart';
import '../../../core/routing/route_names.dart';
import '../../../platform/responsive.dart';
import '../widgets/app_nav_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool get _showCampaigns {
    final scope = ref.read(roleScopeProvider);
    return scope.canSeeProduction || scope.isAdmin;
  }

  bool get _showRnd {
    final scope = ref.read(roleScopeProvider);
    return scope.canSeeRnd || scope.isAdmin;
  }

  List<String> get _routes {
    final routes = <String>[];
    if (_showCampaigns) routes.add(RouteNames.batches);
    if (_showRnd) routes.add(RouteNames.rnd);
    routes.add(RouteNames.formulas);
    routes.addAll([RouteNames.operators, RouteNames.settings]);
    return routes;
  }

  int _currentIndexFromLocation(String location) {
    for (var i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  void _onDestinationSelected(int index) {
    if (index >= 0 && index < _routes.length) {
      context.go(_routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndexFromLocation(location);
    final width = MediaQuery.of(context).size.width;
    final useRail = Responsive.isDesktop(width) || Responsive.isTablet(width);

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: [
                if (_showCampaigns)
                  const NavigationRailDestination(
                    icon: Icon(Icons.science),
                    label: Text('Campaigns'),
                  ),
                if (_showRnd)
                  const NavigationRailDestination(
                    icon: Icon(Icons.biotech),
                    label: Text('R&D'),
                  ),
                const NavigationRailDestination(
                  icon: Icon(Icons.science_outlined),
                  label: Text('Formulas'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.people),
                  label: Text('Operators'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    final navItems = <BottomNavigationBarItem>[
      if (_showCampaigns)
        const BottomNavigationBarItem(
          icon: Icon(Icons.science),
          label: 'Campaigns',
        ),
      if (_showRnd)
        const BottomNavigationBarItem(icon: Icon(Icons.biotech), label: 'R&D'),
      const BottomNavigationBarItem(
        icon: Icon(Icons.science_outlined),
        label: 'Formulas',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.people),
        label: 'Operators',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: AppNavBar(
        currentIndex: currentIndex,
        onTap: _onDestinationSelected,
        items: navItems,
      ),
    );
  }
}
