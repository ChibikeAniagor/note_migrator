import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/data_import/import_screen.dart';
import 'features/data_mapping/preview_screen.dart';
import 'features/export/export_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/source_selection/source_screen.dart';
import 'features/target_selection/target_screen.dart';
import 'services/handoff/note_handoff.dart';
import 'state/migration_controller.dart';
import 'state/migration_state.dart';

class NoteMigratorApp extends ConsumerStatefulWidget {
  const NoteMigratorApp({super.key});

  @override
  ConsumerState<NoteMigratorApp> createState() => _NoteMigratorAppState();
}

class _NoteMigratorAppState extends ConsumerState<NoteMigratorApp>
    with WidgetsBindingObserver {
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullShare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pullShare();
    }
  }

  Future<void> _pullShare() async {
    if (_pulling) return;
    if (ref.read(migrationProvider).parsing) return;
    _pulling = true;
    try {
      final incoming = await NoteHandoff.takeIncoming();
      if (!mounted || incoming == null) return;
      await ref
          .read(migrationProvider.notifier)
          .importIncoming(
            incoming.files,
            sender: incoming.sender,
            error: incoming.error,
          );
    } finally {
      _pulling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(migrationProvider.select((state) => state.step));
    final canLeave =
        step == MigrationStep.onboarding || step == MigrationStep.source;
    final screen = switch (step) {
      MigrationStep.onboarding => const OnboardingScreen(),
      MigrationStep.source => const SourceScreen(),
      MigrationStep.import => const ImportScreen(),
      MigrationStep.preview => const PreviewScreen(),
      MigrationStep.target => const TargetScreen(),
      MigrationStep.export => const ExportScreen(),
    };

    return MaterialApp(
      title: 'Note Migrator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: PopScope(
        canPop: canLeave,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          ref.read(migrationProvider.notifier).back();
        },
        child: screen,
      ),
    );
  }
}
