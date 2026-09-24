@TestOn('browser')
library;

import 'package:crystalapp/features/settings/providers/selected_annotation_size_provider.dart';
import 'package:crystalapp/features/settings/widgets/selected_annotation_size_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _storageKey = 'crystalweb.selectedAnnotationSize';

void main() {
  String? previousValue;

  setUp(() {
    previousValue = web.window.localStorage.getItem(_storageKey);
    web.window.localStorage.removeItem(_storageKey);
  });

  tearDown(() {
    if (previousValue == null) {
      web.window.localStorage.removeItem(_storageKey);
    } else {
      web.window.localStorage.setItem(_storageKey, previousValue!);
    }
  });

  testWidgets('dropdown persists a browser preference across app sessions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SelectedAnnotationSizeSetting(),
            ),
          ),
        ),
      ),
    );
    expect(container.read(selectedAnnotationSizeProvider), 1);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(dropdown.initialValue, 1);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    for (final label in ['1× (default)', '2×', '3×', '4×', '5×']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('4×').last);
    await tester.pumpAndSettle();

    expect(container.read(selectedAnnotationSizeProvider), 4);
    expect(web.window.localStorage.getItem(_storageKey), '4');
    final nextSession = ProviderContainer();
    addTearDown(nextSession.dispose);
    expect(nextSession.read(selectedAnnotationSizeProvider), 4);
    expect(tester.takeException(), isNull);
  });

  test(
    'invalid stored preferences fall back and invalid writes are rejected',
    () {
      for (final stored in ['0', '-1', '6', '1.5', 'invalid']) {
        web.window.localStorage.setItem(_storageKey, stored);
        final notifier = SelectedAnnotationSizeNotifier();
        expect(notifier.state, 1);
        expect(() => notifier.setSize(0), throwsRangeError);
        expect(() => notifier.setSize(6), throwsRangeError);
        expect(notifier.state, 1);
        expect(web.window.localStorage.getItem(_storageKey), stored);
        notifier.dispose();
      }
    },
  );

  testWidgets(
    'blocked storage still applies the size and explains persistence',
    (tester) async {
      final notifier = SelectedAnnotationSizeNotifier(
        read: () => throw StateError('Storage blocked'),
        write: (_) => throw StateError('Storage blocked'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedAnnotationSizeProvider.overrideWith((_) => notifier),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SelectedAnnotationSizeSetting()),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5×').last);
      await tester.pumpAndSettle();
      expect(notifier.state, 5);
      expect(
        find.textContaining('Your browser could not save it'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
