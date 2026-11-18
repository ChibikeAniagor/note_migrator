import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_migrator/models/note.dart';
import 'package:note_migrator/services/parsers/google_keep_parser.dart';
import 'package:note_migrator/services/parsers/note_parser.dart';
import 'package:note_migrator/services/parsers/sample_keep_notes.dart';

void main() {
  const parser = GoogleKeepParser();

  test('reads a text note, labels, link, and microsecond timestamps', () {
    final result = parser.parse([
      ImportedBytes(name: 'meeting.json', bytes: utf8.encode(_textNote)),
    ]);

    expect(result.fatal, isNull);
    expect(result.notes, hasLength(1));
    final note = result.notes.single;
    expect(note.title, 'Monday standup');
    expect(note.type, NoteType.text);
    expect(note.content, contains('Priya'));
    expect(note.tags, ['work', 'follow-up']);
    expect(note.links, ['https://takeout.google.com']);
    expect(note.color, isNull);
    expect(note.isPinned, isFalse);
    expect(note.createdAt, isNotNull);
    expect(note.modifiedAt!.isAfter(note.createdAt!), isTrue);
  });

  test('reads a checklist and keeps text that sits beside it', () {
    final result = parser.parse([
      ImportedBytes(name: 'list.json', bytes: utf8.encode(_listNote)),
    ]);
    final note = result.notes.single;
    expect(note.type, NoteType.checklist);
    expect(note.content, 'Also grab snacks.');
    expect(note.checklistItems, hasLength(2));
    expect(note.checklistItems[1].isChecked, isTrue);
    expect(note.checklistItems[1].text, 'Milk');
    expect(note.color, 'YELLOW');
    expect(note.isPinned, isTrue);
  });

  test(
    'uses the edited time when created is missing, including numeric strings',
    () {
      final result = parser.parse([
        ImportedBytes(name: 'old.json', bytes: utf8.encode(_editedOnly)),
      ]);
      final note = result.notes.single;
      expect(note.createdAt, note.modifiedAt);
      expect(
        note.createdAt,
        DateTime.fromMicrosecondsSinceEpoch(1690000000000000, isUtc: true),
      );
      expect(note.attachments.single.fileName, 'shelf.png');
      expect(note.attachments.single.mimeType, 'image/png');
    },
  );

  test('keeps trashed notes and skips empty objects', () {
    final result = parser.parse([
      ImportedBytes(
        name: 'batch.json',
        bytes: utf8.encode('[$_trashed, {"color": "DEFAULT"}, $_textNote]'),
      ),
    ]);
    expect(result.notes, hasLength(2));
    expect(result.notes.where((note) => note.isTrashed), hasLength(1));
  });

  test('accepts string labels and a notes wrapper', () {
    final result = parser.parse([
      ImportedBytes(
        name: 'wrapped.json',
        bytes: utf8.encode(
          '{"notes":[{"title":"Wrapped","textContent":"Inside","labels":["alpha","alpha"]}]}',
        ),
      ),
    ]);
    final note = result.notes.single;
    expect(note.title, 'Wrapped');
    expect(note.tags, ['alpha']);
  });

  test('falls back to HTML text in a note and strips tags', () {
    final result = parser.parse([
      ImportedBytes(
        name: 'html-body.json',
        bytes: utf8.encode(
          '{"title":"Rich","textContentHtml":"<p>Hello<br>there</p>"}',
        ),
      ),
    ]);
    expect(result.notes.single.content, contains('Hello'));
    expect(result.notes.single.content, contains('there'));
    expect(result.notes.single.content, isNot(contains('<')));
  });

  test('reports a broken JSON file and still keeps its sibling', () {
    final result = parser.parse([
      const ImportedBytes(name: 'bad.json', bytes: [123]),
      ImportedBytes(name: 'good.json', bytes: utf8.encode(_textNote)),
    ]);
    expect(result.notes, hasLength(1));
    expect(result.warnings.single, contains('bad.json'));
  });

  test('a zip uses JSON and skips the HTML copy of the same note', () {
    final zip = _zip({
      'Takeout/Keep/Monday standup.json': _textNote,
      'Takeout/Keep/Monday standup.html': _htmlNote,
      'Takeout/archive_browser.html': '<html><title>browser</title></html>',
    });
    final result = parser.parse([
      ImportedBytes(name: 'takeout.zip', bytes: zip),
    ]);
    expect(result.notes, hasLength(1));
    expect(result.notes.single.title, 'Monday standup');
    expect(result.warnings.single, contains('HTML'));
  });

  test('a zip with only HTML still produces the note', () {
    final zip = _zip({'Takeout/Keep/Packing.html': _htmlNote});
    final result = parser.parse([
      ImportedBytes(name: 'takeout.zip', bytes: zip),
    ]);
    final note = result.notes.single;
    expect(note.title, 'Packing list');
    expect(note.type, NoteType.checklist);
    expect(note.checklistItems.map((item) => item.text), [
      'Passport',
      'Charger',
    ]);
    expect(note.checklistItems[1].isChecked, isTrue);
    expect(note.tags, ['travel']);
    expect(note.color, 'YELLOW');
    expect(note.isArchived, isTrue);
    expect(note.content, isEmpty);
  });

  test('standalone HTML is ignored when a JSON note was also picked', () {
    final result = parser.parse([
      ImportedBytes(name: 'note.json', bytes: utf8.encode(_textNote)),
      ImportedBytes(name: 'Packing.html', bytes: utf8.encode(_htmlNote)),
    ]);
    expect(result.notes, hasLength(1));
    expect(result.warnings.single, contains('HTML'));
  });

  test('a zip that is not a zip is a warning, not a crash', () {
    final result = parser.parse([
      const ImportedBytes(name: 'nope.zip', bytes: [1, 2, 3, 4]),
    ]);
    expect(result.notes, isEmpty);
    expect(result.fatal, isNotNull);
    expect(result.warnings.single, contains('zip'));
  });

  test('dedupes the same note picked twice', () {
    final bytes = utf8.encode(_textNote);
    final result = parser.parse([
      ImportedBytes(name: 'a.json', bytes: bytes),
      ImportedBytes(name: 'b.json', bytes: bytes),
    ]);
    expect(result.notes, hasLength(1));
  });

  test('sample export parses into the five demo notes', () {
    final result = parseKeepFiles(sampleKeepFiles());
    expect(result.fatal, isNull);
    expect(result.notes.map((note) => note.displayTitle), [
      'Grocery run',
      'Monday standup',
      'Kitchen sketch',
      'Train receipt',
      'Old draft',
    ]);
    expect(result.notes.last.isTrashed, isTrue);
    expect(result.notes[3].isArchived, isTrue);
  });

  test('an HTML-only zip still keeps a separate HTML note', () {
    final result = parser.parse([
      ImportedBytes(
        name: 'keep.zip',
        bytes: _zip({
          'Takeout/Keep/Packing.html': _htmlNote,
          'Takeout/Keep/photo.jpg': 'not-a-real-image',
          '__MACOSX/Takeout/._Packing.html': 'junk',
        }),
      ),
      ImportedBytes(
        name: 'Hotel.html',
        bytes: utf8.encode(
          '<html><body><div class="note"><h1>Hotel</h1><div class="content">Room 12</div></div></body></html>',
        ),
      ),
    ]);
    expect(result.fatal, isNull);
    expect(result.notes.map((note) => note.displayTitle).toSet(), {
      'Packing list',
      'Hotel',
    });
  });

  test('an untitled note borrows its first line', () {
    final result = parser.parse([
      ImportedBytes(
        name: 'blank.json',
        bytes: utf8.encode(
          '{"textContent":"Remember the keys\\nAnd the code."}',
        ),
      ),
    ]);
    expect(result.notes.single.title, isEmpty);
    expect(result.notes.single.displayTitle, 'Remember the keys');
  });
}

