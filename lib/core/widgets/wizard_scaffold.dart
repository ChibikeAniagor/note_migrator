import 'package:flutter/material.dart';

/// Shared frame for the five migration steps.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.body,
    this.bottom,
    this.onBack,
    this.actions = const [],
  });

  static const labels = ['Source', 'Import', 'Review', 'Target', 'Export'];

  final Widget body;
  final Widget? bottom;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
        title: const Text('Note Migrator'),
        actions: actions,
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (bottom != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: bottom!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WizardHeader extends StatelessWidget {
  const WizardHeader({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.subtitle,
  });

  final int stepIndex;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = WizardScaffold.labels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${stepIndex + 1} of ${labels.length} · ${labels[stepIndex]}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _Bars(count: labels.length, index: stepIndex),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i <= index
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class FullWidthButton extends StatelessWidget {
  const FullWidthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, textAlign: TextAlign.center);
    final button = switch ((outlined, icon)) {
      (true, null) => OutlinedButton(onPressed: onPressed, child: text),
      (true, final IconData iconData) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(iconData),
        label: text,
      ),
      (false, null) => FilledButton(onPressed: onPressed, child: text),
      (false, final IconData iconData) => FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(iconData),
        label: text,
      ),
    };
    return SizedBox(width: double.infinity, child: button);
  }
}
