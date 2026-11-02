import 'package:flutter/material.dart';

import '../guard_controller.dart';
import 'redacted_image.dart';

/// One checked photo: what will be blacked out, and a switch per finding.
class PhotoPage extends StatelessWidget {
  /// Creates the page.
  const PhotoPage({super.key, required this.controller, required this.photo});

  /// The photos and checks.
  final GuardController controller;

  /// The photo shown.
  final GuardPhoto photo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final report = photo.report!;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          // Phones pass picked photos as renamed temporary files, so the
          // file name says nothing to the user.
          title: const Text('Photo check'),
          actions: [
            IconButton(
              tooltip: 'Remove photo',
              onPressed: () {
                controller.remove(photo);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: RedactedImage(
                  photo: photo,
                  outlineShown: true,
                  onTapFinding: (i) => controller.toggle(photo, i),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(report.verdict, style: theme.textTheme.bodyMedium),
            Text(
              'Checked in ${(report.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s on this device',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final (i, finding) in report.findings.indexed)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(finding.kind.title),
                subtitle: finding.label.isEmpty ? null : Text(finding.label),
                secondary: const Icon(Icons.visibility_off_outlined),
                value: !photo.shown.contains(i),
                onChanged: (_) => controller.toggle(photo, i),
              ),
            if (photo.prepared.hasLocation)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.location_off_outlined),
                title: Text('GPS location in metadata'),
                subtitle: Text('Always removed when shared'),
              ),
          ],
        ),
      );
    },
  );
}
