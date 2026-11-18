import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/format.dart';
import '../../models/export_format.dart';
import '../../models/note.dart';
import '../../models/note_app.dart';
import 'mi_notes_text.dart';

class ExportException implements Exception {
  ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes the selected notes in a form a person can carry into Mi Notes.
class MiNotesExporter {
  const MiNotesExporter();

  ExportPayload export(
    List<UniversalNote> notes,
    ExportFormat format, {
    DateTime? now,
    NoteAppId source = NoteAppId.googleKeep,
    NoteAppId target = NoteAppId.miNotes,
  }) {
    if (notes.isEmpty) {
      throw ExportException('Select at least one note.');
    }
    final clock = now ?? DateTime.now();
    final shareable = [
      for (final note in notes)
        ShareableNote(title: note.displayTitle, text: renderMiNote(note)),
    ];
    final stamp = formatFileStamp(clock);
    final prefix = target == NoteAppId.googleKeep ? 'keep-notes' : 'mi-notes';
    return switch (format) {
      ExportFormat.perNoteZip => ExportPayload(
        fileName: '$prefix-$stamp.zip',
        bytes: _zip(shareable),
        mimeType: 'application/zip',
        notes: shareable,
        format: format,
      ),
      ExportFormat.combinedText => ExportPayload(
        fileName: '$prefix-$stamp.txt',
        bytes: Uint8List.fromList(
          utf8.encode(_combined(shareable, clock, source, target)),
        ),
        mimeType: 'text/plain',
        notes: shareable,
        format: format,
      ),
      ExportFormat.jsonBackup => ExportPayload(
        fileName: '$prefix-$stamp.json',
        bytes: Uint8List.fromList(
          utf8.encode(_json(notes, clock, source, target)),
        ),
        mimeType: 'application/json',
        notes: shareable,
        format: format,
      ),
    };
  }
}

Uint8List _zip(List<ShareableNote> notes) {
  final archive = Archive();
  final used = <String>{};
  for (final note in notes) {
    final name = uniqueNoteFileName(note.title, used);
    archive.add(ArchiveFile.string(name, '${note.text}\n'));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// File name safe on Android and Windows. [used] is compared case-insensitively.
String uniqueNoteFileName(String title, Set<String> used) {
  var base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.isEmpty || base == '.' || base == '..') base = 'Untitled note';
  if (base.length > 60) base = base.substring(0, 60).trim();
  var name = '$base.txt';
  var suffix = 2;
  while (!used.add(name.toLowerCase())) {
    name = '$base-$suffix.txt';
    suffix++;
  }
  return name;
}

String _combined(
  List<ShareableNote> notes,
  DateTime now,
  NoteAppId source,
  NoteAppId target,
) {
  final buffer = StringBuffer()
    ..writeln('${source.label} notes prepared for ${target.label}')
    ..writeln('Exported ${formatNoteDate(now)}')
    ..writeln('${notes.length} ${notes.length == 1 ? 'note' : 'notes'}');
  for (final note in notes) {
    buffer
      ..writeln()
      ..writeln('----------')
      ..writeln()
      ..writeln(note.text);
  }
  buffer.writeln();
  return buffer.toString();
}

String _json(
  List<UniversalNote> notes,
  DateTime now,
  NoteAppId source,
  NoteAppId target,
) {
  final payload = {
    'format': 'note-migrator/v1',
    'source': source == NoteAppId.miNotes ? 'mi_notes' : 'google_keep',
    'target': target == NoteAppId.googleKeep ? 'google_keep' : 'mi_notes',
    'exportedAt': now.toUtc().toIso8601String(),
    'notes': [for (final note in notes) note.toExportJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
