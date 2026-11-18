import '../../models/note.dart';
import '../../models/note_app.dart';

/// Bytes the user picked, or a sample baked into the app.
class ImportedBytes {
  const ImportedBytes({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// Notes read from one import, plus anything the user should know.
class ParseResult {
  const ParseResult({
    required this.notes,
    this.warnings = const [],
    this.fatal,
    this.detectedSource,
  });

  final List<UniversalNote> notes;
  final List<String> warnings;

  /// Set when nothing usable could be read. The import screen shows this.
  final String? fatal;

  /// Set when the file itself says where the notes came from.
  final NoteAppId? detectedSource;
}

/// Each note app gets a parser. Version 1 ships Keep and Mi Notes.
abstract class NoteParser {
  bool supports(String fileName);

  ParseResult parse(List<ImportedBytes> files);
}
