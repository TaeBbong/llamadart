import 'package:flutter/material.dart';

import '../guard_controller.dart';
import 'photo_page.dart';
import 'redacted_image.dart';

/// The model's state, as the page shows it.
class ModelStatus {
  /// Creates a status. [ready] is set once the model can check photos.
  const ModelStatus(this.message, {this.fraction, this.ready = false});

  /// What is happening, or where the model runs once ready.
  final String message;

  /// Download progress, when known.
  final double? fraction;

  /// Whether the model is loaded.
  final bool ready;
}

/// The picked photos, each with its check, and the share button.
class GuardPage extends StatelessWidget {
  /// Creates the page.
  const GuardPage({
    super.key,
    required this.controller,
    required this.status,
    required this.onPick,
    required this.onShare,
  });

  /// The photos and checks.
  final GuardController controller;

  /// The model's state.
  final ModelStatus status;

  /// Opens the system photo picker.
  final VoidCallback onPick;

  /// Shares the checked photos, blacked out; [origin] is the share button's
  /// area, for the share sheet's popover on iPad and macOS.
  final void Function(Rect origin) onShare;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Guard'),
        actions: [
          if (controller.photos.isNotEmpty)
            IconButton(
              tooltip: 'Add photos',
              onPressed: onPick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: _StatusLine(status: status),
        ),
      ),
      body: controller.photos.isEmpty
          ? _Empty(onPick: onPick, unreadable: controller.unreadable)
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: controller.photos.length,
              itemBuilder: (context, index) {
                final photo = controller.photos[index];
                return _PhotoTile(
                  photo: photo,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PhotoPage(controller: controller, photo: photo),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: controller.photos.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: controller.ready.isEmpty || controller.scanning
                      ? null
                      : () {
                          final box = context.findRenderObject() as RenderBox;
                          onShare(box.localToGlobal(Offset.zero) & box.size);
                        },
                  icon: const Icon(Icons.ios_share),
                  label: Text(
                    controller.scanning
                        ? 'Checking on this device…'
                        : 'Share ${controller.ready.length} guarded',
                  ),
                ),
              ),
            ),
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final ModelStatus status;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
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
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(status.message, style: style),
                      LinearProgressIndicator(value: status.fraction),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick, required this.unreadable});

  final VoidCallback onPick;
  final List<String> unreadable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: theme.primaryColor),
            const SizedBox(height: 16),
            Text(
              'Check photos before you share them',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'ID cards, card numbers, addresses and other private details '
              'are found and blacked out on this device. Nothing is uploaded.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pick photos'),
            ),
            if (unreadable.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Could not read ${unreadable.join(', ')}.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final GuardPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = photo.hidden.length;
    final (icon, label, color) = switch (photo.state) {
      PhotoState.waiting => (Icons.hourglass_empty, 'Waiting', scheme.outline),
      PhotoState.scanning => (Icons.search, 'Checking…', scheme.primary),
      PhotoState.failed => (Icons.error_outline, 'Not checked', scheme.error),
      PhotoState.scanned when hidden == 0 => (
        Icons.verified_outlined,
        'Safe to share',
        Colors.green.shade700,
      ),
      PhotoState.scanned => (
        Icons.visibility_off_outlined,
        '$hidden hidden',
        Colors.orange.shade800,
      ),
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: photo.state == PhotoState.scanned ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(child: RedactedImage(photo: photo)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label, style: TextStyle(color: color)),
                  ),
                  if (photo.prepared.hasLocation)
                    Tooltip(
                      message: 'Location in metadata, removed when shared',
                      child: Icon(
                        Icons.location_off_outlined,
                        size: 18,
                        color: scheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
