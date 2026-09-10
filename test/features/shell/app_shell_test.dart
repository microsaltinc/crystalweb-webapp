import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/shell/widgets/app_nav_bar.dart';

const _navItems = <BottomNavigationBarItem>[
  BottomNavigationBarItem(icon: Icon(Icons.science), label: 'Campaigns'),
  BottomNavigationBarItem(icon: Icon(Icons.functions), label: 'Formulas'),
  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
];

Widget _buildNavBar({int currentIndex = 0, ValueChanged<int>? onTap}) {
  return MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AppNavBar(
        currentIndex: currentIndex,
        onTap: onTap ?? (_) {},
        items: _navItems,
      ),
    ),
  );
}

void main() {
  group('AppNavBar', () {
    testWidgets('renders the supplied navigation items', (tester) async {
      await tester.pumpWidget(_buildNavBar());

      expect(find.text('Campaigns'), findsOneWidget);
      expect(find.text('Formulas'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('uses the supplied current index', (tester) async {
      await tester.pumpWidget(_buildNavBar(currentIndex: 1));

      final navBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(navBar.currentIndex, 1);
    });

    testWidgets('forwards navigation item taps', (tester) async {
      int? tappedIndex;
      await tester.pumpWidget(
        _buildNavBar(onTap: (index) => tappedIndex = index),
      );

      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(tappedIndex, 2);
    });
  });
}
