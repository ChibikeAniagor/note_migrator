import 'dart:typed_data';

/// How the selected notes leave the app.
enum ExportFormat {
  perNoteZip(
    'One file per note',
    'A zip of plain text files. Use this when the other app is not on this phone.',
  ),
  combinedText(
    'One combined file',
    'Every selected note in a single text file, split by a divider.',
  ),
  jsonBackup(
    'JSON backup',
    'A structured copy Note Migrator can open again. Keep and Mi Notes cannot import this file by themselves.',
  );

  const ExportFormat(this.label, this.description);

  final String label;
  final String description;
}

/// One note reduced to the text a person can paste into Mi Notes.
class ShareableNote {
  const ShareableNote({required this.title, required this.text});

  final String title;
  final String text;
}

/// The file the exporter produced, plus the per-note text used by the share queue.
class ExportPayload {
  const ExportPayload({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
    required this.notes,
    required this.format,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  final List<ShareableNote> notes;
  final ExportFormat format;
}
