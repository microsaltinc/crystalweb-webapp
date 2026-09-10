import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/providers/role_scope_provider.dart';
import 'package:crystalapp/features/formulas/models/formula.dart';
import 'package:crystalapp/features/formulas/providers/formula_provider.dart';
import 'package:crystalapp/features/formulas/screens/formula_list_screen.dart';
import 'package:crystalapp/features/formulas/screens/formula_editor_screen.dart';

class MockDio extends Mock implements Dio {}

Future<void> selectFormulaField(
  WidgetTester tester,
  String fieldName,
  String value,
) async {
  await tester.tap(find.byKey(Key('formula-field-filter-$fieldName')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  final sampleFormulas = [
    Formula(
      id: '1',
      code: 'MS.CN.IO.GM.60-MX',
      description: 'Microsalt Mined Salt Iodized GMO 60 - Mexico',
      saltPct: 60,
      saltOrigin: 'MS',
      carrierOrigin: 'CN',
      iodine: 'IO',
      gmoStatus: 'GM',
      region: 'MX',
      active: true,
      createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
    ),
    Formula(
      id: '2',
      code: 'GR.SS.TAS.NI.IP.75',
      description: 'Microsalt Granulated Sea Salt Non-Iodized non-GMO 75',
      saltPct: 75,
      process: 'GR',
      saltOrigin: 'SS',
      carrierOrigin: 'TAS',
      iodine: 'NI',
      gmoStatus: 'IP',
      additive: 'MG',
      extraIngredients: const ['VIT', 'KC'],
      active: true,
      createdAt: DateTime.parse('2026-04-02T00:00:00Z'),
      isTesting: true,
    ),
  ];

  group('FormulaListScreen', () {
    testWidgets('shows formulas when loaded', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Shows formula codes
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
    });

    testWidgets('shows empty state when no formulas', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formulaListProvider.overrideWith(
              (ref) => Future.value(<Formula>[]),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No formulas yet'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formulaListProvider.overrideWith(
              (ref) => Future<List<Formula>>.error('Network error'),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load formulas'), findsOneWidget);
      expect(find.textContaining('Network error'), findsNothing);
    });

    testWidgets('has add button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('defaults to All and filters by Production and Experiment', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Experiment'), findsOneWidget);
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);

      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsNothing);

      await tester.tap(find.text('Experiment'));
      await tester.pumpAndSettle();
      expect(find.text('MS.CN.IO.GM.60-MX'), findsNothing);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
    });

    testWidgets('adds structured fields and composes them with mode filters', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'Process',
        'Salt Origin',
        'Carrier Origin',
        'Iodine',
        'GMO Status',
        'Salt Content',
        'Additive',
        'Region',
        'Extra Ingredient',
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Experiment'));
      await tester.pumpAndSettle();
      await selectFormulaField(tester, 'saltOrigin', 'SS');

      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
      expect(find.text('MS.CN.IO.GM.60-MX'), findsNothing);
      expect(find.text('1 of 2 formulas'), findsOneWidget);

      await selectFormulaField(tester, 'iodine', 'IO');
      expect(find.text('No formulas match these filters'), findsOneWidget);
      expect(find.text('0 of 2 formulas'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear formula filters'));
      await tester.pumpAndSettle();
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
      expect(find.byTooltip('Clear formula filters'), findsNothing);
    });

    testWidgets('filters nullable fields and extra ingredients', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await selectFormulaField(tester, 'region', 'None');
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
      expect(find.text('MS.CN.IO.GM.60-MX'), findsNothing);

      await tester.tap(find.byTooltip('Clear formula filters'));
      await tester.pumpAndSettle();
      await selectFormulaField(tester, 'extraIngredient', 'VIT');
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
      expect(find.text('MS.CN.IO.GM.60-MX'), findsNothing);
    });

    testWidgets('wraps field controls at narrow width and 200 percent text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaListProvider.overrideWith(
              (ref) => Future.value(sampleFormulas),
            ),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: FormulaListScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('formula-field-filter-saltOrigin')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('formula-field-filter-extraIngredient')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<InputChip>(
              find.byKey(const Key('formula-field-filter-saltOrigin')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows active-filter count and filtered-empty message', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaListProvider.overrideWith(
              (ref) => Future.value([sampleFormulas.first]),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Experiment'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 1 formulas'), findsOneWidget);
      expect(find.text('No formulas match these filters'), findsOneWidget);
      expect(find.text('No formulas yet'), findsNothing);
    });

    testWidgets('retains the selected mode when formula data refreshes', (
      tester,
    ) async {
      final formulaSource = StateProvider<List<Formula>>(
        (ref) => sampleFormulas,
      );
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              roleScopeProvider.overrideWithValue(const RoleScope.admin()),
              formulaListProvider.overrideWith(
                (ref) => Future.value(ref.watch(formulaSource)),
              ),
            ],
          ),
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      addTearDown(container.dispose);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Experiment'));
      await tester.pumpAndSettle();
      await selectFormulaField(tester, 'extraIngredient', 'VIT');
      container.read(formulaSource.notifier).state = [sampleFormulas.last];
      await tester.pumpAndSettle();

      final experimentChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Experiment'),
      );
      expect(experimentChip.selected, isTrue);
      expect(find.text('Extra Ingredient: VIT'), findsOneWidget);
      expect(find.text('1 of 1 formulas'), findsOneWidget);
      expect(find.text('GR.SS.TAS.NI.IP.75'), findsOneWidget);
    });

    testWidgets('offers only the permitted mode for a single-mode role', (
      tester,
    ) async {
      const productionScope = RoleScope(
        canSeeRnd: false,
        canSeeProduction: true,
        canSeeAll: false,
        availableModes: ['production'],
        isAdmin: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(productionScope),
            formulaListProvider.overrideWith(
              (ref) => Future.value([sampleFormulas.first]),
            ),
          ],
          child: const MaterialApp(home: FormulaListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsOneWidget);
      expect(find.text('All'), findsNothing);
      expect(find.text('Experiment'), findsNothing);
      expect(find.text('MS.CN.IO.GM.60-MX'), findsOneWidget);
    });
  });

  group('FormulaEditorScreen', () {
    testWidgets('places Testing Formula first in create mode', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
          ],
          child: const MaterialApp(home: FormulaEditorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final testingToggle = find.widgetWithText(
        SwitchListTile,
        'Testing Formula',
      );
      final formulaCode = find.byKey(const Key('formula-code-preview'));
      final granulatedToggle = find.widgetWithText(
        SwitchListTile,
        'Granulated',
      );

      expect(testingToggle, findsOneWidget);
      expect(
        tester.getTopLeft(testingToggle).dy,
        lessThan(tester.getTopLeft(formulaCode).dy),
      );
      expect(
        tester.getTopLeft(testingToggle).dy,
        lessThan(tester.getTopLeft(granulatedToggle).dy),
      );
      expect(tester.getBottomRight(testingToggle).dy, lessThanOrEqualTo(600));
    });

    testWidgets('places loaded Testing Formula first in edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaDetailProvider(
              '1',
            ).overrideWith((ref) => Future.value(sampleFormulas.first)),
          ],
          child: const MaterialApp(home: FormulaEditorScreen(formulaId: '1')),
        ),
      );
      await tester.pumpAndSettle();

      final testingToggle = find.widgetWithText(
        SwitchListTile,
        'Testing Formula',
      );
      final formulaCode = find.byKey(const Key('formula-code-preview'));

      expect(testingToggle, findsOneWidget);
      expect(
        tester.getTopLeft(testingToggle).dy,
        lessThan(tester.getTopLeft(formulaCode).dy),
      );
      expect(tester.widget<SwitchListTile>(testingToggle).value, isFalse);
      expect(tester.getBottomRight(testingToggle).dy, lessThanOrEqualTo(600));
    });

    testWidgets('keeps Testing Formula selectable for an administrator', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
          ],
          child: const MaterialApp(home: FormulaEditorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final testingToggle = find.widgetWithText(
        SwitchListTile,
        'Testing Formula',
      );
      expect(tester.widget<SwitchListTile>(testingToggle).onChanged, isNotNull);
      expect(tester.widget<SwitchListTile>(testingToggle).value, isFalse);

      await tester.tap(testingToggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(testingToggle).value, isTrue);
      expect(find.text('R&D'), findsOneWidget);
    });

    testWidgets('keeps Testing Formula locked to a researcher role', (
      tester,
    ) async {
      const researcherScope = RoleScope(
        canSeeRnd: true,
        canSeeProduction: false,
        canSeeAll: false,
        availableModes: ['rnd'],
        isAdmin: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [roleScopeProvider.overrideWithValue(researcherScope)],
          child: const MaterialApp(home: FormulaEditorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final testingToggle = find.widgetWithText(
        SwitchListTile,
        'Testing Formula',
      );
      final toggle = tester.widget<SwitchListTile>(testingToggle);
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      expect(find.text('Set by your operator role'), findsOneWidget);
      expect(find.text('R&D'), findsOneWidget);
    });

    testWidgets('keeps an existing testing formula irreversible', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScopeProvider.overrideWithValue(const RoleScope.admin()),
            formulaDetailProvider(
              '2',
            ).overrideWith((ref) => Future.value(sampleFormulas.last)),
          ],
          child: const MaterialApp(home: FormulaEditorScreen(formulaId: '2')),
        ),
      );
      await tester.pumpAndSettle();

      final testingToggle = find.widgetWithText(
        SwitchListTile,
        'Testing Formula',
      );
      final toggle = tester.widget<SwitchListTile>(testingToggle);
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      expect(
        find.text('Testing designation cannot be reverted'),
        findsOneWidget,
      );
      expect(find.text('R&D'), findsOneWidget);
    });

    testWidgets('keeps edits and shows actionable conflict before retry', (
      tester,
    ) async {
      final dio = MockDio();
      final request = RequestOptions(path: '/api/v1/formulas/1');
      var attempts = 0;
      when(
        () => dio.put<dynamic>('/api/v1/formulas/1', data: any(named: 'data')),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) {
          throw DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 409,
              data: {
                'detail':
                    'A formula with this code already exists. '
                    'Change the formula options and try again.',
              },
            ),
            type: DioExceptionType.badResponse,
          );
        }
        return Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'id': '1',
            'code': 'MS.CN.IO.GM.60-MX',
            'description': 'My retained description',
            'salt_pct': 60,
            'salt_origin': 'MS',
            'carrier_origin': 'CN',
            'iodine': 'IO',
            'gmo_status': 'GM',
            'extra_ingredients': <String>[],
            'active': true,
            'is_testing': false,
            'created_at': '2026-04-01T00:00:00Z',
          },
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
            formulaDetailProvider(
              '1',
            ).overrideWith((ref) => Future.value(sampleFormulas[0])),
          ],
          child: const MaterialApp(home: FormulaEditorScreen(formulaId: '1')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'My retained description',
      );
      await tester.ensureVisible(find.text('Save Formula'));
      await tester.tap(find.text('Save Formula'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('My retained description'), findsOneWidget);
      expect(find.text('Edit Formula'), findsOneWidget);

      await tester.ensureVisible(find.text('Save Formula'));
      await tester.tap(find.text('Save Formula'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
    });

    testWidgets('shows all segment dropdowns in create mode', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();

      // Check for labels of all segment selectors
      expect(find.text('Salt Origin'), findsOneWidget);
      expect(find.text('Carrier Origin'), findsOneWidget);
      expect(find.text('Salt Content'), findsOneWidget);
    });

    testWidgets('shows live code preview', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();

      // The code preview area should exist
      expect(find.byKey(const Key('formula-code-preview')), findsOneWidget);
    });

    testWidgets('code preview updates when segments change', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: FormulaEditorScreen())),
        ),
      );

      await tester.pumpAndSettle();

      // Find the code preview Text widget directly (it has the key)
      final previewFinder = find.byKey(const Key('formula-code-preview'));
      expect(previewFinder, findsOneWidget);

      // The preview should contain a non-empty code since defaults are set
      final previewWidget = tester.widget<Text>(previewFinder);
      expect(previewWidget.data, isNotNull);
      expect(previewWidget.data, isNotEmpty);
      // Default should be MS.CN.IO.GM.60
      expect(previewWidget.data, contains('MS.CN.IO.GM.60'));
    });

    testWidgets('shows save button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();

      expect(find.text('Save Formula'), findsOneWidget);
    });

    testWidgets('shows Granulated switch', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();

      expect(find.text('Granulated'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('auto-checks MG additive when granulated is on', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();

      // Find the Granulated switch and tap it
      final granulatedSwitch = find.widgetWithText(
        SwitchListTile,
        'Granulated',
      );
      expect(granulatedSwitch, findsOneWidget);
      await tester.tap(granulatedSwitch);
      await tester.pumpAndSettle();

      // The Magnesium Stearate checkbox should now be checked
      final mgCheckbox = find.widgetWithText(
        CheckboxListTile,
        'Magnesium Stearate (MG)',
      );
      expect(mgCheckbox, findsOneWidget);
      final checkboxWidget = tester.widget<CheckboxListTile>(mgCheckbox);
      expect(checkboxWidget.value, true);
    });

    testWidgets('shows title for create mode', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FormulaEditorScreen())),
      );

      await tester.pumpAndSettle();
      expect(find.text('New Formula'), findsOneWidget);
    });

    testWidgets('shows title for edit mode', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formulaDetailProvider(
              '1',
            ).overrideWith((ref) => Future.value(sampleFormulas[0])),
          ],
          child: const MaterialApp(home: FormulaEditorScreen(formulaId: '1')),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Edit Formula'), findsOneWidget);
    });
  });
}
