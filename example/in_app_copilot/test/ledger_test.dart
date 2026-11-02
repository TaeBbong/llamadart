import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_copilot_example/src/ledger.dart';

Expense expense(
  int id,
  DateTime date,
  int amount, [
  Category category = Category.food,
  String merchant = 'Kimbap House',
]) => Expense(
  id: id,
  date: date,
  amount: amount,
  category: category,
  merchant: merchant,
);

void main() {
  test('won and formatDay write amounts and days', () {
    expect(won(0), '₩0');
    expect(won(9000), '₩9,000');
    expect(won(1234567), '₩1,234,567');
    expect(won(-14300), '-₩14,300');
    expect(formatDay(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('Category.parse ignores case and spaces', () {
    expect(Category.parse(' Delivery '), Category.delivery);
    expect(Category.parse('coffee'), isNull);
    expect(Category.cafe.title, 'Cafe');
  });

  group('Ledger', () {
    late Ledger ledger;
    late int changes;

    setUp(() {
      ledger = Ledger(
        expenses: [
          expense(1, DateTime(2026, 10, 30), 9000),
          expense(
            4,
            DateTime(2026, 11, 1),
            21000,
            Category.delivery,
            'Pizza Now',
          ),
          expense(2, DateTime(2026, 11, 1), 5000, Category.cafe, 'Corner Cafe'),
        ],
        budgets: {Category.food: 100000},
      );
      changes = 0;
      ledger.changes.listen((_) => changes++);
    });

    tearDown(() => ledger.close());

    test('lists newest first, then by id', () {
      expect(ledger.expenses.map((e) => e.id), [4, 2, 1]);
    });

    test('find matches every filter given', () {
      expect(ledger.find(merchant: 'pizza').single.id, 4);
      expect(ledger.find(category: Category.cafe).single.id, 2);
      expect(ledger.find(from: DateTime(2026, 11, 1)).map((e) => e.id), [4, 2]);
      expect(ledger.find(to: DateTime(2026, 10, 31, 23)).single.id, 1);
      expect(ledger.spent(Category.food), 9000);
    });

    test('add gives the next id and marks it added', () {
      final added = ledger.add(
        amount: 9000,
        category: Category.food,
        merchant: 'Kimbap House',
        date: DateTime(2026, 11, 2, 13, 30),
      );

      expect(added.id, 5);
      expect(added.date, DateTime(2026, 11, 2));
      expect(ledger.lastAdded, {5});
      expect(changes, 1);
    });

    test('delete returns what it deleted and fires only then', () {
      expect(ledger.delete([99]), isEmpty);
      expect(changes, 0);

      expect(ledger.delete([1, 99]).single.id, 1);
      expect(ledger.expenses, hasLength(2));
      expect(changes, 1);
    });

    test('setBudget returns the previous budget', () {
      expect(ledger.setBudget(Category.food, 80000), 100000);
      expect(ledger.setBudget(Category.cafe, 50000), isNull);
      expect(ledger.budgets[Category.food], 80000);
      expect(ledger.lastBudgeted, {Category.cafe});
      expect(changes, 2);
    });
  });

  test('Ledger.sample is repeatable and holds a taxi ride charged twice', () {
    final today = DateTime(2026, 11, 20);
    final a = Ledger.sample(today), b = Ledger.sample(today);
    addTearDown(a.close);
    addTearDown(b.close);

    expect(
      a.expenses.map((e) => e.toJson()),
      b.expenses.map((e) => e.toJson()),
    );
    expect(a.find(from: DateTime(2026, 10)).length, a.expenses.length);
    expect(a.find(from: DateTime(2026, 11, 21)), isEmpty);
    final taxis = a.find(merchant: 'Taxi', from: DateTime(2026, 11, 18));
    expect(
      taxis.where((e) => e.amount == 14300 && e.date == DateTime(2026, 11, 18)),
      hasLength(2),
    );
    expect(a.budgets, hasLength(Category.values.length));
  });
}
