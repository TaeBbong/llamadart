import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:screenshot_inbox_example/src/library.dart';
import 'package:screenshot_inbox_example/src/triage.dart';

/// A 1x1 PNG.
final Uint8List tinyPng = img.encodePng(img.Image(width: 1, height: 1));

/// A screenshot with id [id].
Screenshot shot(String id) =>
    Screenshot(id: id, createdAt: DateTime(2026, 11, 2), preview: tinyPng);

/// A library holding [shots] that deletes only [deletable] ids.
class FakeLibrary implements ScreenshotLibrary {
  /// Creates the library.
  FakeLibrary(this.shots, {this.deletable, this.error});

  /// What [recent] returns.
  final List<Screenshot> shots;

  /// Ids [delete] reports deleted; all requested when null.
  final Set<String>? deletable;

  /// Thrown by [recent] when set.
  final Object? error;

  /// Ids passed to [delete].
  final List<List<String>> deleteRequests = [];

  @override
  Future<List<Screenshot>> recent({int limit = 30}) async {
    if (error case final e?) throw e;
    return shots.take(limit).toList();
  }

  @override
  Future<List<String>> delete(List<String> ids) async {
    deleteRequests.add(ids);
    return [
      for (final id in ids)
        if (deletable?.contains(id) ?? true) id,
    ];
  }
}

/// A triage of [kind] with [actions].
Triage triageOf(
  ScreenshotKind kind,
  String summary, [
  List<InboxAction> actions = const [],
]) => Triage(
  kind: kind,
  summary: summary,
  actions: actions,
  elapsed: const Duration(milliseconds: 2400),
);
