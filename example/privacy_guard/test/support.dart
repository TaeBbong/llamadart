import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:privacy_guard_example/src/guard_controller.dart';
import 'package:privacy_guard_example/src/redaction.dart';
import 'package:privacy_guard_example/src/scanner.dart';

/// A 4x3 PNG.
final Uint8List smallPng = img.encodePng(img.Image(width: 4, height: 3));

/// A prepared photo that shows [smallPng], without decoding anything.
Future<PreparedPhoto> fakePrepare(Uint8List bytes) async {
  if (bytes.isEmpty) throw const FormatException('empty');
  return PreparedPhoto(
    modelImage: smallPng,
    width: 400,
    height: 300,
    hasLocation: bytes.first == 1,
  );
}

/// Calls to [FakeRedactor.redact], as bytes and boxes.
class FakeRedactor {
  /// Calls so far.
  final List<(Uint8List, List<Box>)> calls = [];

  /// Records the call and returns the bytes reversed.
  Future<Uint8List> redact(Uint8List bytes, List<Box> boxes) async {
    calls.add((bytes, boxes));
    return Uint8List.fromList(bytes.reversed.toList());
  }
}

/// A controller with fake decoding and redaction.
GuardController fakeController([FakeRedactor? redactor]) => GuardController(
  prepare: fakePrepare,
  redact: (redactor ?? FakeRedactor()).redact,
);

/// A report of [findings].
ScanReport reportOf(List<Finding> findings, [String verdict = 'Checked.']) =>
    ScanReport(
      findings: findings,
      verdict: verdict,
      elapsed: const Duration(milliseconds: 6400),
    );

/// A finding of [kind] in [box].
Finding findingOf(
  PrivateKind kind, [
  Box box = const Box(0.1, 0.1, 0.5, 0.5),
]) => Finding(kind: kind, label: '${kind.title} label', box: box);
