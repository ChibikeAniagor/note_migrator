import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/keep_palette.dart';
import '../../core/widgets/wizard_scaffold.dart';
import '../../models/note.dart';
import '../../models/note_app.dart';
import '../../state/migration_controller.dart';
import '../../state/migration_state.dart';
import 'note_detail_sheet.dart';

class PreviewScreen extends ConsumerWidget {
  const PreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(migrationProvider);
    final visible = state.visibleNotes;
    final selectedVisible = visible
        .where((note) => state.selectedIds.contains(note.id))
        .length;
    final allVisibleSelected =
        visible.isNotEmpty && selectedVisible == visible.length;

    return WizardScaffold(
      onBack: () => ref.read(migrationProvider.notifier).back(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: WizardHeader(
              stepIndex: 2,
              title: 'Choose what to take',
              subtitle: state.source == NoteAppId.miNotes
                  ? 'Uncheck anything you want to leave in Mi Notes. Trashed notes stay off unless you select them.'
                  : 'Uncheck anything you want to leave in Keep. Trashed notes stay off unless you select them.',
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _SearchField(),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final filter in NoteFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_filterLabel(filter, state)),
                        selected: state.filter == filter,
                        onSelected: (_) => ref
                            .read(migrationProvider.notifier)
                            .setFilter(filter),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: visible.isEmpty
                        ? null
                        : () => ref
                              .read(migrationProvider.notifier)
                              .setVisibleSelected(!allVisibleSelected),
                    child: Text(allVisibleSelected ? 'Clear' : 'Select all'),
                  ),
                  const Spacer(),
                  if (state.trashedCount > 0 &&
                      state.filter != NoteFilter.trash)
                    TextButton(
                      onPressed: () => ref
                          .read(migrationProvider.notifier)
                          .setFilter(NoteFilter.trash),
                      child: Text('${state.trashedCount} in trash'),
                    ),
                ],
              ),
            ),
          ),
          if (state.importWarnings.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  state.importWarnings.join(' '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (state.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyNotes(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final note = visible[index];
                  return _NoteCard(
                    note: note,
                    selected: state.selectedIds.contains(note.id),
                    onToggle: () => ref
                        .read(migrationProvider.notifier)
                        .toggleNote(note.id),
                    onOpen: () => showNoteDetail(context, note.id),
                  );
                },
              ),
            ),
        ],
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${state.selectedNotes.length} of ${state.notes.length} selected',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FullWidthButton(
            label: 'Continue',
            onPressed: state.selectedNotes.isEmpty
                ? null
                : () => ref
                      .read(migrationProvider.notifier)
                      .continueFromPreview(),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(migrationProvider).search,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        hintText: 'Search titles, text, labels',
        prefixIcon: Icon(Icons.search),
        isDense: true,
      ),
      onChanged: ref.read(migrationProvider.notifier).setSearch,
    );
  }
}

String _filterLabel(NoteFilter filter, MigrationState state) {
  return switch (filter) {
    NoteFilter.all => 'All',
    NoteFilter.text => 'Text',
    NoteFilter.lists => 'Lists',
    NoteFilter.pinned => 'Pinned',
    NoteFilter.archived => 'Archived',
    NoteFilter.trash => 'Trash (${state.trashedCount})',
  };
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No notes match.',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });

  final UniversalNote note;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: keepSwatch(note.color), width: 6),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                semanticLabel: 'Include ${note.displayTitle}',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (note.isPinned)
                            Icon(
                              Icons.push_pin_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _snippet(note),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (note.type == NoteType.checklist)
                            const _MetaChip(label: 'List'),
                          for (final tag in note.tags.take(3))
                            _MetaChip(label: tag),
                          if (note.attachments.isNotEmpty)
                            const _MetaChip(label: 'Image left behind'),
                          if (note.isArchived)
                            const _MetaChip(label: 'Archived'),
                          if (note.isTrashed) const _MetaChip(label: 'Trash'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String _snippet(UniversalNote note) {
  if (note.checklistItems.isNotEmpty) {
    return note.checklistItems
        .take(3)
        .map((item) => '${item.isChecked ? '[x]' : '[ ]'} ${item.text}')
        .join('\n');
  }
  final text = note.content.trim();
  return text.isEmpty ? 'Empty note' : text;
}
