import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/platform/responsive.dart';

void main() {
  group('Responsive breakpoints', () {
    test('mobile breakpoint', () {
      expect(Responsive.isMobile(400), true);
      expect(Responsive.isMobile(700), false);
    });

    test('tablet breakpoint', () {
      expect(Responsive.isTablet(800), true);
      expect(Responsive.isTablet(400), false);
      expect(Responsive.isTablet(1300), false);
    });

    test('desktop breakpoint', () {
      expect(Responsive.isDesktop(1300), true);
      expect(Responsive.isDesktop(800), false);
    });

    test('column count for grid', () {
      expect(Responsive.gridColumns(400), 1);
      expect(Responsive.gridColumns(800), 2);
      expect(Responsive.gridColumns(1400), 3);
    });
  });
}
