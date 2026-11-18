import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_migrator/models/note.dart';
import 'package:note_migrator/models/note_app.dart';
import 'package:note_migrator/services/parsers/mi_notes_parser.dart';
import 'package:note_migrator/services/parsers/note_parser.dart';

void main() {
  test('plain text and a divider become separate notes', () {
    final result = parseMiNotesFiles([
      ImportedBytes(
        name: 'notes.txt',
        bytes: utf8.encode('''
Market run

Color: Yellow
Labels: home, errand
Status: Pinned

[ ] Eggs
[x] Bread

----------

Train idea

Write down the platform number.
'''),
      ),
    ]);

    expect(result.fatal, isNull);
    expect(result.notes, hasLength(2));
    final market = result.notes.first;
    expect(market.displayTitle, 'Market run');
    expect(market.color, 'YELLOW');
    expect(market.tags, ['home', 'errand']);
    expect(market.isPinned, isTrue);
    expect(market.type, NoteType.checklist);
    expect(market.checklistItems.map((item) => item.text), ['Eggs', 'Bread']);
    expect(market.checklistItems.last.isChecked, isTrue);
    expect(result.notes.last.displayTitle, 'Train idea');
    expect(result.notes.last.content, contains('platform number'));
  });

  test('a note-migrator backup keeps the source it was written with', () {
    final result = parseMiNotesFiles([
      ImportedBytes(
        name: 'backup.json',
        bytes: utf8.encode(
          jsonEncode({
            'format': 'note-migrator/v1',
            'source': 'mi_notes',
            'target': 'google_keep',
            'notes': [
              {
                'title': 'Saved',
                'content': 'From Mi Notes',
                'isPinned': false,
                'type': 'text',
                'checklist': <Object>[],
              },
            ],
          }),
        ),
      ),
    ]);

    expect(result.detectedSource, NoteAppId.miNotes);
    expect(result.notes.single.displayTitle, 'Saved');
    expect(result.notes.single.content, 'From Mi Notes');
  });

  test('a Mi cloud list uses subject and snippet', () {
    final result = parseMiNotesFiles([
      ImportedBytes(
        name: 'cloud.json',
        bytes: utf8.encode(
          jsonEncode([
            {
              'subject': 'Market',
              'snippet': '<div>Eggs<br>Milk</div>',
              'createDate': 1710000000000,
              'modifyDate': 1710000001000,
            },
          ]),
        ),
      ),
    ]);

    expect(result.notes.single.displayTitle, 'Market');
    expect(result.notes.single.content, contains('Eggs'));
    expect(result.notes.single.content, contains('Milk'));
    expect(result.notes.single.createdAt, isNotNull);
  });
}
