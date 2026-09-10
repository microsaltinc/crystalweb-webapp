import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/projects/models/project.dart';

void main() {
  test('Project parses the API representation', () {
    final project = Project.fromJson({
      'id': 'project-1',
      'name': 'Dryer Optimization',
      'created_at': '2026-08-06T14:30:00Z',
    });
    expect(project.id, 'project-1');
    expect(project.name, 'Dryer Optimization');
    expect(project.createdAt, DateTime.utc(2026, 8, 6, 14, 30));
  });

  test('Project rejects malformed API representations', () {
    expect(
      () => Project.fromJson({'id': 'project-1'}),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => Project.fromJson({
        'id': 'project-1',
        'name': 'Name',
        'created_at': 'not-a-date',
      }),
      throwsFormatException,
    );
  });
}
