import 'dart:convert';

import 'package:archive/archive.dart';

import '../../core/keep_palette.dart';
import '../../models/note.dart';
import '../../models/note_app.dart';
import 'note_parser.dart';

/// Reads notes a person saved out of Mi Notes, or a backup this app wrote.
///
/// Accepts plain text, a combined file split by a line of dashes, a zip of
/// those files, a `note-migrator/v1` JSON backup, and a JSON list shaped like
/// a Mi Notes cloud export (`subject`, `snippet`, `createDate`).
class MiNotesParser implements NoteParser {
  const MiNotesParser();

  @override
  bool supports(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.json') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.text');
  }

  @override
  ParseResult parse(List<ImportedBytes> files) {
    final draft = _Draft();
    for (final file in files) {
      final lower = file.name.toLowerCase();
      if (lower.endsWith('.zip')) {
        _parseZip(file, draft);
      } else if (_isTextName(lower) || lower.endsWith('.json')) {
        _parseBytes(file.bytes, file.name, draft);
      } else {
        draft.warnings.add('${_baseName(file.name)} is not a note file.');
      }
    }
    if (draft.notes.isEmpty) {
      return ParseResult(
        notes: const [],
        warnings: draft.warnings,
        fatal: draft.warnings.isEmpty
            ? 'No notes were found. Share a note from Mi Notes, or choose a text or JSON file you saved.'
            : draft.warnings.join(' '),
        detectedSource: draft.detectedSource,
      );
    }
    return ParseResult(
      notes: draft.notes,
      warnings: draft.warnings,
      detectedSource: draft.detectedSource,
    );
  }
}

/// Entry point for an isolate. Must stay a top-level function.
ParseResult parseMiNotesFiles(List<ImportedBytes> files) {
  try {
    return const MiNotesParser().parse(files);
  } catch (_) {
    return const ParseResult(
      notes: [],
      fatal: 'That file could not be read.',
    );
  }
}

/// Two short notes so the Mi Notes path can be tried without a phone export.
List<ImportedBytes> sampleMiNotesFiles() {
  return [
    ImportedBytes(
      name: 'sample-mi-notes.txt',
      bytes: utf8.encode('''
Market run

[ ] Eggs
[x] Bread

----------

Train idea

Write down the platform number before the doors close.
'''),
    ),
  ];
}

class _Draft {
  final notes = <UniversalNote>[];
  final warnings = <String>[];
  final ids = <String>{};
  NoteAppId? detectedSource;
}

bool _isTextName(String lower) {
  return lower.endsWith('.txt') ||
      lower.endsWith('.md') ||
      lower.endsWith('.text');
}

void _parseZip(ImportedBytes file, _Draft draft) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.bytes);
  } catch (_) {
    draft.warnings.add('${_baseName(file.name)} could not be opened as a zip.');
    return;
  }
  var found = false;
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final base = _baseName(name);
    if (base.startsWith('.') || name.contains('__MACOSX')) continue;
    final lower = base.toLowerCase();
    if (!_isTextName(lower) && !lower.endsWith('.json')) continue;
    final bytes = entry.readBytes();
    if (bytes == null) continue;
    final before = draft.notes.length;
    _parseBytes(bytes, base, draft);
    if (draft.notes.length > before) found = true;
  }
  if (!found) {
    draft.warnings.add('${_baseName(file.name)} does not contain note files.');
  }
}

void _parseBytes(List<int> bytes, String fileName, _Draft draft) {
  final text = _decode(bytes).trim();
  if (text.isEmpty) {
    draft.warnings.add('${_baseName(fileName)} is empty.');
    return;
  }
  if (_looksLikeJson(text)) {
    try {
      final decoded = jsonDecode(text);
      if (_consumeJson(decoded, fileName, draft)) return;
    } catch (_) {
      // A text note can start with "{" without being JSON.
    }
  }
  final parts = _splitCombined(text);
  if (parts.isEmpty) {
    draft.warnings.add('${_baseName(fileName)} did not contain a note.');
    return;
  }
  for (var index = 0; index < parts.length; index++) {
    final note = _noteFromText(parts[index], fileName, index, draft.ids);
    if (note != null) draft.notes.add(note);
  }
}

