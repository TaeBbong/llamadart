import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_copilot_example/src/copilot_tools.dart';
import 'package:in_app_copilot_example/src/ledger.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  final today = DateTime(2026, 11, 20);
  late Ledger ledger;
  late List<String> questions;
  late bool approve;
  late Map<String, ToolDefinition> tools;

  Future<Object?> call(String name, [Map<String, dynamic> args = const {}]) =>
      tools[name]!.invoke(args);

  setUp(() {
    ledger = Ledger(
      expenses: [
        Expense(
          id: 1,
          date: DateTime(2026, 10, 12),
          amount: 30000,
          category: Category.delivery,
          merchant: 'Pizza Now',
        ),
        Expense(
          id: 2,
          date: DateTime(2026, 11, 3),
          amount: 25000,
          category: Category.delivery,
          merchant: 'Chicken Express',
        ),
        Expense(
          id: 3,
          date: DateTime(2026, 11, 4),
          amount: 4500,
          category: Category.cafe,
          merchant: 'Corner Cafe',
        ),
      ],
      budgets: {Category.delivery: 20000, Category.cafe: 50000},
    );
    questions = [];
    approve = true;
    tools = {
      for (final t in ledgerTools(
        ledger,
        today: () => today,
        confirm: (q) async {
          questions.add(q);
          return approve;
        },
      ))
        t.name: t,
    };
  });

  tearDown(() => ledger.close());

  test('find_expenses lists matches with ids and a total', () async {
    final result =
        await call('find_expenses', {
              'category': 'delivery',
              'from': '2026-11-01',
            })
            as Map;

    expect(result['count'], 1);
    expect(result['total'], 25000);
    expect(result['expenses'], [
      {
        'id': 2,
        'date': '2026-11-03',
        'merchant': 'Chicken Express',
        'category': 'delivery',
        'amount': 25000,
      },
    ]);
  });

  test('find_expenses lists only the newest 25', () async {
    for (var i = 0; i < 30; i++) {
      ledger.add(
        amount: 1000,
        category: Category.cafe,
        merchant: 'Bean Brothers',
        date: today,
      );
    }

    final result = await call('find_expenses', {'merchant': 'bean'}) as Map;

    expect(result['count'], 30);
    expect(result['expenses'], hasLength(25));
    expect(result['note'], isNotNull);
  });

  test('find_expenses names the merchants when a name matches none', () async {
    final result =
        await call('find_expenses', {'category': 'delivery', 'merchant': '피자'})
            as Map;

    expect(result['count'], 0);
    expect(
      result['note'],
      'No merchant name contains "피자". Merchants with the other filters: '
      'Chicken Express, Pizza Now.',
    );
  });

  test('spending_summary groups this month by default', () async {
    final result = await call('spending_summary') as Map;

    expect(result['from'], '2026-11-01');
    expect(result['to'], '2026-11-20');
    expect(result['total'], 29500);
    expect(result['groups'], [
      {'name': 'delivery', 'total': 25000, 'count': 1},
      {'name': 'cafe', 'total': 4500, 'count': 1},
    ]);

    final byMerchant =
        await call('spending_summary', {
              'from': '2026-10-01',
              'to': '2026-10-31',
              'group_by': 'merchant',
            })
            as Map;
    expect(byMerchant['groups'], [
      {'name': 'Pizza Now', 'total': 30000, 'count': 1},
    ]);
  });

  test('budget_status flags categories over budget this month', () async {
    final result = await call('budget_status') as Map;

    expect(result['month'], '2026-11');
    expect(result['categories'], [
      {
        'category': 'delivery',
        'budget': 20000,
        'spent': 25000,
        'left': -5000,
        'over_budget': true,
      },
      {
        'category': 'cafe',
        'budget': 50000,
        'spent': 4500,
        'left': 45500,
        'over_budget': false,
      },
    ]);
  });

  test('add_expense records today by default', () async {
    final result =
        await call('add_expense', {
              'amount': 9000,
              'category': 'Food',
              'merchant': ' Kimbap House ',
            })
            as Map;

    expect(result['added'], {
      'id': 4,
      'date': '2026-11-20',
      'merchant': 'Kimbap House',
      'category': 'food',
      'amount': 9000,
    });
  });

  test('set_budget returns the previous budget', () async {
    expect(
      await call('set_budget', {'category': 'delivery', 'amount': 16000}),
      {'category': 'delivery', 'previous': 20000, 'budget': 16000},
    );
    expect(ledger.budgets[Category.delivery], 16000);
  });

  test('bad arguments throw a message the model can act on', () async {
    await expectLater(
      call('add_expense', {
        'amount': 9000,
        'category': 'coffee',
        'merchant': 'x',
      }),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('Use one of food, delivery, cafe'),
        ),
      ),
    );
    await expectLater(
      call('find_expenses', {'from': 'last week'}),
      throwsFormatException,
    );
    await expectLater(
      call('spending_summary', {'group_by': 'week'}),
      throwsArgumentError,
    );
    await expectLater(
      call('add_expense', {'amount': 0, 'category': 'food', 'merchant': 'x'}),
      throwsArgumentError,
    );
  });

  group('delete_expenses', () {
    test('deletes once the user approves', () async {
      final result = await call('delete_expenses', {
        'ids': [2, 3],
      });

      expect(result, {
        'deleted': [2, 3],
      });
      expect(
        questions.single,
        'Delete 2 expenses?\n'
        '2026-11-04  Corner Cafe  ₩4,500\n'
        '2026-11-03  Chicken Express  ₩25,000',
      );
      expect(ledger.expenses.single.id, 1);
    });

    test('keeps everything when the user declines', () async {
      approve = false;

      final result = await call('delete_expenses', {
        'ids': [1],
      });

      expect(result, {'deleted': 0, 'note': 'The user declined.'});
      expect(ledger.expenses, hasLength(3));
    });

    test('rejects ids that match nothing without asking', () async {
      await expectLater(
        call('delete_expenses', {
          'ids': [42],
        }),
        throwsArgumentError,
      );
      expect(questions, isEmpty);
    });
  });
}
