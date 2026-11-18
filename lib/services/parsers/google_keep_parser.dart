import 'dart:convert';

import 'package:archive/archive.dart';

import '../../models/note.dart';
import 'keep_html.dart';
import 'note_parser.dart';

/// Parses a Google Keep Takeout export.
///
/// Takeout writes one JSON file per note (and usually an HTML copy). A note
/// looks like `{ "title", "textContent" | "listContent", "color", "labels",
/// "isPinned", "isArchived", "isTrashed", "createdTimestampUsec" }`.
/// Timestamps are microseconds. This parser prefers JSON and ignores the HTML
/// copies when JSON is present, so a note is not imported twice.
class GoogleKeepParser implements NoteParser {
  const GoogleKeepParser();

  @override
  bool supports(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.json') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  @override
  ParseResult parse(List<ImportedBytes> files) {
    final bucket = _Bucket();
    final htmlFiles = <ImportedBytes>[];
    var sawJsonNotes = false;

    for (final file in files) {
      final lower = file.name.toLowerCase();
      if (lower.endsWith('.zip')) {
        if (_parseZip(file, bucket)) sawJsonNotes = true;
      } else if (lower.endsWith('.json')) {
        final before = bucket.notes.length;
        _parseJsonBytes(file.bytes, file.name, bucket);
        if (bucket.notes.length > before) sawJsonNotes = true;
      } else if (lower.endsWith('.html') || lower.endsWith('.htm')) {
        htmlFiles.add(file);
      } else {
        bucket.warnings.add('${_baseName(file.name)} is not a Keep export.');
      }
    }

    if (sawJsonNotes && htmlFiles.isNotEmpty) {
      bucket.warnings.add(
        'Used the JSON notes and skipped ${htmlFiles.length} HTML ${htmlFiles.length == 1 ? 'file' : 'files'}.',
      );
    } else {
      for (final file in htmlFiles) {
        _parseHtmlBytes(file.bytes, file.name, bucket);
      }
    }

    final notes = _dedupe(bucket.notes);
    notes.sort(_compareNotes);
    if (notes.isEmpty) {
      return ParseResult(
        notes: const [],
        warnings: bucket.warnings,
        fatal: bucket.warnings.isEmpty
            ? 'No Google Keep notes were found. Export Keep from Google Takeout, then choose the zip or the .json files inside Takeout/Keep.'
            : bucket.warnings.join(' '),
      );
    }
    return ParseResult(notes: notes, warnings: bucket.warnings);
  }
}

/// Entry point for an isolate. Must stay a top-level function.
ParseResult parseKeepFiles(List<ImportedBytes> files) {
  try {
    return const GoogleKeepParser().parse(files);
  } catch (_) {
    return const ParseResult(
      notes: [],
      fatal: 'That export could not be read.',
    );
  }
}

class _Bucket {
  final notes = <UniversalNote>[];
  final warnings = <String>[];
  final ids = <String>{};
}

/// True when the zip contained JSON notes. HTML inside that zip is then
/// skipped. An HTML-only zip returns false so other HTML files still count.
bool _parseZip(ImportedBytes file, _Bucket bucket) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.bytes);
  } catch (_) {
    bucket.warnings.add(
      '${_baseName(file.name)} could not be opened as a zip.',
    );
    return false;
  }

  final jsonEntries = <ArchiveFile>[];
  final htmlEntries = <ArchiveFile>[];
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final base = name.split('/').last.toLowerCase();
    if (base.isEmpty || base.startsWith('.') || name.contains('__MACOSX')) {
      continue;
    }
    if (base.contains('archive_browser')) continue;
    if (base.endsWith('.json')) {
      jsonEntries.add(entry);
    } else if (base.endsWith('.html') || base.endsWith('.htm')) {
      htmlEntries.add(entry);
    }
  }

  if (jsonEntries.isEmpty && htmlEntries.isEmpty) {
    bucket.warnings.add('${_baseName(file.name)} does not contain Keep notes.');
    return false;
  }

  if (jsonEntries.isNotEmpty) {
    final before = bucket.notes.length;
    for (final entry in jsonEntries) {
      final bytes = entry.readBytes();
      if (bytes == null) continue;
      _parseJsonBytes(bytes, entry.name, bucket);
    }
    if (bucket.notes.length > before) {
      if (htmlEntries.isNotEmpty) {
        bucket.warnings.add(
          'Used the JSON notes and skipped ${htmlEntries.length} HTML ${htmlEntries.length == 1 ? 'copy' : 'copies'}.',
        );
      }
      return true;
    }
  }

  for (final entry in htmlEntries) {
    final bytes = entry.readBytes();
    if (bytes == null) continue;
    _parseHtmlBytes(bytes, entry.name, bucket);
  }
  return false;
}