bool _looksLikeJson(String text) {
  final start = text.trimLeft();
  return start.startsWith('{') || start.startsWith('[');
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// True when [value] was a note document. False when it should be read as text.
bool _consumeJson(Object? value, String fileName, _Draft draft) {
  if (value is List) {
    final notes = _maps(value);
    if (notes.isEmpty || !_looksLikeNoteList(notes)) return false;
    final before = draft.notes.length;
    for (var index = 0; index < notes.length; index++) {
      _addLooseNote(notes[index], fileName, index, draft);
    }
    return draft.notes.length > before;
  }
  if (value is! Map) return false;
  if (value['format'] == 'note-migrator/v1') {
    draft.detectedSource = switch (value['source']) {
      'mi_notes' => NoteAppId.miNotes,
      'google_keep' => NoteAppId.googleKeep,
      _ => draft.detectedSource,
    };
    final notes = value['notes'];
    if (notes is! List) return true;
    for (var index = 0; index < notes.length; index++) {
      final item = notes[index];
      if (item is Map) {
        _addExportNote(item, fileName, index, draft);
      }
    }
    return true;
  }
  for (final key in ['notes', 'records', 'data', 'items']) {
    final nested = value[key];
    if (nested is List && _consumeJson(nested, fileName, draft)) return true;
    if (nested is Map && _consumeJson(nested, fileName, draft)) return true;
  }
  if (_looksLikeNoteMap(value)) {
    _addLooseNote(value, fileName, 0, draft);
    return true;
  }
  return false;
}

bool _looksLikeNoteList(List<Map<dynamic, dynamic>> notes) {
  return notes.any(_looksLikeNoteMap);
}

bool _looksLikeNoteMap(Map<dynamic, dynamic> map) {
  return map.containsKey('subject') ||
      map.containsKey('snippet') ||
      map.containsKey('content') ||
      map.containsKey('title') ||
      map.containsKey('textContent');
}

List<Map<dynamic, dynamic>> _maps(List<Object?> value) {
  return [
    for (final item in value)
      if (item is Map) item,
  ];
}

void _addExportNote(
  Map<dynamic, dynamic> json,
  String fileName,
  int index,
  _Draft draft,
) {
  final title = _string(json['title']);
  final content = _string(json['content']);
  final checklist = _checklist(json['checklist']);
  if (title.isEmpty && content.isEmpty && checklist.isEmpty) return;
  final tags = [
    for (final tag in _asList(json['tags']))
      if (tag is String && tag.trim().isNotEmpty) tag.trim(),
  ];
  final links = [
    for (final link in _asList(json['links']))
      if (link is String && link.trim().isNotEmpty) link.trim(),
  ];
  final attachments = <AttachmentRef>[
    for (final item in _asList(json['attachments']))
      if (item is Map && _string(item['fileName']).isNotEmpty)
        AttachmentRef(
          fileName: _string(item['fileName']),
          mimeType: _nullableString(item['mimeType']),
        ),
  ];
  draft.notes.add(
    UniversalNote(
      id: _makeId(_string(json['id']).isEmpty ? fileName : _string(json['id']), index, draft.ids),
      title: title,
      content: content,
      createdAt: _date(json['createdAt']),
      modifiedAt: _date(json['modifiedAt']),
      tags: tags,
      color: _nullableString(json['color']),
      isPinned: json['isPinned'] == true,
      isArchived: json['isArchived'] == true,
      isTrashed: json['isTrashed'] == true,
      attachments: attachments,
      type: json['type'] == 'checklist' || checklist.isNotEmpty
          ? NoteType.checklist
          : NoteType.text,
      checklistItems: checklist,
      links: links,
      sourceFileName: _baseName(fileName),
    ),
  );
}

void _addLooseNote(
  Map<dynamic, dynamic> json,
  String fileName,
  int index,
  _Draft draft,
) {
  final title = _firstString(json, ['subject', 'title']);
  final rawBody = _firstString(json, ['snippet', 'content', 'textContent', 'extraInfo']);
  final body = _stripTags(rawBody).trim();
  if (title.isEmpty && body.isEmpty) return;
  final pinned = _loosePinned(json);
  draft.notes.add(
    UniversalNote(
      id: _makeId(fileName, index, draft.ids),
      title: title,
      content: body,
      createdAt: _date(json['createDate'] ?? json['createdAt']),
      modifiedAt: _date(json['modifyDate'] ?? json['modifiedAt']),
      tags: _looseTags(json),
      color: null,
      isPinned: pinned,
      isArchived: false,
      isTrashed: json['status'] == 'deleted',
      attachments: const [],
      type: NoteType.text,
      checklistItems: const [],
      links: const [],
      sourceFileName: _baseName(fileName),
    ),
  );
}

List<String> _looseTags(Map<dynamic, dynamic> json) {
  final folder = _firstString(json, ['folderName', 'label']);
  if (folder.isEmpty) return const [];
  return [folder];
}

bool _loosePinned(Map<dynamic, dynamic> json) {
  if (json['pinned'] == true || json['isPinned'] == true) return true;
  final setting = json['setting'];
  if (setting is String) {
    return setting.contains('"pinned":true') || setting.contains('"stick":1');
  }
  if (setting is Map) {
    return setting['pinned'] == true || setting['stick'] == 1;
  }
  return false;
}

UniversalNote? _noteFromText(
  String raw,
  String fileName,
  int index,
  Set<String> ids,
) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var cursor = 0;
  while (cursor < lines.length && lines[cursor].trim().isEmpty) {
    cursor++;
  }
  if (cursor >= lines.length) return null;
  final title = lines[cursor].trim();
  cursor++;
  while (cursor < lines.length && lines[cursor].trim().isEmpty) {
    cursor++;
  }

  String? color;
  final tags = <String>[];
  var pinned = false;
  var archived = false;
  var trashed = false;
  final links = <String>[];
  final attachments = <AttachmentRef>[];
  final checklist = <ChecklistItem>[];
  final body = <String>[];

  var section = _Section.body;
  var header = true;
  for (var i = cursor; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (header) {
      if (trimmed.isEmpty) {
        header = false;
        continue;
      }
      final headerLine = _readHeader(trimmed);
      if (headerLine != null) {
        if (headerLine.color != null) color = headerLine.color;
        tags.addAll(headerLine.tags);
        pinned = pinned || headerLine.pinned;
        archived = archived || headerLine.archived;
        trashed = trashed || headerLine.trashed;
        continue;
      }
      header = false;
    }
    if (trimmed == 'Links:') {
      section = _Section.links;
      continue;
    }
    if (trimmed == 'Attachments not included:') {
      section = _Section.attachments;
      continue;
    }
    if (trimmed.isEmpty) {
      if (section == _Section.body) body.add('');
      continue;
    }
    if (section == _Section.links && trimmed.startsWith('- ')) {
      links.add(trimmed.substring(2).trim());
      continue;
    }
    if (section == _Section.attachments && trimmed.startsWith('- ')) {
      final name = trimmed.substring(2).trim();
      if (name.isNotEmpty) {
        attachments.add(AttachmentRef(fileName: name));
      }
      continue;
    }
    section = _Section.body;
    final box = _checkbox.firstMatch(trimmed);
    if (box != null) {
      final mark = box.group(1) ?? ' ';
      checklist.add(
        ChecklistItem(
          text: box.group(2) ?? '',
          isChecked: mark.toLowerCase() == 'x',
        ),
      );
      continue;
    }
    body.add(line.trimRight());
  }

  final content = body.join('\n').trim();
  if (title.isEmpty && content.isEmpty && checklist.isEmpty) return null;
  return UniversalNote(
    id: _makeId(fileName, index, ids),
    title: title,
    content: content,
    createdAt: null,
    modifiedAt: null,
    tags: tags,
    color: color,
    isPinned: pinned,
    isArchived: archived,
    isTrashed: trashed,
    attachments: attachments,
    type: checklist.isEmpty ? NoteType.text : NoteType.checklist,
    checklistItems: checklist,
    links: links,
    sourceFileName: _baseName(fileName),
  );
}

