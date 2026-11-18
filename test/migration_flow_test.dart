import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_migrator/app.dart';
import 'package:note_migrator/models/export_format.dart';
import 'package:note_migrator/models/note.dart';
import 'package:note_migrator/models/note_app.dart';
import 'package:note_migrator/services/parsers/note_parser.dart';
import 'package:note_migrator/services/storage_service.dart';
import 'package:note_migrator/state/migration_controller.dart';
import 'package:note_migrator/state/migration_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('sample Keep notes can be reviewed and exported', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const NoteMigratorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take your notes with you'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Google Keep'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview with sample notes'));
    await tester.pumpAndSettle();

    expect(find.text('Grocery run'), findsOneWidget);
    expect(find.text('Old draft'), findsNothing);
    expect(find.text('1 in trash'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Images stay behind'), findsOneWidget);
    expect(find.text('Checklists become text'), findsOneWidget);
    expect(find.text('Mi Notes'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create export'));
    await tester.pumpAndSettle();

    expect(find.text('Share this note'), findsOneWidget);
    expect(find.text('Grocery run'), findsOneWidget);
    expect(find.text('Note 1 of 4'), findsOneWidget);

    expect(preferences.getString(StorageService.historyKey), isNull);
  });

  test('mi notes source opens the notes in keep', () async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(migrationProvider.notifier);
    notifier.selectSource(NoteAppId.miNotes);
    expect(container.read(migrationProvider).target, NoteAppId.googleKeep);

    notifier.loadSample();
    final loaded = container.read(migrationProvider);
    expect(loaded.step, MigrationStep.preview);
    expect(loaded.source, NoteAppId.miNotes);
    expect(loaded.notes, hasLength(2));
    expect(loaded.notes.first.type, NoteType.checklist);

    await notifier.prepareExport();
    final exported = container.read(migrationProvider);
    expect(exported.step, MigrationStep.export);
    expect(exported.payload?.fileName, startsWith('keep-notes-'));
    expect(exported.history, isEmpty);

    await notifier.noteOpenedInTarget();
    expect(
      container.read(migrationProvider).history.single.routeLabel,
      'Mi Notes → Google Keep',
    );
  });

  test('trash stays unselected and search filters the review list', () async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    container.read(migrationProvider.notifier).loadSample();
    final loaded = container.read(migrationProvider);
    expect(loaded.step, MigrationStep.preview);
    expect(loaded.selectedNotes, hasLength(4));
    expect(loaded.selectedNotes.any((note) => note.isTrashed), isFalse);

    container.read(migrationProvider.notifier).setSearch('train');
    expect(
      container
          .read(migrationProvider)
          .visibleNotes
          .map((note) => note.displayTitle),
      ['Train receipt'],
    );

    container.read(migrationProvider.notifier).setSearch('');
    container.read(migrationProvider.notifier).setFilter(NoteFilter.trash);
    expect(
      container.read(migrationProvider).visibleNotes.single.displayTitle,
      'Old draft',
    );
  });

  test('a bad file stays on import and does not wipe a later export', () async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(migrationProvider.notifier);

    notifier.continueFromSource();
    await notifier.importFiles([
      const ImportedBytes(name: 'nope.zip', bytes: [1, 2, 3, 4]),
    ]);
    final failed = container.read(migrationProvider);
    expect(failed.step, MigrationStep.import);
    expect(failed.notes, isEmpty);
    expect(failed.error, isNotNull);
    expect(failed.parsing, isFalse);

    notifier.loadSample();
    notifier.continueFromPreview();
    await notifier.prepareExport();
    await notifier.prepareExport();
    expect(container.read(migrationProvider).history, isEmpty);
    await notifier.noteOpenedInTarget();
    await notifier.noteOpenedInTarget();
    expect(container.read(migrationProvider).history, hasLength(1));

    notifier.setFormat(ExportFormat.combinedText);
    await notifier.prepareExport();
    await notifier.noteOpenedInTarget();
    notifier.setFormat(ExportFormat.jsonBackup);
    await notifier.prepareExport();
    await notifier.noteOpenedInTarget();
    expect(container.read(migrationProvider).history, hasLength(3));
    expect(
      container
          .read(migrationProvider)
          .history
          .map((record) => record.formatLabel),
      ['JSON backup', 'One combined file', 'One file per note'],
    );

    final kept = container.read(migrationProvider).history;
    notifier.startOver();
    final fresh = container.read(migrationProvider);
    expect(fresh.step, MigrationStep.source);
    expect(fresh.notes, isEmpty);
    expect(fresh.history, kept);

    final stored = jsonDecode(
      preferences.getString(StorageService.historyKey)!,
    );
    expect(stored, hasLength(3));
  });

  testWidgets('back returns to the notes already read, with the search kept', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview with sample notes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'train');
    await tester.pumpAndSettle();
    expect(find.text('Train receipt'), findsOneWidget);
    expect(find.text('Grocery run'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Review 5 notes'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Review 5 notes'));
    await tester.pumpAndSettle();
    expect(find.text('Train receipt'), findsOneWidget);
    expect(find.text('train'), findsOneWidget);
    expect(find.text('Grocery run'), findsNothing);
  });

  testWidgets('review can open a note, clear the selection, and copy text', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview with sample notes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grocery run'));
    await tester.pumpAndSettle();
    expect(find.text('Include in export'), findsOneWidget);
    expect(find.textContaining('[ ] Milk'), findsWidgets);
    await tester.tap(find.text('Include in export'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 5 selected'), findsOneWidget);
    Navigator.of(tester.element(find.text('Include in export'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    final blocked = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(blocked.onPressed, isNull);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One combined file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create export'));
    await tester.pumpAndSettle();
    expect(find.text('Share text file'), findsOneWidget);

    expect(find.widgetWithText(TextButton, 'Copy note'), findsOneWidget);

    await tester.tap(find.byTooltip('Next note'));
    await tester.pumpAndSettle();
    expect(find.text('Note 2 of 4'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    final jsonTile = find.text('JSON backup');
    await tester.ensureVisible(jsonTile);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(jsonTile) + const Offset(12, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create export'));
    await tester.pumpAndSettle();
    expect(find.text('Share JSON backup'), findsOneWidget);

    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(find.text('Google Keep'), findsOneWidget);
    final historyButton = tester.getSemantics(find.byTooltip('Past exports'));
    expect(historyButton.tooltip, 'Past exports');
    expect(historyButton.label, isNot('3'));
    expect(find.bySemanticsLabel('3'), findsNothing);
    await tester.tap(find.byTooltip('Past exports'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A note shows up here after it opens in the other app. The note text is not stored in this list.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('short and dark layouts do not overflow', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const NoteMigratorApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 6; attempt++) {
      if (find.text('Preview with sample notes').evaluate().isNotEmpty) break;
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    final sample = find.text('Preview with sample notes');
    await tester.ensureVisible(sample);
    await tester.pumpAndSettle();
    await tester.tap(sample);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create export'));
    await tester.pumpAndSettle();
    expect(find.text('Share this note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const NoteMigratorApp(),
    ),
  );
  await tester.pumpAndSettle();
}
