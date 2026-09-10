class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String name;
  final DateTime createdAt;
}