enum _Section { body, links, attachments }

final _checkbox = RegExp(r'^\[([ xX])\]\s?(.*)$');

class _Header {
  const _Header({
    this.color,
    this.tags = const [],
    this.pinned = false,
    this.archived = false,
    this.trashed = false,
  });

  final String? color;
  final List<String> tags;
  final bool pinned;
  final bool archived;
  final bool trashed;
}

_Header? _readHeader(String trimmed) {
  if (trimmed.startsWith('Color:')) {
    final value = trimmed.substring(trimmed.indexOf(':') + 1).trim();
    if (!isKnownKeepColor(value)) return const _Header();
    return _Header(color: value.toUpperCase());
  }
  if (trimmed.startsWith('Labels:')) {
    return _Header(
      tags: _splitList(trimmed.substring(trimmed.indexOf(':') + 1)),
    );
  }
  if (trimmed.startsWith('Status:')) {
    final status = trimmed.substring(trimmed.indexOf(':') + 1).toLowerCase();
    return _Header(
      pinned: status.contains('pinned'),
      archived: status.contains('archived'),
      trashed: status.contains('trashed'),
    );
  }
  if (trimmed.startsWith('Edited:') || trimmed.startsWith('Created:')) {
    return const _Header();
  }
  return null;
}

List<String> _splitList(String value) {
  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

List<ChecklistItem> _checklist(Object? value) {
  final items = <ChecklistItem>[];
  for (final item in _asList(value)) {
    if (item is! Map) continue;
    final text = _string(item['text']);
    if (text.isEmpty) continue;
    items.add(ChecklistItem(text: text, isChecked: item['checked'] == true));
  }
  return items;
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

String _string(Object? value) {
  if (value is String) return value;
  return '';
}

String? _nullableString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

String _firstString(Map<dynamic, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

DateTime? _date(Object? value) {
  if (value is int) return _fromEpoch(value);
  if (value is num) return _fromEpoch(value.round());
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    final asInt = int.tryParse(value);
    if (asInt != null) return _fromEpoch(asInt);
  }
  return null;
}

DateTime? _fromEpoch(int value) {
  if (value <= 0) return null;
  final digits = value.abs().toString().length;
  if (digits >= 16) {
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }
  if (digits >= 13) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

String _stripTags(String value) {
  if (!value.contains('<')) return value;
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

List<String> _splitCombined(String text) {
  final lines = text.split('\n');
  final chunks = <StringBuffer>[StringBuffer()];
  for (final line in lines) {
    if (RegExp(r'^-{10,}\s*$').hasMatch(line.trim())) {
      chunks.add(StringBuffer());
    } else {
      chunks.last.writeln(line);
    }
  }
  final parts = [
    for (final chunk in chunks)
      if (chunk.toString().trim().isNotEmpty) chunk.toString().trim(),
  ];
  if (parts.isEmpty) return const [];
  final first = parts.first;
  if (first.contains('prepared for') && first.contains('Exported')) {
    return parts.skip(1).toList();
  }
  return parts;
}

String _makeId(String fileName, int index, Set<String> used) {
  var id = '$fileName#$index';
  var suffix = 2;
  while (!used.add(id)) {
    id = '$fileName#$index#$suffix';
    suffix++;
  }
  return id;
}

String _baseName(String fileName) {
  final normalized = fileName.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? fileName : parts.last;
}
