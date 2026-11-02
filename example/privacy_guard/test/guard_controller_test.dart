import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_guard_example/src/guard_controller.dart';
import 'package:privacy_guard_example/src/scanner.dart';

import 'support.dart';

void main() {
  test('add queues readable photos and names the others', () async {
    final guard = fakeController();
    addTearDown(guard.dispose);

    await guard.add([
      ('a.jpg', Uint8List.fromList([1])),
      ('broken.heic', Uint8List(0)),
      ('b.jpg', Uint8List.fromList([2])),
    ]);

    expect(guard.photos.map((p) => p.name), ['a.jpg', 'b.jpg']);
    expect(guard.photos.map((p) => p.state), everyElement(PhotoState.waiting));
    expect(guard.photos.first.prepared.hasLocation, isTrue);
    expect(guard.unreadable, ['broken.heic']);
  });

  test('scanWaiting checks in order and marks failures', () async {
    final guard = fakeController();
    addTearDown(guard.dispose);
    await guard.add([
      for (final n in ['a', 'b', 'c']) (n, Uint8List.fromList([0])),
    ]);
    var calls = 0;

    await guard.scanWaiting((_) async {
      if (++calls == 2) throw StateError('model failed');
      return reportOf([findingOf(PrivateKind.address)]);
    });

    expect(guard.photos.map((p) => p.state), [
      PhotoState.scanned,
      PhotoState.failed,
      PhotoState.scanned,
    ]);
    expect(guard.ready.map((p) => p.name), ['a', 'c']);
    expect(guard.scanning, isFalse);
  });

  test('scanWaiting also checks photos added while it runs', () async {
    final guard = fakeController();
    addTearDown(guard.dispose);
    await guard.add([
      ('a', Uint8List.fromList([0])),
    ]);
    final first = Completer<ScanReport>();
    final scanned = <int>[];
    var calls = 0;

    final run = guard.scanWaiting((_) {
      scanned.add(++calls);
      return calls == 1 ? first.future : Future.value(reportOf(const []));
    });
    await guard.add([
      ('b', Uint8List.fromList([0])),
    ]);
    // A second run while one is going does nothing.
    await guard.scanWaiting((_) => throw StateError('second run'));
    first.complete(reportOf(const []));
    await run;

    expect(scanned, [1, 2]);
    expect(guard.ready, hasLength(2));
  });

  test('toggle shows or hides a finding', () async {
    final guard = fakeController();
    addTearDown(guard.dispose);
    await guard.add([
      ('a', Uint8List.fromList([0])),
    ]);
    await guard.scanWaiting(
      (_) async => reportOf([
        findingOf(PrivateKind.personName),
        findingOf(PrivateKind.phoneNumber),
      ]),
    );
    final photo = guard.photos.single;

    guard.toggle(photo, 0);
    expect(photo.hidden.map((f) => f.kind), [PrivateKind.phoneNumber]);
    guard.toggle(photo, 0);
    expect(photo.hidden, hasLength(2));
  });

  test('shareable redacts checked photos with their hidden boxes', () async {
    final redactor = FakeRedactor();
    final guard = fakeController(redactor);
    addTearDown(guard.dispose);
    await guard.add([
      ('IMG_1.HEIC', Uint8List.fromList([0, 9])),
      ('IMG_2.jpg', Uint8List.fromList([0, 8])),
    ]);
    const kept = Box(0.6, 0.6, 0.9, 0.9);
    await guard.scanWaiting(
      (_) async => reportOf([
        findingOf(PrivateKind.licensePlate),
        findingOf(PrivateKind.address, kept),
      ]),
    );
    guard.toggle(guard.photos.first, 0);
    guard.remove(guard.photos.last);

    final shared = await guard.shareable();

    expect(shared.single.$1, 'IMG_1-guarded.jpg');
    expect(shared.single.$2, [9, 0]);
    expect(redactor.calls.single.$2, [kept]);
  });
}
