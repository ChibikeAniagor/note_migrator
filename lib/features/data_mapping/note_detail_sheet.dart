import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/keep_palette.dart';
import '../../models/note.dart';
import '../../services/exporters/mi_notes_text.dart';
import '../../state/migration_controller.dart';

Future<void> showNoteDetail(BuildContext context, String noteId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.86,
        child: NoteDetailSheet(noteId: noteId),
      );
    },
  );
}

class NoteDetailSheet extends ConsumerWidget {
  const NoteDetailSheet({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(
      migrationProvider.select((state) => _find(state.notes, noteId)),
    );
    final selected = ref.watch(
      migrationProvider.select((state) => state.selectedIds.contains(noteId)),
    );
    if (note == null) {
      return const Center(child: Text('This note is no longer in the import.'));
    }

    final theme = Theme.of(context);
    final rendered = renderMiNote(note);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: keepSwatch(note.color),
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  note.displayTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: selected,
            onChanged: (_) =>
                ref.read(migrationProvider.notifier).toggleNote(note.id),
            title: const Text('Include in export'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Expanded(
            child: ListView(
              children: [
                Text(
                  'What Mi Notes will get',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(rendered),
                if (note.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'The attachment file is not copied. Only its name is kept.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

UniversalNote? _find(List<UniversalNote> notes, String id) {
  for (final note in notes) {
    if (note.id == id) return note;
  }
  return null;
}
