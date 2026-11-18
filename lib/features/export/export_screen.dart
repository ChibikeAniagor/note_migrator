import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share_sheet.dart';
import '../../core/widgets/wizard_scaffold.dart';
import '../../models/export_format.dart';
import '../../models/note_app.dart';
import '../../services/exporters/mi_notes_text.dart';
import '../../services/handoff/note_handoff.dart';
import '../../state/migration_controller.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen>
    with WidgetsBindingObserver {
  bool _awaitingReturn = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingReturn) return;
    _awaitingReturn = false;
    final payload = ref.read(migrationProvider).payload;
    final index = ref.read(migrationProvider).shareIndex;
    final count = payload?.notes.length ?? 0;
    if (!mounted || count == 0) return;
    if (index >= count - 1) {
      setState(() {
        _status = 'That was the last note. Save it in the other app if you have not yet.';
      });
      return;
    }
    ref.read(migrationProvider.notifier).setShareIndex(index + 1);
    setState(() => _status = 'Next note is ready.');
  }

  Future<void> _openInApp(NoteAppId target, String title, String fullText) async {
    final body = noteBody(title, fullText);
    final text = target == NoteAppId.googleKeep
        ? (body.isEmpty ? title : body)
        : fullText;
    final status = await NoteHandoff.openNote(
      target: target,
      title: title,
      text: text,
    );
    if (!mounted) return;
    switch (status) {
      case HandoffStatus.opened:
        await ref.read(migrationProvider.notifier).noteOpenedInTarget();
        if (!mounted) return;
        setState(() {
          _awaitingReturn = true;
          _status = 'Save it in ${target.label}, then come back for the next note.';
        });
      case HandoffStatus.missing:
        _snack(
          '${target.label} is not installed on this phone. Share the note and pick it there.',
        );
      case HandoffStatus.refused:
        _snack(
          '${target.label} is installed, but it did not accept the note. Share the note and pick it there.',
        );
      case HandoffStatus.failed:
        _snack('Could not open ${target.label}.');
      case HandoffStatus.unsupported:
        await shareNoteText(context, title: title, text: fullText);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final payload = ref.watch(
      migrationProvider.select((state) => state.payload),
    );
    final index = ref.watch(
      migrationProvider.select((state) => state.shareIndex),
    );
    final target = ref.watch(
      migrationProvider.select((state) => state.target),
    );
    if (payload == null || payload.notes.isEmpty) {
      return WizardScaffold(
        onBack: () => ref.read(migrationProvider.notifier).back(),
        body: const Center(
          child: Text('The export is missing. Go back and create it again.'),
        ),
      );
    }

    final safeIndex = index < 0 || index >= payload.notes.length ? 0 : index;
    final note = payload.notes[safeIndex];
    final fileLabel = switch (payload.format) {
      ExportFormat.perNoteZip => 'Share zip',
      ExportFormat.combinedText => 'Share text file',
      ExportFormat.jsonBackup => 'Share JSON backup',
    };
    final openLabel = target == NoteAppId.googleKeep
        ? 'Open in Keep'
        : 'Open in Mi Notes';

    return WizardScaffold(
      onBack: () => ref.read(migrationProvider.notifier).back(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          WizardHeader(
            stepIndex: 4,
            title: target == NoteAppId.googleKeep
                ? 'Open them in Keep'
                : 'Open them in Mi Notes',
            subtitle:
                'Each note opens in ${target.label}. Save it there, come back, and the next note is ready.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Instructions(format: payload.format, target: target),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _status!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _NoteQueue(
              index: safeIndex,
              count: payload.notes.length,
              title: note.title,
              text: note.text,
              onPrevious: safeIndex == 0
                  ? null
                  : () => ref
                        .read(migrationProvider.notifier)
                        .setShareIndex(safeIndex - 1),
              onNext: safeIndex >= payload.notes.length - 1
                  ? null
                  : () => ref
                        .read(migrationProvider.notifier)
                        .setShareIndex(safeIndex + 1),
              onCopy: () => copyText(context, note.text),
            ),
          ),
        ],
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FullWidthButton(
            label: openLabel,
            icon: Icons.open_in_new,
            onPressed: () => _openInApp(target, note.title, note.text),
          ),
          const SizedBox(height: 8),
          FullWidthButton(
            label: 'Share this note',
            icon: Icons.ios_share,
            outlined: true,
            onPressed: () =>
                shareNoteText(context, title: note.title, text: note.text),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => shareExportFile(context, payload),
                  child: Text(fileLabel),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () =>
                      ref.read(migrationProvider.notifier).startOver(),
                  child: const Text('Start over'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions({required this.format, required this.target});

  final ExportFormat format;
  final NoteAppId target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = switch (format) {
      ExportFormat.jsonBackup =>
        'The JSON file is a backup ${target.label} cannot open. Open each note in the app, or share it as text.',
      ExportFormat.perNoteZip =>
        'The zip keeps one text file per note if ${target.label} is not installed.',
      ExportFormat.combinedText =>
        'The text file holds every note, split by a line of dashes.',
    };
    return Text(
      extra,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _NoteQueue extends StatelessWidget {
  const _NoteQueue({
    required this.index,
    required this.count,
    required this.title,
    required this.text,
    required this.onPrevious,
    required this.onNext,
    required this.onCopy,
  });

  final int index;
  final int count;
  final String title;
  final String text;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Note ${index + 1} of $count',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Previous note',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next note',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(noteBody(title, text)),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onCopy,
                child: const Text('Copy note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
