import '../batches/models/batch.dart';

/// Applies the local R&D list filters after ownership and workflow filtering
/// have already been applied by the API.
List<Batch> filterRndBatches(
  List<Batch> batches, {
  DateTime? fromDate,
  DateTime? toDate,
  String? formulaCode,
  String? projectId,
  bool noProject = false,
}) {
  var filtered = batches;
  if (fromDate != null) {
    filtered = filtered
        .where((batch) => !batch.createdAt.isBefore(fromDate))
        .toList();
  }
  if (toDate != null) {
    final endOfDay = DateTime(
      toDate.year,
      toDate.month,
      toDate.day,
      23,
      59,
      59,
      999,
      999,
    );
    filtered = filtered
        .where((batch) => !batch.createdAt.isAfter(endOfDay))
        .toList();
  }
  if (formulaCode != null) {
    filtered = filtered
        .where((batch) => batch.formulaCode == formulaCode)
        .toList();
  }
  if (noProject) {
    filtered = filtered.where((batch) => batch.projectId == null).toList();
  } else if (projectId != null) {
    filtered = filtered.where((batch) => batch.projectId == projectId).toList();
  }
  return filtered;
}