void _parseJsonBytes(List<int> bytes, String fileName, _Bucket bucket) {
  final text = utf8
      .decode(bytes, allowMalformed: true)
      .replaceFirst('\uFEFF', '');
  final decoded = _decodeJson(text);
  if (decoded == null) {
    bucket.warnings.add('Could not read ${_baseName(fileName)}.');
    return;
  }
  _consumeJson(decoded, fileName, bucket);
}

void _parseHtmlBytes(List<int> bytes, String fileName, _Bucket bucket) {
  final base = _baseName(fileName).toLowerCase();
  if (base.contains('archive_browser')) return;
  final html = utf8.decode(bytes, allowMalformed: true);
  final note = parseKeepHtml(
    html: html,
    fileName: fileName,
    id: _makeId(fileName, 0, bucket.ids),
  );
  if (note != null) bucket.notes.add(note);
}

Object? _decodeJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

void _consumeJson(Object? decoded, String fileName, _Bucket bucket) {
  if (decoded is List) {
    for (var index = 0; index < decoded.length; index++) {
      final map = _asMap(decoded[index]);
      if (map == null) continue;
      final note = _noteFromKeepJson(
        map,
        fileName: fileName,
        index: index,
        ids: bucket.ids,
      );
      if (note != null) bucket.notes.add(note);
    }
    return;
  }

  final map = _asMap(decoded);
  if (map == null) {
    bucket.warnings.add('${_baseName(fileName)} is not a Keep note.');
    return;
  }
  if (!_looksLikeNote(map) && map['notes'] is List) {
    _consumeJson(map['notes'], fileName, bucket);
    return;
  }
  if (!_looksLikeNote(map)) return;
  final note = _noteFromKeepJson(
    map,
    fileName: fileName,
    index: 0,
    ids: bucket.ids,
  );
  if (note != null) bucket.notes.add(note);
}

bool _looksLikeNote(Map<String, dynamic> json) {
  return json.containsKey('textContent') ||
      json.containsKey('textContentHtml') ||
      json.containsKey('listContent') ||
      json.containsKey('title') ||
      json.containsKey('isTrashed') ||
      json.containsKey('isPinned') ||
      json.containsKey('attachments');
}

UniversalNote? _noteFromKeepJson(
  Map<String, dynamic> json, {
  required String fileName,
  required int index,
  required Set<String> ids,
}) {
  final checklist = _checklist(json['listContent']);
  var content = _asString(json['textContent']).replaceAll('\r\n', '\n').trim();
  if (content.isEmpty && json['textContentHtml'] is String) {
    content = _stripTags(json['textContentHtml'] as String);
  }
  final attachments = _attachments(json['attachments']);
  final title = _asString(json['title']).trim();
  if (title.isEmpty &&
      content.isEmpty &&
      checklist.isEmpty &&
      attachments.isEmpty) {
    return null;
  }

  final created = parseKeepTimestamp(json['createdTimestampUsec']);
  final edited = parseKeepTimestamp(json['userEditedTimestampUsec']);

  return UniversalNote(
    id: _makeId(fileName, index, ids),
    title: title,
    content: content,
    createdAt: created ?? edited,
    modifiedAt: edited ?? created,
    tags: _labels(json['labels']),
    color: _color(json['color']),
    isPinned: _asBool(json['isPinned']),
    isArchived: _asBool(json['isArchived']),
    isTrashed: _asBool(json['isTrashed']),
    attachments: attachments,
    type: checklist.isEmpty ? NoteType.text : NoteType.checklist,
    checklistItems: checklist,
    links: _links(json['annotations']),
    sourceFileName: fileName,
  );
}

