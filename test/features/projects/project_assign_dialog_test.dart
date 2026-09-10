import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/projects/models/project.dart';
import 'package:crystalapp/features/projects/providers/project_provider.dart';
import 'package:crystalapp/features/projects/widgets/project_assign_dialog.dart';

class MockDio extends Mock implements Dio {}

void main() {
  testWidgets('shows current catalog and supports explicit unassignment', (
    tester,
  ) async {
    final dio = MockDio();
    final client = ApiClient.withDio(dio);
    when(
      () => dio.patch(
        '/api/v1/projects/batch-1/assign',
        data: {'project_id': null},
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/projects/batch-1/assign'),
      ),
    );
    final projects = [
      Project(
        id: 'project-1',
        name: 'Alpha',
        createdAt: DateTime.utc(2026, 8, 6),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          projectListProvider.overrideWith((_) async => projects),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProjectAssignDialog(
              batchId: 'batch-1',
              currentProjectId: 'project-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text('No Project'));
    await tester.pumpAndSettle();
    verify(
      () => dio.patch(
        '/api/v1/projects/batch-1/assign',
        data: {'project_id': null},
      ),
    ).called(1);
  });

  testWidgets('blank inline creation stays open with validation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [projectListProvider.overrideWith((_) async => [])],
        child: const MaterialApp(
          home: Scaffold(
            body: ProjectAssignDialog(
              batchId: 'batch-1',
              currentProjectId: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create and assign Project'));
    await tester.pump();
    expect(find.text('Project name is required'), findsOneWidget);
    expect(find.byType(ProjectAssignDialog), findsOneWidget);
  });
}
