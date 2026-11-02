import 'package:flutter/material.dart';

import '../guard_controller.dart';

/// [photo] with each hidden finding blacked out as it will be shared, and
/// each shown one outlined when [outlineShown].
class RedactedImage extends StatelessWidget {
  /// Creates the image.
  const RedactedImage({
    super.key,
    required this.photo,
    this.outlineShown = false,
    this.onTapFinding,
  });

  /// The photo.
  final GuardPhoto photo;

  /// Whether to outline findings the user left visible.
  final bool outlineShown;

  /// Called with a finding's index when it is tapped.
  final void Function(int index)? onTapFinding;

  @override
  Widget build(BuildContext context) {
    final findings = photo.report?.findings ?? const [];
    final accent = Theme.of(context).colorScheme.tertiary;
    return AspectRatio(
      aspectRatio: photo.prepared.width / photo.prepared.height,
      child: LayoutBuilder(
        builder: (context, size) => Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              photo.prepared.modelImage,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
            for (final (i, finding) in findings.indexed)
              if (outlineShown || !photo.shown.contains(i))
                Builder(
                  builder: (context) {
                    // The same margin redactPhoto adds.
                    final box = finding.box.inflate(0.01);
                    final hidden = !photo.shown.contains(i);
                    return Positioned(
                      left: box.left * size.maxWidth,
                      top: box.top * size.maxHeight,
                      width: (box.right - box.left) * size.maxWidth,
                      height: (box.bottom - box.top) * size.maxHeight,
                      child: GestureDetector(
                        onTap: onTapFinding == null
                            ? null
                            : () => onTapFinding!(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: hidden ? Colors.black : Colors.transparent,
                            border: hidden
                                ? null
                                : Border.all(color: accent, width: 2),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}
