import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/wizard_scaffold.dart';
import '../../models/note_app.dart';
import '../../services/parsers/note_parser.dart';
import '../../state/migration_controller.dart';

const _largeFileBytes = 40 * 1024 * 1024;

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsing = ref.watch(
      migrationProvider.select((state) => state.parsing),
    );
    final error = ref.watch(migrationProvider.select((state) => state.error));
    final loadedCount = ref.watch(
      migrationProvider.select((state) => state.notes.length),
    );
    final source = ref.watch(
      migrationProvider.select((state) => state.source),
    );
    final fromMi = source == NoteAppId.miNotes;

    return Stack(
      children: [
        WizardScaffold(
          onBack: parsing
              ? null
              : () => ref.read(migrationProvider.notifier).back(),
          body: ListView(
            children: [
              WizardHeader(
                stepIndex: 1,
                title: fromMi ? 'Bring notes out of Mi Notes' : 'Bring notes out of Keep',
                subtitle: fromMi
                    ? 'Share a note from Mi Notes into Note Migrator, or open a text or JSON file you saved.'
                    : 'Share a note from Keep into Note Migrator, or open a Takeout zip for the whole account.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Steps(fromMi: fromMi),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ErrorBanner(message: error),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FullWidthButton(
                label: fromMi ? 'Choose a saved file' : 'Choose Takeout file',
                icon: Icons.folder_open_outlined,
                onPressed: parsing
                    ? null
                    : () => _pick(context, ref, fromMi: fromMi),
              ),
              if (loadedCount > 0) ...[
                const SizedBox(height: 8),
                FullWidthButton(
                  label: 'Review $loadedCount notes',
                  outlined: true,
                  onPressed: parsing
                      ? null
                      : () => ref
                            .read(migrationProvider.notifier)
                            .returnToPreview(),
                ),
              ],
              TextButton(
                onPressed: parsing
                    ? null
                    : () => ref.read(migrationProvider.notifier).loadSample(),
                child: const Text('Preview with sample notes'),
              ),
            ],
          ),
        ),
        if (parsing) const _ReadingOverlay(),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required bool fromMi,
  }) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: fromMi
            ? const ['txt', 'json', 'zip', 'md']
            : const ['zip', 'json', 'html', 'htm'],
      );
    } on PlatformException {
      if (context.mounted) {
        _snack(context, 'The file picker could not be opened.');
      }
      return;
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'The file picker could not be opened.');
      }
      return;
    }
    if (picked.isEmpty) return;

    final files = <ImportedBytes>[];
    for (final file in picked) {
      final bytes = await _bytesOf(file);
      if (bytes == null) continue;
      files.add(ImportedBytes(name: file.name, bytes: bytes));
    }
    if (files.isEmpty) {
      if (context.mounted) {
        _snack(context, 'That file could not be read.');
      }
      return;
    }

    final large = files.where((file) => file.bytes.length > _largeFileBytes);
    if (large.isNotEmpty && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('This export is large'),
          content: const Text(
            'Files over 40 MB usually include photos. Photos are not copied. Reading the zip can take a moment and use a lot of memory. You can also unzip it and pick only the .json files in Takeout/Keep.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Read it'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }
    if (!context.mounted) return;
    await ref.read(migrationProvider.notifier).importFiles(files);
  }
}

Future<List<int>?> _bytesOf(PlatformFile file) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isNotEmpty) return bytes;
  } catch (_) {}
  return _readPath(file.path);
}

Future<List<int>?> _readPath(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Steps extends StatelessWidget {
  const _Steps({required this.fromMi});

  final bool fromMi;

  List<String> get _items => fromMi
      ? const [
          'Open the note in Mi Notes.',
          'Tap Share and choose Note Migrator.',
          'Repeat for each note you want to move.',
          'Or choose a text or JSON file you already saved.',
        ]
      : const [
          'Open a Keep note, tap Share, and choose Note Migrator.',
          'For every note, open takeout.google.com and sign in.',
          'Deselect everything, then select only Google Keep.',
          'Download the zip and choose it here.',
        ];

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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_items[i])),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              fromMi
                  ? 'Mi Notes has no bulk export. Sharing a note, or opening a file you saved, is how the notes get here. Nothing is uploaded.'
                  : 'This app does not sign in to Google. A shared note or the Takeout file is read on this device. HTML copies are ignored when JSON notes are present.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingOverlay extends StatelessWidget {
  const _ReadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x66000000),
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 14),
                Text('Reading notes'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
