import 'package:flutter/material.dart';

import '../inbox_controller.dart';
import '../triage.dart';

/// The model's state, as the page shows it.
class ModelStatus {
  /// Creates a status. [ready] is set once the model can sort.
  const ModelStatus(this.message, {this.fraction, this.ready = false});

  /// What is happening, or where the model runs once ready.
  final String message;

  /// Download progress, when known.
  final double? fraction;

  /// Whether the model is loaded.
  final bool ready;
}

/// The inbox: screenshots, what the agent made of each, and one-tap
/// follow-ups.
class InboxPage extends StatelessWidget {
  /// Creates the page.
  const InboxPage({
    super.key,
    required this.controller,
    required this.status,
    required this.onSort,
    required this.onRun,
    this.onOpenSettings,
  });

  /// The inbox state.
  final InboxController controller;

  /// The model's state.
  final ModelStatus status;

  /// Starts sorting every unsorted screenshot.
  final VoidCallback onSort;

  /// Runs a proposed action and returns whether it ran.
  final Future<bool> Function(InboxAction action) onRun;

  /// Opens the system settings when photo access was denied.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Screenshot Inbox'),
          // iOS centers the title only beside fewer than two actions, so it
          // would jump when the Delete action appears.
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Reload screenshots',
              onPressed: controller.sorting || controller.loading
                  ? null
                  : controller.load,
              icon: const Icon(Icons.refresh),
            ),
            if (controller.doneCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: controller.sorting ? null : controller.deleteDone,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Delete ${controller.doneCount}'),
                ),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: _StatusLine(status: status),
          ),
        ),
        body: _body(context, theme),
        bottomNavigationBar: _SortBar(
          controller: controller,
          ready: status.ready,
          onSort: onSort,
        ),
      );
    },
  );

  Widget _body(BuildContext context, ThemeData theme) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (onOpenSettings != null)
                OutlinedButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ),
      );
    }
    if (controller.items.isEmpty) {
      return const Center(child: Text('No screenshots found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: controller.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _InboxCard(
        item: controller.items[index],
        onRun: (action) async {
          if (await onRun(action)) {
            controller.markRan(controller.items[index], action);
          }
        },
        onDone: () => controller.toggleDone(controller.items[index]),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final ModelStatus status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        Icon(
          status.ready ? Icons.memory : Icons.downloading,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: status.ready || status.fraction == null
              ? Text(
                  status.message,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    LinearProgressIndicator(value: status.fraction),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.controller,
    required this.ready,
    required this.onSort,
  });

  final InboxController controller;
  final bool ready;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final total = controller.items.length;
    final sorted = total - controller.unsorted;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: controller.sorting
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sorted $sorted of $total on this device'),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: total == 0 ? null : sorted / total,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: controller.stop,
                  child: const Text('Stop'),
                ),
              ],
            )
          : FilledButton.icon(
              onPressed: ready && controller.unsorted > 0 ? onSort : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                controller.unsorted == 0 && total > 0
                    ? 'All sorted'
                    : 'Sort ${controller.unsorted} screenshots',
              ),
            ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.onRun,
    required this.onDone,
  });

  final InboxItem item;
  final void Function(InboxAction action) onRun;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final triage = item.triage;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: item.done ? 0.5 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.memory(
              item.screenshot.preview,
              width: 76,
              height: 136,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: switch (item.state) {
                  ItemState.waiting => Text(
                    'Waiting',
                    style: theme.textTheme.bodySmall,
                  ),
                  ItemState.sorting => const Row(
                    children: [
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Reading…'),
                    ],
                  ),
                  ItemState.failed => Text(
                    'Could not sort this one. Sort again to retry.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  ItemState.sorted => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _KindChip(kind: triage!.kind),
                          const SizedBox(width: 8),
                          Text(
                            '${(triage.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(triage.summary, style: theme.textTheme.bodyMedium),
                      if (triage.actions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final action in triage.actions)
                              _ActionChip(
                                action: action,
                                ran: item.ran.contains(action),
                                onPressed: () => onRun(action),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                },
              ),
            ),
            IconButton(
              tooltip: item.done ? 'Keep' : 'Done with it',
              onPressed: item.state == ItemState.sorted ? onDone : null,
              icon: Icon(
                item.done ? Icons.check_circle : Icons.check_circle_outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final ScreenshotKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        kind.title,
        style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.action,
    required this.ran,
    required this.onPressed,
  });

  final InboxAction action;
  final bool ran;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (action) {
      AddEventAction(:final title) => (Icons.event, title),
      OpenMapAction(:final query) => (Icons.place, query),
      CopyTextAction(:final label, :final text) => (
        Icons.content_copy,
        '$label: $text',
      ),
    };
    return ActionChip(
      avatar: Icon(ran ? Icons.check : icon, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      onPressed: onPressed,
    );
  }
}