/// Keep Takeout stores microseconds. Older files and hand-made JSON sometimes
/// use milliseconds, seconds, or a numeric string.
DateTime? parseKeepTimestamp(Object? value) {
  final number = switch (value) {
    final num n => n,
    final String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (number == null || number <= 0) return null;
  try {
    if (number > 100000000000000) {
      return DateTime.fromMicrosecondsSinceEpoch(number.round(), isUtc: true);
    }
    if (number > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(number.round(), isUtc: true);
    }
    if (number > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(
        (number * 1000).round(),
        isUtc: true,
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

List<ChecklistItem> _checklist(Object? value) {
  if (value is! List) return const [];
  final items = <ChecklistItem>[];
  for (final raw in value) {
    final map = _asMap(raw);
    if (map == null) continue;
    final text = _itemText(map);
    final checked = _asBool(map['isChecked'] ?? map['checked']);
    if (text.isEmpty && !checked) continue;
    items.add(ChecklistItem(text: text, isChecked: checked));
  }
  return items;
}

String _itemText(Map<String, dynamic> item) {
  final text = item['text'];
  if (text is String) return text.trim();
  if (text is Map && text['text'] is String) {
    return (text['text'] as String).trim();
  }
  if (item['textHtml'] is String) return _stripTags(item['textHtml'] as String);
  return '';
}

List<String> _labels(Object? value) {
  if (value is! List) return const [];
  final names = <String>[];
  for (final raw in value) {
    final name = switch (raw) {
      final String text => text.trim(),
      final Map map => _asString(map['name'] ?? map['label']).trim(),
      _ => '',
    };
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names;
}

List<AttachmentRef> _attachments(Object? value) {
  if (value is! List) return const [];
  final attachments = <AttachmentRef>[];
  for (final raw in value) {
    final map = _asMap(raw);
    if (map == null) continue;
    final path = _asString(map['filePath'] ?? map['fileName'] ?? map['name'])
        .trim();
    if (path.isEmpty) continue;
    final mime = map['mimetype'] ?? map['mimeType'];
    attachments.add(
      AttachmentRef(
        fileName: path.split(RegExp(r'[\\/]')).last,
        mimeType: mime is String && mime.trim().isNotEmpty ? mime.trim() : null,
      ),
    );
  }
  return attachments;
}

List<String> _links(Object? value) {
  if (value is! List) return const [];
  final links = <String>[];
  for (final raw in value) {
    final map = _asMap(raw);
    if (map == null) continue;
    final url = _asString(map['url']).trim();
    if (url.isNotEmpty && !links.contains(url)) links.add(url);
  }
  return links;
}

String? _color(Object? value) {
  if (value is! String) return null;
  final color = value.trim().toUpperCase();
  if (color.isEmpty ||
      color == 'DEFAULT' ||
      color == 'WHITE' ||
      color == 'NONE') {
    return null;
  }
  return color;
}

String _stripTags(String html) {
  final withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
  return withBreaks
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('\r\n', '\n')
      .trim();
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _asString(Object? value) => value is String ? value : '';

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return false;
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

List<UniversalNote> _dedupe(List<UniversalNote> notes) {
  final seen = <String>{};
  final unique = <UniversalNote>[];
  for (final note in notes) {
    final key = [
      note.title,
      note.createdAt?.toIso8601String() ?? '',
      note.content,
      for (final item in note.checklistItems) '${item.isChecked}:${item.text}',
    ].join('\u0001');
    if (seen.add(key)) unique.add(note);
  }
  return unique;
}

int _compareNotes(UniversalNote a, UniversalNote b) {
  int rank(UniversalNote note) {
    if (note.isTrashed) return 2;
    if (note.isPinned) return 0;
    return 1;
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  final aTime = a.modifiedAt ?? a.createdAt;
  final bTime = b.modifiedAt ?? b.createdAt;
  if (aTime != null && bTime != null) {
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) return byTime;
  } else if (aTime != null || bTime != null) {
    return aTime == null ? 1 : -1;
  }
  return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
}
