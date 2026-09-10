import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:uuid/uuid.dart';

import '../models/microscope_file_set.dart';

const _uuid = Uuid();

class _ParsedFile {
  const _ParsedFile({
    required this.file,
    required this.role,
    required this.stem,
    required this.exactKey,
    required this.matchKey,
  });

  final MicroscopeLocalFile file;
  final MicroscopeFileRole role;
  final String stem;
  final String exactKey;
  final String matchKey;
}

class _ExtensionMatch {
  const _ExtensionMatch(this.role, this.length);
  final MicroscopeFileRole role;
  final int length;
}

_ExtensionMatch? _extension(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tiff')) {
    return const _ExtensionMatch(MicroscopeFileRole.tiff, 5);
  }
  if (lower.endsWith('.tif')) {
    return const _ExtensionMatch(MicroscopeFileRole.tiff, 4);
  }
  if (lower.endsWith('.txt')) {
    return const _ExtensionMatch(MicroscopeFileRole.txt, 4);
  }
  return null;
}

MicroscopeFileRole? microscopeFileRoleForName(String name) =>
    _extension(name)?.role;

String canonicalMicroscopeBaseName(String value) =>
    unorm.nfc(value.trim()).toLowerCase();

String microscopeMatchKey(String value) => canonicalMicroscopeBaseName(
  value,
).replaceAll(RegExp(r'[.\s]+'), ' ').trim();

List<MicroscopeFileSet> groupMicroscopeFiles(
  Iterable<MicroscopeLocalFile> selected, {
  List<MicroscopeFileSet> existing = const [],
}) {
  final unique = <String, MicroscopeLocalFile>{};
  for (final file in selected) {
    unique['${file.path}\u0000${file.name}\u0000${file.sizeBytes}'] = file;
  }

  final parsed = <_ParsedFile>[];
  for (final file in unique.values) {
    final extension = _extension(file.name);
    if (extension == null || file.name.length <= extension.length) continue;
    final stem = file.name
        .substring(0, file.name.length - extension.length)
        .trim();
    if (stem.isEmpty) continue;
    parsed.add(
      _ParsedFile(
        file: file,
        role: extension.role,
        stem: stem,
        exactKey: canonicalMicroscopeBaseName(stem),
        matchKey: microscopeMatchKey(stem),
      ),
    );
  }

  final reusableIds = <String, String>{};
  for (final set in existing) {
    reusableIds['exact:${set.canonicalBaseName}'] = set.clientSetId;
    reusableIds.putIfAbsent(
      'match:${set.normalizedMatchKey}',
      () => set.clientSetId,
    );
  }

  final exactBuckets = <String, List<_ParsedFile>>{};
  for (final item in parsed) {
    exactBuckets.putIfAbsent(item.exactKey, () => []).add(item);
  }

  final result = <MicroscopeFileSet>[];
  final remaining = <_ParsedFile>[];
  for (final entry in exactBuckets.entries) {
    final byRole = _byRole(entry.value);
    final hasConflict = byRole.values.any((items) => items.length > 1);
    final complete = MicroscopeFileRole.values.every(
      (role) => byRole[role]?.length == 1,
    );
    if (complete || hasConflict) {
      result.add(
        _buildSet(
          entry.value,
          reusableIds: reusableIds,
          forceIssue: hasConflict
              ? 'More than one file has the same role.'
              : null,
        ),
      );
    } else {
      remaining.addAll(entry.value);
    }
  }

  final matchBuckets = <String, List<_ParsedFile>>{};
  for (final item in remaining) {
    matchBuckets.putIfAbsent(item.matchKey, () => []).add(item);
  }
  for (final entry in matchBuckets.entries) {
    final byRole = _byRole(entry.value);
    final ambiguous = byRole.values.any((items) => items.length > 1);
    result.add(
      _buildSet(
        entry.value,
        reusableIds: reusableIds,
        forceIssue: ambiguous
            ? 'Filename normalization matches more than one possible file.'
            : null,
      ),
    );
  }

  result.sort(
    (left, right) => left.logicalBaseName.toLowerCase().compareTo(
      right.logicalBaseName.toLowerCase(),
    ),
  );
  return result;
}

Map<MicroscopeFileRole, List<_ParsedFile>> _byRole(
  Iterable<_ParsedFile> files,
) {
  final result = <MicroscopeFileRole, List<_ParsedFile>>{};
  for (final file in files) {
    result.putIfAbsent(file.role, () => []).add(file);
  }
  return result;
}

MicroscopeFileSet _buildSet(
  List<_ParsedFile> parsed, {
  required Map<String, String> reusableIds,
  String? forceIssue,
}) {
  final byRole = _byRole(parsed);
  final preferred = byRole[MicroscopeFileRole.tiff]?.first ?? parsed.first;
  final exactKey = preferred.exactKey;
  final matchKey = preferred.matchKey;
  final files = <MicroscopeFileRole, MicroscopeLocalFile>{};
  final conflicts = <MicroscopeLocalFile>[];
  for (final entry in byRole.entries) {
    files[entry.key] = entry.value.first.file;
    conflicts.addAll(entry.value.skip(1).map((item) => item.file));
  }
  final id =
      reusableIds['exact:$exactKey'] ??
      reusableIds['match:$matchKey'] ??
      _uuid.v4();
  return MicroscopeFileSet(
    clientSetId: id,
    logicalBaseName: preferred.stem,
    canonicalBaseName: exactKey,
    normalizedMatchKey: matchKey,
    files: Map.unmodifiable(files),
    conflictingFiles: List.unmodifiable(conflicts),
    issues: forceIssue == null ? const [] : [forceIssue],
  );
}
