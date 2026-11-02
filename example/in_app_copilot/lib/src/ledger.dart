import 'dart:async';
import 'dart:math' as math;

/// What an expense was for.
enum Category {
  food,
  delivery,
  cafe,
  groceries,
  transport,
  shopping,
  entertainment,
  bills;

  /// Name shown in the app.
  String get title => '${name[0].toUpperCase()}${name.substring(1)}';

  /// The category named [name], or `null`.
  static Category? parse(String name) {
    final key = name.trim().toLowerCase();
    return values.where((c) => c.name == key).firstOrNull;
  }
}

/// One spending record, in whole Korean won.
class Expense {
  /// Creates an expense.
  const Expense({
    required this.id,
    required this.date,
    required this.amount,
    required this.category,
    required this.merchant,
  });

  /// Stable identifier.
  final int id;

  /// Day it was spent.
  final DateTime date;

  /// Amount in won.
  final int amount;

  /// What it was for.
  final Category category;

  /// Where it was spent.
  final String merchant;

  /// The expense as the model reads it.
  Map<String, Object> toJson() => {
    'id': id,
    'date': formatDay(date),
    'merchant': merchant,
    'category': category.name,
    'amount': amount,
  };
}

/// [day] as `YYYY-MM-DD`.
String formatDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// [amount] as `₩12,345`.
String won(int amount) {
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount < 0 ? '-' : ''}₩$grouped';
}

/// The app's data: expenses and a monthly budget per category.
///
/// Plain Dart, so the copilot's tools and `bin/copilot.dart` use it without
/// Flutter; the app rebuilds on [changes].
class Ledger {
  /// Creates a ledger.
  Ledger({
    Iterable<Expense> expenses = const [],
    Map<Category, int> budgets = const {},
  }) : _expenses = [...expenses],
       _budgets = {...budgets},
       _nextId = expenses.fold(0, (m, e) => math.max(m, e.id)) + 1;

  /// A ledger with this month up to [today] and all of last month.
  factory Ledger.sample(DateTime today) {
    final random = math.Random(7);
    final expenses = <Expense>[];
    var id = 0;
    void spend(DateTime day, int amount, Category category, String merchant) =>
        expenses.add(
          Expense(
            id: ++id,
            date: day,
            amount: amount,
            category: category,
            merchant: merchant,
          ),
        );
    int pick(int low, int high) =>
        (low + random.nextInt(high - low + 1)) ~/ 100 * 100;
    String oneOf(List<String> names) => names[random.nextInt(names.length)];

    final start = DateTime(today.year, today.month - 1);
    for (
      var day = start;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final weekday = day.weekday <= 5;
      if (random.nextDouble() < 0.8) {
        spend(
          day,
          pick(3800, 6500),
          Category.cafe,
          oneOf(['Corner Cafe', 'Bean Brothers']),
        );
      }
      if (weekday) {
        spend(
          day,
          pick(8000, 13000),
          Category.food,
          oneOf(['Kimbap House', 'Noodle Bar', 'Rice Bowl']),
        );
        spend(day, 2800, Category.transport, 'Metro');
      }
      if (random.nextDouble() < 0.45) {
        spend(
          day,
          pick(17000, 34000),
          Category.delivery,
          oneOf(['Chicken Express', 'Pizza Now', 'Tteokbokki Delivery']),
        );
      }
      if (day.weekday == DateTime.saturday) {
        spend(day, pick(38000, 92000), Category.groceries, 'Fresh Mart');
      }
      if (random.nextDouble() < 0.12) {
        spend(day, pick(12000, 21000), Category.transport, 'Taxi');
      }
      if (random.nextDouble() < 0.1) {
        spend(
          day,
          pick(19000, 89000),
          Category.shopping,
          oneOf(['Online Store', 'Bookshop']),
        );
      }
      if (day.weekday == DateTime.friday && random.nextBool()) {
        spend(day, 15000, Category.entertainment, 'Cinema');
      }
      if (day.day == 5) spend(day, 55000, Category.bills, 'Phone bill');
      if (day.day == 15) spend(day, 17000, Category.entertainment, 'Streaming');
    }
    // A taxi ride charged twice, for the copilot to find.
    final twice = DateTime(today.year, today.month, math.max(1, today.day - 2));
    spend(twice, 14300, Category.transport, 'Taxi');
    spend(twice, 14300, Category.transport, 'Taxi');

    return Ledger(
      expenses: expenses,
      budgets: {
        Category.food: 250000,
        Category.delivery: 120000,
        Category.cafe: 100000,
        Category.groceries: 300000,
        Category.transport: 120000,
        Category.shopping: 150000,
        Category.entertainment: 60000,
        Category.bills: 80000,
      },
    );
  }

  final List<Expense> _expenses;
  final Map<Category, int> _budgets;
  final StreamController<void> _changes = StreamController.broadcast(
    sync: true,
  );
  int _nextId;

  /// Fires after every change.
  Stream<void> get changes => _changes.stream;

  /// Ids of the expenses the last change added.
  Set<int> lastAdded = const {};

  /// Categories whose budget the last change set.
  Set<Category> lastBudgeted = const {};

  /// Every expense, newest first.
  List<Expense> get expenses => [..._expenses]
    ..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });

  /// Monthly budget per category.
  Map<Category, int> get budgets => Map.unmodifiable(_budgets);

  /// Expenses matching every filter given, newest first. [merchant] matches
  /// any part of the name, ignoring case; [from] and [to] are inclusive days.
  List<Expense> find({
    Category? category,
    String? merchant,
    DateTime? from,
    DateTime? to,
  }) {
    final name = merchant?.trim().toLowerCase();
    return [
      for (final e in expenses)
        if ((category == null || e.category == category) &&
            (name == null ||
                name.isEmpty ||
                e.merchant.toLowerCase().contains(name)) &&
            (from == null || !e.date.isBefore(_day(from))) &&
            (to == null || !e.date.isAfter(_day(to))))
          e,
    ];
  }

  /// Total spent in [category] from [from] to [to], inclusive.
  int spent(Category category, {DateTime? from, DateTime? to}) => find(
    category: category,
    from: from,
    to: to,
  ).fold(0, (sum, e) => sum + e.amount);

  /// Adds an expense and returns it.
  Expense add({
    required int amount,
    required Category category,
    required String merchant,
    required DateTime date,
  }) {
    final expense = Expense(
      id: _nextId++,
      date: _day(date),
      amount: amount,
      category: category,
      merchant: merchant,
    );
    _expenses.add(expense);
    _changed(added: {expense.id});
    return expense;
  }

  /// Deletes the expenses with [ids] and returns those it deleted.
  List<Expense> delete(Iterable<int> ids) {
    final wanted = ids.toSet();
    final deleted = _expenses.where((e) => wanted.contains(e.id)).toList();
    _expenses.removeWhere((e) => wanted.contains(e.id));
    if (deleted.isNotEmpty) _changed();
    return deleted;
  }

  /// Sets the monthly budget of [category] and returns the previous one.
  int? setBudget(Category category, int amount) {
    final previous = _budgets[category];
    _budgets[category] = amount;
    _changed(budgeted: {category});
    return previous;
  }

  /// Stops [changes].
  Future<void> close() => _changes.close();

  void _changed({
    Set<int> added = const {},
    Set<Category> budgeted = const {},
  }) {
    lastAdded = added;
    lastBudgeted = budgeted;
    _changes.add(null);
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}
