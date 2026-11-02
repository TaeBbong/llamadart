import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_inbox_example/src/inbox_controller.dart';
import 'package:screenshot_inbox_example/src/library.dart';
import 'package:screenshot_inbox_example/src/triage.dart';

import 'support.dart';

void main() {
  test('load keeps the newest screenshots up to the limit', () async {
    final inbox = InboxController(
      FakeLibrary([shot('a'), shot('b'), shot('c')]),
      limit: 2,
    );
    addTearDown(inbox.dispose);

    await inbox.load();

    expect(inbox.items.map((i) => i.screenshot.id), ['a', 'b']);
    expect(inbox.unsorted, 2);
    expect(inbox.loading, isFalse);
  });

  test('load reports why it failed', () async {
    final inbox = InboxController(
      FakeLibrary(const [], error: const PhotoAccessDenied()),
    );
    addTearDown(inbox.dispose);

    await inbox.load();

    expect(inbox.error, isA<PhotoAccessDenied>());
    expect(inbox.items, isEmpty);
  });

  test('sortAll sorts in order and marks failures for a retry', () async {
    final inbox = InboxController(
      FakeLibrary([shot('a'), shot('b'), shot('c')]),
    );
    addTearDown(inbox.dispose);
    await inbox.load();
    var calls = 0;

    await inbox.sortAll((Uint8List image) async {
      calls++;
      if (calls == 2) throw StateError('model failed');
      return triageOf(ScreenshotKind.meme, 'meme $calls');
    });

    expect(inbox.items.map((i) => i.state), [
      ItemState.sorted,
      ItemState.failed,
      ItemState.sorted,
    ]);
    expect(inbox.items.last.triage!.summary, 'meme 3');
    expect(inbox.sorting, isFalse);

    await inbox.sortAll((_) async => triageOf(ScreenshotKind.chat, 'retry'));
    expect(inbox.items[1].triage!.summary, 'retry');
    expect(inbox.unsorted, 0);
  });

  test('stop ends the run after the screenshot being sorted', () async {
    final inbox = InboxController(
      FakeLibrary([shot('a'), shot('b'), shot('c')]),
    );
    addTearDown(inbox.dispose);
    await inbox.load();
    final first = Completer<Triage>();

    final run = inbox.sortAll((_) => first.future);
    expect(inbox.items.first.state, ItemState.sorting);
    inbox.stop();
    first.complete(triageOf(ScreenshotKind.other, 'first'));
    await run;

    expect(inbox.items.map((i) => i.state), [
      ItemState.sorted,
      ItemState.waiting,
      ItemState.waiting,
    ]);
  });

  test('deleteDone removes only what the library deleted', () async {
    final library = FakeLibrary(
      [shot('a'), shot('b'), shot('c')],
      deletable: {'a'},
    );
    final inbox = InboxController(library);
    addTearDown(inbox.dispose);
    await inbox.load();

    inbox.toggleDone(inbox.items[0]);
    inbox.toggleDone(inbox.items[2]);
    expect(inbox.doneCount, 2);
    await inbox.deleteDone();

    expect(library.deleteRequests, [
      ['a', 'c'],
    ]);
    expect(inbox.items.map((i) => i.screenshot.id), ['b', 'c']);
    expect(inbox.doneCount, 1);
  });

  test('markRan records the action on its item', () async {
    final inbox = InboxController(FakeLibrary([shot('a')]));
    addTearDown(inbox.dispose);
    await inbox.load();
    const action = OpenMapAction('Seoul');

    inbox.markRan(inbox.items.single, action);

    expect(inbox.items.single.ran, {action});
  });
}
