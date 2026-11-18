import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_format.dart';
import '../models/migration_record.dart';
import '../models/note.dart';
import '../models/note_app.dart';
import '../services/exporters/mi_notes_exporter.dart';
import '../services/parsers/google_keep_parser.dart';
import '../services/parsers/mi_notes_parser.dart';
import '../services/parsers/note_parser.dart';
import '../services/parsers/sample_keep_notes.dart';
import '../services/storage_service.dart';
import 'migration_state.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('SharedPreferences was not provided at startup.');
});

final migrationProvider = NotifierProvider<MigrationController, MigrationState>(
  MigrationController.new,
);

class MigrationController extends Notifier<MigrationState> {
  @override
  MigrationState build() {
    final storage = StorageService(ref.watch(sharedPreferencesProvider));
    return MigrationState.initial(
      onboardingSeen: storage.onboardingSeen,
      history: storage.readHistory(),
    );
  }

  StorageService get _storage =>
      StorageService(ref.read(sharedPreferencesProvider));

  Future<void> completeOnboarding() async {
    await _storage.setOnboardingSeen();
    state = state.copyWith(step: MigrationStep.source);
  }

  void showOnboarding() {
    state = state.copyWith(step: MigrationStep.onboarding);
  }

  void back() {
    final previous = switch (state.step) {
      MigrationStep.import => MigrationStep.source,
      MigrationStep.preview => MigrationStep.import,
      MigrationStep.target => MigrationStep.preview,
      MigrationStep.export => MigrationStep.target,
      _ => null,
    };
    if (previous == null) return;
    state = state.copyWith(step: previous, clearError: true);
  }

  void selectSource(NoteAppId source) {
    if (source != NoteAppId.googleKeep && source != NoteAppId.miNotes) return;
    if (source == state.source) return;
    state = state.copyWith(
      source: source,
      target: source.opposite,
      notes: const [],
      selectedIds: const {},
      importWarnings: const [],
      clearError: true,
      clearPayload: true,
      exportSaved: false,
      shareIndex: 0,
      search: '',
      filter: NoteFilter.all,
    );
  }

  void continueFromSource() {
    state = state.copyWith(step: MigrationStep.import, clearError: true);
  }

  /// Import stays on screen after Back. The notes already read are still here.
  void returnToPreview() {
    if (state.notes.isEmpty) return;
    state = state.copyWith(step: MigrationStep.preview, clearError: true);
  }

  void continueFromPreview() {
    if (state.selectedNotes.isEmpty) {
      state = state.copyWith(error: 'Select at least one note.');
      return;
    }
    state = state.copyWith(step: MigrationStep.target, clearError: true);
  }

  Future<void> importFiles(List<ImportedBytes> files) async {
    if (files.isEmpty) {
      state = state.copyWith(error: _emptyChoice(state.source));
      return;
    }
    state = state.copyWith(parsing: true, clearError: true);
    final routed = await _parseRouted(files);
    if (routed.notes.isEmpty) {
      final message = state.source == NoteAppId.miNotes
          ? (routed.miFatal ?? 'No notes were found in that file.')
          : (routed.keepFatal ??
                'No Google Keep notes were found in that file.');
      state = state.copyWith(
        parsing: false,
        error: message,
        importWarnings: routed.warnings,
      );
      return;
    }
    _adopt(routed.result, source: routed.detectedSource ?? state.source);
  }

  /// Notes another app shared in. Same-source notes are added to the list.
  Future<void> importIncoming(
    List<ImportedBytes> files, {
    NoteAppId? sender,
    String? error,
  }) async {
    if (!_storage.onboardingSeen) {
      await _storage.setOnboardingSeen();
    }
    if (error != null && files.isEmpty) {
      state = state.copyWith(
        step: MigrationStep.import,
        parsing: false,
        error: error,
      );
      return;
    }
    if (files.isEmpty) return;
    state = state.copyWith(parsing: true, clearError: true);
    final routed = await _parseRouted(files);
    if (routed.notes.isEmpty) {
      state = state.copyWith(
        step: MigrationStep.import,
        parsing: false,
        error: error ?? 'That share did not contain a note.',
        importWarnings: routed.warnings,
      );
      return;
    }
    final source = sender ?? routed.detectedSource ?? state.source;
    final sameList = source == state.source && state.notes.isNotEmpty;
    if (!sameList) {
      _adopt(routed.result, source: source);
      return;
    }
    _append(routed.notes, source);
  }

  void loadSample() {
    state = state.copyWith(parsing: false, clearError: true);
    if (state.source == NoteAppId.miNotes) {
      _adopt(parseMiNotesFiles(sampleMiNotesFiles()), source: NoteAppId.miNotes);
      return;
    }
    _adopt(parseKeepFiles(sampleKeepFiles()), source: NoteAppId.googleKeep);
  }

  void _adopt(ParseResult result, {NoteAppId? source}) {
    if (result.fatal != null || result.notes.isEmpty) {
      state = state.copyWith(
        parsing: false,
        error: result.fatal ?? _emptyChoice(source ?? state.source),
        importWarnings: result.warnings,
      );
      return;
    }
    final from = source ?? result.detectedSource ?? state.source;
    state = state.copyWith(
      parsing: false,
      clearError: true,
      source: from,
      target: from.opposite,
      notes: result.notes,
      selectedIds: {
        for (final note in result.notes)
          if (!note.isTrashed) note.id,
      },
      importWarnings: result.warnings,
      filter: NoteFilter.all,
      search: '',
      shareIndex: 0,
      exportSaved: false,
      clearPayload: true,
      step: MigrationStep.preview,
    );
  }

