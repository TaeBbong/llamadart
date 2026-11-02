import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_inbox_example/src/inbox_controller.dart';
import 'package:screenshot_inbox_example/src/triage.dart';
import 'package:screenshot_inbox_example/src/ui/inbox_page.dart';

import 'support.dart';

void main() {
  late InboxController inbox;
  late List<InboxAction> ran;
  late int sorts;

  Future<void> pumpPage(WidgetTester tester, {required bool ready}) async {
    ran = [];
    sorts = 0;
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: InboxPage(
          controller: inbox,
          status: ModelStatus(
            ready ? 'Qwen3.5 4B · Metal' : 'Downloading',
            ready: ready,
          ),
          onSort: () => sorts++,
          onRun: (action) async {
            ran.add(action);
            return true;
          },
        ),
      ),
    );
  }

  setUp(() async {
    inbox = InboxController(FakeLibrary([shot('a'), shot('b')]));
    await inbox.load();
  });

  tearDown(() => inbox.dispose());

  testWidgets('waits for the model before sorting', (tester) async {
    await pumpPage(tester, ready: false);

    final button = find.widgetWithText(FilledButton, 'Sort 2 screenshots');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await pumpPage(tester, ready: true);
    await tester.tap(button);
    expect(sorts, 1);
  });

  testWidgets('shows each triage and runs a follow-up on tap', (tester) async {
    const copy = CopyTextAction(label: 'Coupon code', text: 'WINTER5K');
    await inbox.sortAll(
      (_) async => triageOf(ScreenshotKind.coupon, '5,000 won off', [copy]),
    );
    await pumpPage(tester, ready: true);

    expect(find.text('Coupon'), findsNWidgets(2));
    expect(find.text('5,000 won off'), findsNWidgets(2));
    expect(find.text('2.4 s'), findsNWidgets(2));
    expect(find.text('All sorted'), findsOneWidget);

    await tester.tap(find.text('Coupon code: WINTER5K').first);
    await tester.pump();

    expect(ran, [copy]);
    expect(inbox.items.first.ran, {copy});
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('offers to delete screenshots marked done', (tester) async {
    await inbox.sortAll((_) async => triageOf(ScreenshotKind.meme, 'meme'));
    await pumpPage(tester, ready: true);
    expect(find.textContaining('Delete'), findsNothing);

    await tester.tap(find.byTooltip('Done with it').first);
    await tester.pump();

    expect(find.text('Delete 1'), findsOneWidget);
  });
}