List<int> _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.add(ArchiveFile.string(name, content));
  });
  return ZipEncoder().encode(archive);
}

const _textNote = '''
{
  "color": "DEFAULT",
  "isTrashed": false,
  "isPinned": false,
  "isArchived": false,
  "title": "Monday standup",
  "textContent": "Ship the export preview.\\nAsk Priya about the Takeout zip.",
  "labels": [{"name": "work"}, {"name": "follow-up"}],
  "annotations": [{"url": "https://takeout.google.com", "title": "Google Takeout"}],
  "createdTimestampUsec": 1700000000000000,
  "userEditedTimestampUsec": 1700007200000000
}
''';

const _listNote = '''
{
  "color": "YELLOW",
  "isPinned": true,
  "isArchived": false,
  "isTrashed": false,
  "title": "Grocery run",
  "textContent": "Also grab snacks.",
  "listContent": [
    {"text": "Apples", "isChecked": false},
    {"text": "Milk", "isChecked": true}
  ]
}
''';

const _editedOnly = '''
{
  "color": "RED",
  "title": "Kitchen sketch",
  "textContent": "Move the shelf.",
  "attachments": [{"filePath": "photos/shelf.png", "mimetype": "image/png"}],
  "userEditedTimestampUsec": "1690000000000000"
}
''';

const _trashed = '''
{
  "isTrashed": true,
  "title": "Old draft",
  "textContent": "Gone"
}
''';

const _htmlNote = '''
<html>
<head><title>Ignored title</title></head>
<body>
<div class="note YELLOW archived">
<div class="heading">Packing list</div>
<div class="content">
<div class="list">
<div class="listitem"><span class="bullet">&#9744;</span><span class="text">Passport</span></div>
<div class="listitem checked"><span class="bullet">&#9745;</span><span class="text">Charger</span></div>
</div>
</div>
<div class="chips"><span class="chip label"><span class="label-name">travel</span></span></div>
</div>
</body>
</html>
''';
