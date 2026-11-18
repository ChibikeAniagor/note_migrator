import '../models/export_format.dart';
import '../models/migration_record.dart';
import '../models/note.dart';
import '../models/note_app.dart';

enum MigrationStep { onboarding, source, import, preview, target, export }

enum NoteFilter { all, text, lists, pinned, archived, trash }

class MigrationState {
  const MigrationState({
    required this.step,
    required this.source,
    required this.target,
    required this.notes,
    required this.selectedIds,
    required this.filter,
    required this.search,
    required this.format,
    required this.parsing,
    required this.error,
    required this.importWarnings,
    required this.history,
    required this.shareIndex,
    required this.exportSaved,
    required this.payload,
  });

  factory MigrationState.initial({
    required bool onboardingSeen,
    required List<MigrationRecord> history,
  }) {
    return MigrationState(
      step: onboardingSeen ? MigrationStep.source : MigrationStep.onboarding,
      source: NoteAppId.googleKeep,
      target: NoteAppId.miNotes,
      notes: const [],
      selectedIds: const {},
      filter: NoteFilter.all,
      search: '',
      format: ExportFormat.perNoteZip,
      parsing: false,
      error: null,
      importWarnings: const [],
      history: history,
      shareIndex: 0,
      exportSaved: false,
      payload: null,
    );
  }

  final MigrationStep step;
  final NoteAppId source;
  final NoteAppId target;
  final List<UniversalNote> notes;
  final Set<String> selectedIds;
  final NoteFilter filter;
  final String search;
  final ExportFormat format;
  final bool parsing;
  final String? error;
  final List<String> importWarnings;
  final List<MigrationRecord> history;
  final int shareIndex;
  final bool exportSaved;
  final ExportPayload? payload;

  List<UniversalNote> get selectedNotes => [
    for (final note in notes)
      if (selectedIds.contains(note.id)) note,
  ];

  int get trashedCount => notes.where((note) => note.isTrashed).length;

  List<UniversalNote> get visibleNotes {
    final query = search.trim().toLowerCase();
    return [
      for (final note in notes)
        if (_matchesFilter(note) && _matchesQuery(note, query)) note,
    ];
  }

  bool _matchesFilter(UniversalNote note) {
    return switch (filter) {
      NoteFilter.all => !note.isTrashed,
      NoteFilter.text => !note.isTrashed && note.type == NoteType.text,
      NoteFilter.lists => !note.isTrashed && note.type == NoteType.checklist,
      NoteFilter.pinned => !note.isTrashed && note.isPinned,
      NoteFilter.archived => !note.isTrashed && note.isArchived,
      NoteFilter.trash => note.isTrashed,
    };
  }

  bool _matchesQuery(UniversalNote note, String query) {
    if (query.isEmpty) return true;
    final haystack = [
      note.title,
      note.content,
      ...note.tags,
      ...note.checklistItems.map((item) => item.text),
    ].join('\n').toLowerCase();
    return haystack.contains(query);
  }

  MigrationState copyWith({
    MigrationStep? step,
    NoteAppId? source,
    NoteAppId? target,
    List<UniversalNote>? notes,
    Set<String>? selectedIds,
    NoteFilter? filter,
    String? search,
    ExportFormat? format,
    bool? parsing,
    String? error,
    bool clearError = false,
    List<String>? importWarnings,
    List<MigrationRecord>? history,
    int? shareIndex,
    bool? exportSaved,
    ExportPayload? payload,
    bool clearPayload = false,
  }) {
    return MigrationState(
      step: step ?? this.step,
      source: source ?? this.source,
      target: target ?? this.target,
      notes: notes ?? this.notes,
      selectedIds: selectedIds ?? this.selectedIds,
      filter: filter ?? this.filter,
      search: search ?? this.search,
      format: format ?? this.format,
      parsing: parsing ?? this.parsing,
      error: clearError ? null : error ?? this.error,
      importWarnings: importWarnings ?? this.importWarnings,
      history: history ?? this.history,
      shareIndex: shareIndex ?? this.shareIndex,
      exportSaved: exportSaved ?? this.exportSaved,
      payload: clearPayload ? null : payload ?? this.payload,
    );
  }
}
