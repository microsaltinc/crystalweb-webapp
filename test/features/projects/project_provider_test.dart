import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/projects/providers/project_provider.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late ApiClient client;
  final projectJson = {
    'id': 'project-1',
    'name': 'Alpha',
    'created_at': '2026-08-06T14:30:00Z',
  };

  setUp(() {
    dio = MockDio();
    client = ApiClient.withDio(dio);
  });

  test('projectListProvider loads the organization-wide catalog', () async {
    when(() => dio.get('/api/v1/projects')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/projects'),
        data: [projectJson],
      ),
    );
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final projects = await container.read(projectListProvider.future);
    expect(projects.single.name, 'Alpha');
  });

  test('createProject trims input and sends JSON', () async {
    when(
      () => dio.post('/api/v1/projects', data: {'name': 'Alpha'}),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/projects'),
        data: projectJson,
      ),
    );
    final project = await createProject(client, '  Alpha  ');
    expect(project.name, 'Alpha');
  });

  test('assignProject sends nullable project id in the request body', () async {
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
    await assignProject(client, batchId: 'batch-1', projectId: null);
    verify(
      () => dio.patch(
        '/api/v1/projects/batch-1/assign',
        data: {'project_id': null},
      ),
    ).called(1);
  });

  test('projectErrorMessage extracts FastAPI detail', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/projects'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/projects'),
        data: {'detail': 'Project already exists'},
      ),
    );
    expect(projectErrorMessage(error), 'Project already exists');
  });
}
