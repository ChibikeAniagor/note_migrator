import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_migrator/models/export_format.dart';
import 'package:note_migrator/models/note.dart';
import 'package:note_migrator/services/exporters/mi_notes_exporter.dart';
import 'package:note_migrator/services/exporters/mi_notes_text.dart';

void main() {
  final clock = DateTime(2026, 3, 9, 12, 4);

  UniversalNote note({
    String id = '1',
    String title = 'Grocery run',
    String content = '',
    String? color = 'YELLOW',
    bool pinned = true,
    List<String> tags = const ['home'],
    List<ChecklistItem> checklist = const [
      ChecklistItem(text: 'Milk', isChecked: false),
      ChecklistItem(text: 'Eggs', isChecked: true),
    ],
    List<AttachmentRef> attachments = const [],
    List<String> links = const [],
    bool keepModified = true,
  }) {
    return UniversalNote(
      id: id,
      title: title,
      content: content,
      createdAt: DateTime.utc(2024, 3, 1, 9),
      modifiedAt: keepModified ? DateTime.utc(2024, 3, 2, 10, 30) : null,
      tags: tags,
      color: color,
      isPinned: pinned,
      isArchived: false,
      isTrashed: false,
      attachments: attachments,
      type: checklist.isEmpty ? NoteType.text : NoteType.checklist,
      checklistItems: checklist,
      links: links,
      sourceFileName: 'note.json',
    );
  }

  test('writes color, labels, status, and checklist lines', () {
    final text = renderMiNote(note());
    expect(text, startsWith('Grocery run\n'));
    expect(text, contains('Color: Yellow'));
    expect(text, contains('Labels: home'));
    expect(text, contains('Status: Pinned'));
    expect(text, contains('[ ] Milk'));
    expect(text, contains('[x] Eggs'));
    expect(text, isNot(contains('Color: DEFAULT')));
  });

  test('omits a default color and names attachments that were not copied', () {
    final text = renderMiNote(
      note(
        title: 'Kitchen sketch',
        content: 'Move the shelf.',
        color: null,
        pinned: false,
        tags: const [],
        checklist: const [],
        attachments: const [
          AttachmentRef(fileName: 'shelf.png', mimeType: 'image/png'),
        ],
        links: const ['https://example.com/shelf'],
      ),
    );
    expect(text, isNot(contains('Color:')));
    expect(text, isNot(contains('Labels:')));
    expect(text, isNot(contains('Status:')));
    expect(text, contains('Move the shelf.'));
    expect(text, contains('Links:\n- https://example.com/shelf'));
    expect(text, contains('Attachments not included:\n- shelf.png'));
  });

  test('does not repeat an inferred title inside the body', () {
    final text = renderMiNote(
      note(
        title: '',
        content: 'Remember the keys\nAnd the code.',
        color: null,
        pinned: false,
        tags: const [],
        checklist: const [],
        keepModified: false,
      ),
    );
    expect(text, startsWith('Remember the keys\n'));
    expect(
      RegExp(RegExp.escape('Remember the keys')).allMatches(text),
      hasLength(1),
    );
    expect(text, contains('And the code.'));
    expect(text, contains('Created:'));
  });

  test(
    'zip export gives each note its own text file and renames duplicates',
    () {
      final payload = const MiNotesExporter().export(
        [
          note(id: '1', title: 'Same'),
          note(id: '2', title: 'Same'),
          note(id: '3', title: 'Report: Q1/draft'),
        ],
        ExportFormat.perNoteZip,
        now: clock,
      );
      expect(payload.fileName, 'mi-notes-20260309-1204.zip');
      final archive = ZipDecoder().decodeBytes(payload.bytes);
      expect(archive.files.map((file) => file.name).toList(), [
        'Same.txt',
        'Same-2.txt',
        'Report Q1 draft.txt',
      ]);
      final first = utf8.decode(archive.files.first.readBytes()!);
      expect(first, contains('[ ] Milk'));
    },
  );

  test('combined export separates notes', () {
    final payload = const MiNotesExporter().export(
      [
        note(id: '1', title: 'One'),
        note(id: '2', title: 'Two', checklist: const []),
      ],
      ExportFormat.combinedText,
      now: clock,
    );
    final text = utf8.decode(payload.bytes);
    expect(text, contains('2 notes'));
    expect(text, contains('----------'));
    expect(text, contains('One'));
    expect(text, contains('Two'));
  });

  test('JSON backup keeps the structured fields', () {
    final payload = const MiNotesExporter().export(
      [note()],
      ExportFormat.jsonBackup,
      now: clock,
    );
    final json = jsonDecode(utf8.decode(payload.bytes)) as Map<String, dynamic>;
    expect(json['format'], 'note-migrator/v1');
    expect(json['source'], 'google_keep');
    expect(json['target'], 'mi_notes');
    final notes = json['notes'] as List<dynamic>;
    expect(notes, hasLength(1));
    expect(notes.single['title'], 'Grocery run');
    expect(notes.single['checklist'], hasLength(2));
  });

  test('refuses an empty selection', () {
    expect(
      () => const MiNotesExporter().export(const [], ExportFormat.perNoteZip),
      throwsA(isA<ExportException>()),
    );
  });

  test('warnings describe what Mi Notes cannot keep', () {
    final warnings = conversionWarnings([
      note(attachments: const [AttachmentRef(fileName: 'a.png')]),
    ]);
    expect(
      warnings.map((warning) => warning.title),
      contains('Images stay behind'),
    );
    expect(
      warnings.map((warning) => warning.title),
      contains('Colors become a line of text'),
    );
    expect(
      warnings.map((warning) => warning.title),
      contains('Checklists become text'),
    );
  });
}
