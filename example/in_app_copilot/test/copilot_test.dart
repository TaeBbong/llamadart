import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_copilot_example/src/copilot.dart';

void main() {
  test('copilotInstructions gives this month and last month', () {
    final prompt = copilotInstructions(DateTime(2026, 3, 9));

    expect(prompt, contains('Today is 2026-03-09.'));
    expect(prompt, contains('This month runs from 2026-03-01;'));
    expect(prompt, contains('last month ran from 2026-02-01 to 2026-02-28.'));
    expect(prompt, contains('food, delivery, cafe'));
  });

  test('copilotInstructions crosses the year in January', () {
    expect(
      copilotInstructions(DateTime(2027, 1, 3)),
      contains('last month ran from 2026-12-01 to 2026-12-31.'),
    );
  });

  test('ToolActivity.signature shows the call as written', () {
    expect(
      ToolActivity('set_budget', {
        'category': 'delivery',
        'amount': 96000,
      }).signature,
      'set_budget(category: "delivery", amount: 96000)',
    );
    expect(
      ToolActivity('budget_status', const {}).signature,
      'budget_status()',
    );
  });
}
