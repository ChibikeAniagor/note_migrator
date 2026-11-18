enum NoteType { text, checklist }

/// One checkbox row from a Keep list note.
class ChecklistItem {
  const ChecklistItem({required this.text, required this.isChecked});

  final String text;
  final bool isChecked;
}

/// A file Keep attached to a note. Version 1 records the name and does not
/// copy the bytes.
class AttachmentRef {
  const AttachmentRef({required this.fileName, this.mimeType});

  final String fileName;
  final String? mimeType;
}

/// Note shape shared by every parser and exporter.
class UniversalNote {
  const UniversalNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    required this.tags,
    required this.color,
    required this.isPinned,
    required this.isArchived,
    required this.isTrashed,
    required this.attachments,
    required this.type,
    required this.checklistItems,
    required this.links,
    required this.sourceFileName,
  });

  final String id;
  final String title;
  final String content;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final List<String> tags;

  /// Keep color name such as `YELLOW`. Null when the note uses the default.
  final String? color;
  final bool isPinned;
  final bool isArchived;
  final bool isTrashed;
  final List<AttachmentRef> attachments;
  final NoteType type;
  final List<ChecklistItem> checklistItems;
  final List<String> links;
  final String sourceFileName;

  UniversalNote withId(String nextId) {
    return UniversalNote(
      id: nextId,
      title: title,
      content: content,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      tags: tags,
      color: color,
      isPinned: isPinned,
      isArchived: isArchived,
      isTrashed: isTrashed,
      attachments: attachments,
      type: type,
      checklistItems: checklistItems,
      links: links,
      sourceFileName: sourceFileName,
    );
  }

  /// Title shown in the app and written into the exported text.
  ///
  /// Keep allows an empty title. Fall back to the first line of the note so
  /// the export still has something to file it under.
  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final line = _firstContentLine(content);
    if (line.isNotEmpty) return line;
    for (final item in checklistItems) {
      final text = item.text.trim();
      if (text.isNotEmpty) return text;
    }
    return 'Untitled note';
  }

  Map<String, Object?> toExportJson() {
    return {
      'id': id,
      'title': displayTitle,
      'content': content,
      'createdAt': createdAt?.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
      'tags': tags,
      'color': color,
      'isPinned': isPinned,
      'isArchived': isArchived,
      'isTrashed': isTrashed,
      'type': type.name,
      'checklist': [
        for (final item in checklistItems)
          {'text': item.text, 'checked': item.isChecked},
      ],
      'attachments': [
        for (final attachment in attachments)
          {'fileName': attachment.fileName, 'mimeType': attachment.mimeType},
      ],
      'links': links,
      'sourceFileName': sourceFileName,
    };
  }
}

String _firstContentLine(String content) {
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}
