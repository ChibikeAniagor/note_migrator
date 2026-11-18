import 'dart:convert';

import 'note_parser.dart';

/// A small Takeout-shaped export so the flow can be tried before a real one.
List<ImportedBytes> sampleKeepFiles() {
  return [
    ImportedBytes(name: 'grocery.json', bytes: utf8.encode(_grocery)),
    ImportedBytes(name: 'meeting.json', bytes: utf8.encode(_meeting)),
    ImportedBytes(name: 'sketch.json', bytes: utf8.encode(_sketch)),
    ImportedBytes(name: 'receipt.json', bytes: utf8.encode(_receipt)),
    ImportedBytes(name: 'deleted.json', bytes: utf8.encode(_deleted)),
  ];
}

const _grocery = '''
{
  "color": "YELLOW",
  "isTrashed": false,
  "isPinned": true,
  "isArchived": false,
  "title": "Grocery run",
  "listContent": [
    {"text": "Milk", "isChecked": false},
    {"text": "Eggs", "isChecked": true},
    {"text": "Rice", "isChecked": false}
  ],
  "labels": [{"name": "home"}],
  "createdTimestampUsec": 1710000000000000,
  "userEditedTimestampUsec": 1710003600000000
}
''';

const _meeting = '''
{
  "color": "DEFAULT",
  "isTrashed": false,
  "isPinned": false,
  "isArchived": false,
  "title": "Monday standup",
  "textContent": "Ship the export preview.\\nAsk Priya about the Takeout zip.",
  "labels": [{"name": "work"}, {"name": "follow-up"}],
  "annotations": [
    {
      "description": "Takeout",
      "source": "WEBLINK",
      "title": "Google Takeout",
      "url": "https://takeout.google.com"
    }
  ],
  "createdTimestampUsec": 1700000000000000,
  "userEditedTimestampUsec": 1700007200000000
}
''';

const _sketch = '''
{
  "color": "RED",
  "isTrashed": false,
  "isPinned": false,
  "isArchived": false,
  "title": "Kitchen sketch",
  "textContent": "Move the shelf up. Keep the warm light.",
  "attachments": [
    {"filePath": "shelf.png", "mimetype": "image/png"}
  ],
  "userEditedTimestampUsec": "1690000000000000"
}
''';

const _receipt = '''
{
  "color": "DEFAULT",
  "isTrashed": false,
  "isPinned": false,
  "isArchived": true,
  "title": "Train receipt",
  "textContent": "Paid 420 for the Friday ticket.",
  "createdTimestampUsec": 1600000000000000,
  "userEditedTimestampUsec": 1600000000000000
}
''';

const _deleted = '''
{
  "color": "DEFAULT",
  "isTrashed": true,
  "isPinned": false,
  "isArchived": false,
  "title": "Old draft",
  "textContent": "Throwaway line that was deleted in Keep.",
  "userEditedTimestampUsec": 1500000000000000
}
''';