  void _append(List<UniversalNote> incoming, NoteAppId source) {
    final used = {for (final note in state.notes) note.id};
    final seen = {
      for (final note in state.notes) _fingerprint(note),
    };
    final notes = [...state.notes];
    final selected = {...state.selectedIds};
    for (final note in incoming) {
      if (!seen.add(_fingerprint(note))) continue;
      var id = note.id;
      var suffix = 2;
      while (!used.add(id)) {
        id = '${note.id}#$suffix';
        suffix++;
      }
      final stored = id == note.id ? note : note.withId(id);
      notes.add(stored);
      if (!stored.isTrashed) selected.add(stored.id);
    }
    state = state.copyWith(
      parsing: false,
      clearError: true,
      source: source,
      target: source.opposite,
      notes: notes,
      selectedIds: selected,
      shareIndex: 0,
      exportSaved: false,
      clearPayload: true,
      step: MigrationStep.preview,
    );
  }

  Future<_RoutedParse> _parseRouted(List<ImportedBytes> files) async {
    final keep = await _runKeep(files);
    if (keep.notes.isNotEmpty) {
      final result = ParseResult(
        notes: keep.notes,
        warnings: keep.warnings,
        detectedSource: NoteAppId.googleKeep,
      );
      return _RoutedParse(
        result: result,
        notes: keep.notes,
        detectedSource: NoteAppId.googleKeep,
        warnings: keep.warnings,
      );
    }
    final mi = await _runMi(files);
    return _RoutedParse(
      result: mi,
      notes: mi.notes,
      detectedSource: mi.detectedSource,
      keepFatal: keep.fatal,
      miFatal: mi.fatal,
      warnings: mi.warnings,
    );
  }

  Future<ParseResult> _runKeep(List<ImportedBytes> files) async {
    try {
      return await Isolate.run(() => parseKeepFiles(files));
    } catch (_) {
      return parseKeepFiles(files);
    }
  }

  Future<ParseResult> _runMi(List<ImportedBytes> files) async {
    try {
      return await Isolate.run(() => parseMiNotesFiles(files));
    } catch (_) {
      return parseMiNotesFiles(files);
    }
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void setFilter(NoteFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void toggleNote(String id) {
    final next = {...state.selectedIds};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(
      selectedIds: next,
      exportSaved: false,
      clearError: true,
    );
  }

  void setVisibleSelected(bool selected) {
    final next = {...state.selectedIds};
    for (final note in state.visibleNotes) {
      if (selected) {
        next.add(note.id);
      } else {
        next.remove(note.id);
      }
    }
    state = state.copyWith(selectedIds: next, exportSaved: false);
  }

  void setFormat(ExportFormat format) {
    state = state.copyWith(format: format, exportSaved: false);
  }

  void setShareIndex(int index) {
    final count = state.payload?.notes.length ?? 0;
    if (count == 0) return;
    final next = index < 0 ? 0 : (index >= count ? count - 1 : index);
    state = state.copyWith(shareIndex: next);
  }

  Future<void> prepareExport() async {
    final selected = state.selectedNotes;
    if (selected.isEmpty) {
      state = state.copyWith(error: 'Select at least one note.');
      return;
    }
    final ExportPayload payload;
    try {
      payload = const MiNotesExporter().export(
        selected,
        state.format,
        source: state.source,
        target: state.target,
      );
    } on ExportException catch (error) {
      state = state.copyWith(error: error.message);
      return;
    }

    state = state.copyWith(
      payload: payload,
      step: MigrationStep.export,
      shareIndex: 0,
      clearError: true,
    );
  }

  /// Records the transfer once the other app has actually opened a note.
  Future<void> noteOpenedInTarget() async {
    final payload = state.payload;
    if (payload == null || state.exportSaved) return;
    final selected = state.selectedNotes;
    final record = MigrationRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      completedAt: DateTime.now(),
      noteCount: selected.isEmpty ? payload.notes.length : selected.length,
      checklistCount: selected
          .where((note) => note.checklistItems.isNotEmpty)
          .length,
      attachmentCount: selected
          .where((note) => note.attachments.isNotEmpty)
          .length,
      formatLabel: payload.format.label,
      routeLabel: '${state.source.label} → ${state.target.label}',
    );
    var history = state.history;
    try {
      await _storage.addRecord(record);
      history = [record, ...state.history];
    } catch (_) {
      return;
    }
    state = state.copyWith(exportSaved: true, history: history);
  }

  void startOver() {
    state = MigrationState.initial(
      onboardingSeen: true,
      history: state.history,
    );
  }
}

class _RoutedParse {
  const _RoutedParse({
    required this.result,
    required this.notes,
    this.detectedSource,
    this.keepFatal,
    this.miFatal,
    this.warnings = const [],
  });

  final ParseResult result;
  final List<UniversalNote> notes;
  final NoteAppId? detectedSource;
  final String? keepFatal;
  final String? miFatal;
  final List<String> warnings;
}

String _emptyChoice(NoteAppId source) {
  return source == NoteAppId.miNotes
      ? 'Choose a text or JSON file from Mi Notes.'
      : 'Choose a Takeout zip or Keep JSON file.';
}

String _fingerprint(UniversalNote note) {
  final checks = [
    for (final item in note.checklistItems) '${item.isChecked}:${item.text}',
  ].join('\n');
  return '${note.displayTitle}\n${note.content}\n$checks';
}
