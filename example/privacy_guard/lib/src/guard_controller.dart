import 'package:flutter/foundation.dart';

import 'redaction.dart';
import 'scanner.dart';

/// Checks one photo for private details.
typedef Scan = Future<ScanReport> Function(Uint8List image);

/// Where a photo is in the check.
enum PhotoState { waiting, scanning, scanned, failed }

/// A picked photo and what the check found.
class GuardPhoto {
  /// Creates a photo named [name] from its encoded [bytes].
  GuardPhoto(this.name, this.bytes, this.prepared);

  /// File name.
  final String name;

  /// The file as picked.
  final Uint8List bytes;

  /// The decoded photo and its copy for the model.
  final PreparedPhoto prepared;

  /// Where it is.
  PhotoState state = PhotoState.waiting;

  /// What the model found, once scanned.
  ScanReport? report;

  /// Indices of findings the user chose to leave visible.
  final Set<int> shown = {};

  /// Findings blacked out when the photo is shared.
  List<Finding> get hidden => [
    for (final (i, f) in (report?.findings ?? const <Finding>[]).indexed)
      if (!shown.contains(i)) f,
  ];
}

/// The picked photos, the checks over them and the user's choices.
class GuardController extends ChangeNotifier {
  /// Creates a controller that decodes photos with [prepare] and makes
  /// shareable copies with [redact], both off the UI isolate in the app.
  GuardController({
    required Future<PreparedPhoto> Function(Uint8List bytes) prepare,
    required Future<Uint8List> Function(Uint8List bytes, List<Box> boxes)
    redact,
  }) : _prepare = prepare,
       _redact = redact;

  final Future<PreparedPhoto> Function(Uint8List bytes) _prepare;
  final Future<Uint8List> Function(Uint8List bytes, List<Box> boxes) _redact;

  /// Picked photos, in the order picked.
  final List<GuardPhoto> photos = [];

  /// Names of picked files that could not be read as images.
  final List<String> unreadable = [];

  bool _scanning = false;

  /// Whether a check is running.
  bool get scanning => _scanning;

  /// Photos checked and ready to share.
  Iterable<GuardPhoto> get ready =>
      photos.where((p) => p.state == PhotoState.scanned);

  /// Decodes [picked] files, as name and bytes, and queues them for a check.
  Future<void> add(List<(String, Uint8List)> picked) async {
    for (final (name, bytes) in picked) {
      try {
        photos.add(GuardPhoto(name, bytes, await _prepare(bytes)));
      } on FormatException {
        unreadable.add(name);
      }
      notifyListeners();
    }
  }

  /// Checks every waiting photo with [scan], one at a time, including
  /// photos added while it runs.
  Future<void> scanWaiting(Scan scan) async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    for (var photo = _nextWaiting(); photo != null; photo = _nextWaiting()) {
      photo.state = PhotoState.scanning;
      notifyListeners();
      try {
        photo.report = await scan(photo.prepared.modelImage);
        photo.state = PhotoState.scanned;
      } catch (_) {
        photo.state = PhotoState.failed;
      }
      notifyListeners();
    }
    _scanning = false;
    notifyListeners();
  }

  GuardPhoto? _nextWaiting() =>
      photos.where((p) => p.state == PhotoState.waiting).firstOrNull;

  /// Shows finding [index] of [photo] if hidden, or hides it if shown.
  void toggle(GuardPhoto photo, int index) {
    if (!photo.shown.remove(index)) photo.shown.add(index);
    notifyListeners();
  }

  /// Removes [photo].
  void remove(GuardPhoto photo) {
    photos.remove(photo);
    notifyListeners();
  }

  /// Copies of the checked photos, with their hidden findings blacked out
  /// and no metadata, named after the originals.
  Future<List<(String, Uint8List)>> shareable() async => [
    for (final photo in ready.toList())
      (
        '${photo.name.split('.').first}-guarded.jpg',
        await _redact(photo.bytes, [for (final f in photo.hidden) f.box]),
      ),
  ];
}
