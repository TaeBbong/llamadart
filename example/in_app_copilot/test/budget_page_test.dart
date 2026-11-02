import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_copilot_example/src/copilot.dart';
import 'package:in_app_copilot_example/src/ledger.dart';
import 'package:in_app_copilot_example/src/ui/budget_page.dart';
import 'package:in_app_copilot_example/src/ui/copilot_panel.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  final today = DateTime(2026, 11, 20);
  late Ledger ledger;

  Future<void> pumpPage(
    WidgetTester tester, {
    Ask? ask,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BudgetPage(
          ledger: ledger,
          today: today,
          status: ask == null ? 'Downloading' : 'Qwen3.5 4B · Metal',
          ask: ask,
        ),
      ),
    );
  }

  setUp(() {
    ledger = Ledger(
      expenses: [
        Expense(
          id: 1,
          date: DateTime(2026, 11, 3),
          amount: 25000,
          category: Category.delivery,
          merchant: 'Chicken Express',
        ),
      ],
      budgets: {Category.delivery: 20000},
    );
  });

  tearDown(() => ledger.close());

  testWidgets('shows the budget and waits for the model', (tester) async {
    await pumpPage(tester);

    expect(find.text('₩25,000'), findsNWidgets(2));
    expect(find.text('₩25,000 / ₩20,000'), findsOneWidget);
    expect(find.text('Loading model…'), findsOneWidget);
    final chip = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, suggestions.first),
    );
    expect(chip.onPressed, isNull);
  });

  testWidgets('shows each tool call, the answer and the changed app', (
    tester,
  ) async {
    final answered = Completer<void>();
    await pumpPage(
      tester,
      ask: (request, {onActivity}) async {
        final activity = ToolActivity('set_budget', {
          'category': 'delivery',
          'amount': 30000,
        });
        onActivity?.call(activity);
        ledger.setBudget(Category.delivery, 30000);
        activity.result = {'budget': 30000};
        onActivity?.call(activity);
        await answered.future;
        return const CopilotReply(
          text: 'Raised delivery to ₩30,000.',
          activities: [],
          stopReason: LlamaToolLoopStopReason.completed,
        );
      },
    );

    await tester.tap(find.text(suggestions[3]));
    await tester.pump();

    expect(find.text(suggestions[3]), findsOneWidget);
    expect(
      find.text('set_budget(category: "delivery", amount: 30000)'),
      findsOneWidget,
    );
    expect(find.text('₩25,000 / ₩30,000'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);

    answered.complete();
    await tester.pumpAndSettle();
    expect(find.text('Raised delivery to ₩30,000.'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('puts the copilot under the app on a phone', (tester) async {
    await pumpPage(tester, size: const Size(400, 800));

    final app = tester.getRect(find.text('Spent this month'));
    final copilot = tester.getRect(find.text('Copilot'));
    expect(copilot.top, greaterThan(app.bottom));
  });
}
