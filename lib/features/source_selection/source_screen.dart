import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/wizard_scaffold.dart';
import '../../models/note_app.dart';
import '../../state/migration_controller.dart';
import '../history/history_screen.dart';

class SourceScreen extends ConsumerWidget {
  const SourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyCount = ref.watch(
      migrationProvider.select((state) => state.history.length),
    );
    final source = ref.watch(migrationProvider.select((state) => state.source));
    return WizardScaffold(
      actions: [
        IconButton(
          tooltip: 'How this works',
          onPressed: () =>
              ref.read(migrationProvider.notifier).showOnboarding(),
          icon: const Icon(Icons.help_outline),
        ),
        IconButton(
          tooltip: 'Past exports',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            );
          },
          // The count is visual. Leaving it in the semantics tree replaces
          // the button name, so a reader only hears the number.
          icon: Badge(
            isLabelVisible: historyCount > 0,
            label: ExcludeSemantics(child: Text('$historyCount')),
            child: const Icon(Icons.history),
          ),
        ),
      ],
      body: ListView(
        children: [
          const WizardHeader(
            stepIndex: 0,
            title: 'Which way are the notes moving?',
            subtitle:
                'Pick a direction. Notes are read on this phone, then opened in the other app.',
          ),
          for (final app in const [NoteAppId.googleKeep, NoteAppId.miNotes])
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _AppTile(
                app: app,
                selected: source == app,
                onTap: () =>
                    ref.read(migrationProvider.notifier).selectSource(app),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _LaterLabel(),
          ),
          for (final app in const [
            NoteAppId.appleNotes,
            NoteAppId.notion,
            NoteAppId.evernote,
          ])
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _AppTile(app: app, selected: false),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Notes stay on this device.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottom: FullWidthButton(
        label: 'Continue',
        onPressed: () =>
            ref.read(migrationProvider.notifier).continueFromSource(),
      ),
    );
  }
}

class _LaterLabel extends StatelessWidget {
  const _LaterLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Later',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.selected, this.onTap});

  final NoteAppId app;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = app.available;
    final accent = app == NoteAppId.miNotes
        ? AppTheme.miOrange
        : const Color(0xFFFFF475);
    final iconColor = app == NoteAppId.miNotes
        ? Colors.white
        : const Color(0xFF1C1915);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled
                        ? accent
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    enabled
                        ? (app == NoteAppId.miNotes
                              ? Icons.notes_rounded
                              : Icons.sticky_note_2_outlined)
                        : Icons.lock_outline,
                    color: enabled ? iconColor : const Color(0xFF1C1915),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled ? _routeLine(app) : app.detail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _routeLine(NoteAppId app) {
  return switch (app) {
    NoteAppId.googleKeep => 'Open each note in Mi Notes',
    NoteAppId.miNotes => 'Open each note in Google Keep',
    _ => app.detail,
  };
}
