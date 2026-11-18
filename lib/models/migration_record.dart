/// A finished export, stored locally. Note text is not stored.
class MigrationRecord {
  const MigrationRecord({
    required this.id,
    required this.completedAt,
    required this.noteCount,
    required this.checklistCount,
    required this.attachmentCount,
    required this.formatLabel,
    this.routeLabel = 'Google Keep → Mi Notes',
  });

  final String id;
  final DateTime completedAt;
  final int noteCount;
  final int checklistCount;
  final int attachmentCount;
  final String formatLabel;

  /// `Google Keep → Mi Notes` or the other direction. Older history has none.
  final String routeLabel;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'completedAt': completedAt.toIso8601String(),
      'noteCount': noteCount,
      'checklistCount': checklistCount,
      'attachmentCount': attachmentCount,
      'formatLabel': formatLabel,
      'routeLabel': routeLabel,
    };
  }

  static MigrationRecord? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final completedAt = json['completedAt'];
    if (id is! String || completedAt is! String) return null;
    final parsed = DateTime.tryParse(completedAt);
    if (parsed == null) return null;
    return MigrationRecord(
      id: id,
      completedAt: parsed,
      noteCount: _asInt(json['noteCount']),
      checklistCount: _asInt(json['checklistCount']),
      attachmentCount: _asInt(json['attachmentCount']),
      formatLabel: json['formatLabel'] is String
          ? json['formatLabel'] as String
          : 'Export',
      routeLabel: json['routeLabel'] is String
          ? json['routeLabel'] as String
          : 'Google Keep → Mi Notes',
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}
