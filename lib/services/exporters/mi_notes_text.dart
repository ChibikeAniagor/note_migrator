import '../../core/format.dart';
import '../../core/keep_palette.dart';
import '../../models/note.dart';
import '../../models/note_app.dart';

/// A conversion Mi Notes cannot represent as a real feature.
class ConversionWarning {
  const ConversionWarning({required this.title, required this.detail});

  final String title;
  final String detail;
}

/// Plain text for one note. Mi Notes has no bulk import, so this is the note.
String renderMiNote(UniversalNote note) {
  final buffer = StringBuffer()..writeln(note.displayTitle);
  final meta = <String>[];
  final color = keepColorName(note.color);
  if (color != null) meta.add('Color: $color');
  if (note.tags.isNotEmpty) meta.add('Labels: ${note.tags.join(', ')}');
  final status = <String>[
    if (note.isPinned) 'Pinned',
    if (note.isArchived) 'Archived',
    if (note.isTrashed) 'Trashed',
  ];
  if (status.isNotEmpty) meta.add('Status: ${status.join(', ')}');
  if (note.modifiedAt != null) {
    meta.add('Edited: ${formatNoteDate(note.modifiedAt!)}');
  } else if (note.createdAt != null) {
    meta.add('Created: ${formatNoteDate(note.createdAt!)}');
  }
  if (meta.isNotEmpty) {
    buffer.writeln();
    for (final line in meta) {
      buffer.writeln(line);
    }
  }

  final body = _bodyWithoutInferredTitle(note);
  if (body.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(body);
  }
  if (note.checklistItems.isNotEmpty) {
    buffer.writeln();
    for (final item in note.checklistItems) {
      buffer.writeln('${item.isChecked ? '[x]' : '[ ]'} ${item.text}');
    }
  }
  if (note.links.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Links:');
    for (final link in note.links) {
      buffer.writeln('- $link');
    }
  }
  if (note.attachments.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Attachments not included:');
    for (final attachment in note.attachments) {
      buffer.writeln('- ${attachment.fileName}');
    }
  }
  return buffer.toString().trimRight();
}

String _bodyWithoutInferredTitle(UniversalNote note) {
  final body = note.content.trim();
  if (note.title.trim().isNotEmpty || body.isEmpty) return body;
  if (body == note.displayTitle) return '';
  final firstBreak = body.indexOf('\n');
  final firstLine = firstBreak == -1 ? body : body.substring(0, firstBreak);
  if (firstLine.trim() != note.displayTitle) return body;
  return body.substring(firstLine.length).trim();
}

/// The card already shows [title]. Sharing still sends the full note.
String noteBody(String title, String text) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) return text;
  if (text.trim() == trimmedTitle) return '';
  final prefix = '$trimmedTitle\n';
  if (!text.startsWith(prefix)) return text;
  return text.substring(prefix.length).trimLeft();
}

/// What will change on the way into [target].
List<ConversionWarning> conversionWarnings(
  List<UniversalNote> notes, {
  NoteAppId target = NoteAppId.miNotes,
}) {
  final app = target.label;
  final filing = target == NoteAppId.googleKeep
      ? '$app will not file them as labels.'
      : '$app will not file them into folders.';
  final warnings = <ConversionWarning>[];
  final withAttachments = notes
      .where((note) => note.attachments.isNotEmpty)
      .length;
  if (withAttachments > 0) {
    warnings.add(
      ConversionWarning(
        title: 'Images stay behind',
        detail:
            '$withAttachments selected ${withAttachments == 1 ? 'note has' : 'notes have'} attachments. The file name is written into the note. The file itself is not copied.',
      ),
    );
  }
  final withColor = notes
      .where((note) => keepColorName(note.color) != null)
      .length;
  if (withColor > 0) {
    warnings.add(
      ConversionWarning(
        title: 'Colors become a line of text',
        detail:
            '$app will not color $withColor ${withColor == 1 ? 'note' : 'notes'}. The color name is written at the top.',
      ),
    );
  }
  final lists = notes.where((note) => note.checklistItems.isNotEmpty).length;
  if (lists > 0) {
    warnings.add(
      ConversionWarning(
        title: 'Checklists become text',
        detail:
            '$lists ${lists == 1 ? 'list becomes lines' : 'lists become lines'} starting with [ ] and [x]. They will not be $app checkboxes.',
      ),
    );
  }
  final labeled = notes.where((note) => note.tags.isNotEmpty).length;
  if (labeled > 0) {
    warnings.add(
      ConversionWarning(
        title: 'Labels become a line of text',
        detail:
            'Labels on $labeled ${labeled == 1 ? 'note are' : 'notes are'} written at the top. $filing',
      ),
    );
  }
  return warnings;
}
