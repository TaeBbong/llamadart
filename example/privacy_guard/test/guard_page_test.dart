import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_guard_example/src/guard_controller.dart';
import 'package:privacy_guard_example/src/scanner.dart';
import 'package:privacy_guard_example/src/ui/guard_page.dart';

import 'support.dart';

void main() {
  late GuardController guard;
  late int picks;
  late List<Rect> shares;

  Future<void> pumpPage(WidgetTester tester) async {
    picks = 0;
    shares = [];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GuardPage(
          controller: guard,
          status: const ModelStatus('Qwen3.5 4B · Metal', ready: true),
          onPick: () => picks++,
          onShare: shares.add,
        ),
      ),
    );
  }

  setUp(() => guard = fakeController());
  tearDown(() => guard.dispose());

  testWidgets('starts with the picker', (tester) async {
    await pumpPage(tester);

    expect(find.text('Check photos before you share them'), findsOneWidget);
    await tester.tap(find.text('Pick photos'));
    expect(picks, 1);
  });

  testWidgets('labels each photo and shares the checked ones', (tester) async {
    await guard.add([
      ('safe.jpg', Uint8List.fromList([0])),
      ('card.jpg', Uint8List.fromList([1])),
    ]);
    await guard.scanWaiting(
      (image) async => reportOf(
        guard.photos.last.state == PhotoState.scanning
            ? [
                findingOf(PrivateKind.paymentCard),
                findingOf(PrivateKind.personName),
              ]
            : const [],
      ),
    );
    await pumpPage(tester);

    expect(find.text('Safe to share'), findsOneWidget);
    expect(find.text('2 hidden'), findsOneWidget);
    expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);

    await tester.tap(find.text('Share 2 guarded'));
    expect(shares, hasLength(1));
  });

  testWidgets('a finding switched off stays visible', (tester) async {
    await guard.add([
      ('card.jpg', Uint8List.fromList([0])),
    ]);
    await guard.scanWaiting(
      (_) async => reportOf([
        findingOf(PrivateKind.paymentCard),
        findingOf(PrivateKind.personName),
      ], 'Not safe to share.'),
    );
    await pumpPage(tester);

    await tester.tap(find.text('2 hidden'));
    await tester.pumpAndSettle();
    expect(find.text('Not safe to share.'), findsOneWidget);
    expect(find.text('Checked in 6.4 s on this device'), findsOneWidget);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(guard.photos.single.hidden.map((f) => f.kind), [
      PrivateKind.paymentCard,
    ]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 hidden'), findsOneWidget);
  });
}
