import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/core/theme/app_theme.dart';
import 'package:crystalapp/core/theme/app_colors.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses Material 3', () {
      expect(AppTheme.light.useMaterial3, true);
    });

    test('dark theme uses Material 3', () {
      expect(AppTheme.dark.useMaterial3, true);
    });

    test('light theme has correct primary color', () {
      expect(
        AppTheme.light.colorScheme.primary,
        AppColors.primary,
      );
    });

    test('font family is set', () {
      expect(AppTheme.light.textTheme.bodyLarge?.fontFamily, isNotNull);
    });
  });

  group('AppColors', () {
    test('status colors are distinct', () {
      expect(AppColors.success, isNot(equals(AppColors.error)));
      expect(AppColors.warning, isNot(equals(AppColors.error)));
    });

    test('crystal overlay colors exist', () {
      expect(AppColors.crystalModel, isNotNull);
      expect(AppColors.crystalHuman, isNotNull);
      expect(AppColors.crystalDiscarded, isNotNull);
    });
  });
}
