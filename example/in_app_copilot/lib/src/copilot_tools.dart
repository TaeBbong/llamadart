import 'package:llamadart/llamadart.dart';

import 'ledger.dart';

/// Asks the user to approve a change described by [question].
typedef Confirm = Future<bool> Function(String question);

/// The app's own functions, as tools the copilot can call. Reads and small
/// edits run at once; deleting expenses waits for [confirm].
///
/// Bad arguments throw, and the tool loop hands the message back to the
/// model so it can retry. Categories are strings checked here rather than
/// schema enums, because a value outside an enum fails the whole call before
/// the model sees why.
List<ToolDefinition> ledgerTools(
  Ledger ledger, {
  required DateTime Function() today,
  required Confirm confirm,
}) {
  final categories = Category.values.map((c) => c.name).join(', ');
  return [
    ToolDefinition(
      name: 'find_expenses',
      description:
          'Lists expenses matching every filter given, newest first, with '
          'their ids and total.',
      parameters: [
        ToolParam.string('category', description: categories),
        ToolParam.string('merchant', description: 'Part of a merchant name.'),
        ToolParam.string('from', description: 'First day, YYYY-MM-DD.'),
        ToolParam.string('to', description: 'Last day, YYYY-MM-DD.'),
      ],
      handler: (params) async {
        final category = _category(params.getString('category'));
        final merchant = params.getString('merchant');
        final from = _date(params.getString('from'));
        final to = _date(params.getString('to'));
        final found = ledger.find(
          category: category,
          merchant: merchant,
          from: from,
          to: to,
        );
        // A request in one language can name a merchant stored in another
        // ("택시" for "Taxi"); the names let the model retry.
        final merchants = found.isEmpty && merchant != null
            ? {
                for (final e in ledger.find(
                  category: category,
                  from: from,
                  to: to,
                ))
                  e.merchant,
              }
            : const <String>{};
        const shown = 25;
        return {
          'count': found.length,
          'total': found.fold(0, (sum, e) => sum + e.amount),
          'expenses': [for (final e in found.take(shown)) e.toJson()],
          if (found.length > shown) 'note': 'Only the newest $shown listed.',
          if (merchants.isNotEmpty)
            'note':
                'No merchant name contains "$merchant". Merchants with the '
                'other filters: ${merchants.join(', ')}.',
        };
      },
    ),
    ToolDefinition(
      name: 'spending_summary',
      description:
          'Totals spending between two days, grouped by category, merchant '
          'or day, largest first. Defaults to this month.',
      parameters: [
        ToolParam.string('from', description: 'First day, YYYY-MM-DD.'),
        ToolParam.string('to', description: 'Last day, YYYY-MM-DD.'),
        ToolParam.string(
          'group_by',
          description: 'category, merchant or day. Defaults to category.',
        ),
      ],
      handler: (params) async {
        final now = today();
        final from = _date(params.getString('from')) ?? _monthStart(now);
        final to = _date(params.getString('to')) ?? now;
        final groupBy = params.getString('group_by') ?? 'category';
        final key = switch (groupBy) {
          'category' => (Expense e) => e.category.name,
          'merchant' => (Expense e) => e.merchant,
          'day' => (Expense e) => formatDay(e.date),
          _ => throw ArgumentError(
            'group_by must be category, merchant or day, not "$groupBy".',
          ),
        };
        final groups = <String, (int, int)>{};
        var total = 0;
        for (final e in ledger.find(from: from, to: to)) {
          final (sum, count) = groups[key(e)] ?? (0, 0);
          groups[key(e)] = (sum + e.amount, count + 1);
          total += e.amount;
        }
        final sorted = groups.entries.toList()
          ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
        return {
          'from': formatDay(from),
          'to': formatDay(to),
          'total': total,
          'groups': [
            for (final g in sorted)
              {'name': g.key, 'total': g.value.$1, 'count': g.value.$2},
          ],
        };
      },
    ),
    ToolDefinition(
      name: 'budget_status',
      description:
          'Shows each category\'s monthly budget, what was spent this month '
          'and what is left.',
      parameters: const [],
      handler: (params) async {
        final now = today();
        return {
          'month': formatDay(_monthStart(now)).substring(0, 7),
          'categories': [
            for (final MapEntry(key: c, value: budget)
                in ledger.budgets.entries)
              () {
                final spent = ledger.spent(c, from: _monthStart(now), to: now);
                return {
                  'category': c.name,
                  'budget': budget,
                  'spent': spent,
                  'left': budget - spent,
                  'over_budget': spent > budget,
                };
              }(),
          ],
        };
      },
    ),
    ToolDefinition(
      name: 'add_expense',
      description: 'Records an expense.',
      parameters: [
        ToolParam.integer('amount', description: 'Whole won.', required: true),
        ToolParam.string('category', description: categories, required: true),
        ToolParam.string('merchant', required: true),
        ToolParam.string('date', description: 'YYYY-MM-DD. Defaults to today.'),
      ],
      handler: (params) async {
        final amount = params.getRequiredInt('amount');
        if (amount <= 0) throw ArgumentError('amount must be positive.');
        final expense = ledger.add(
          amount: amount,
          category: _category(params.getRequiredString('category'))!,
          merchant: params.getRequiredString('merchant').trim(),
          date: _date(params.getString('date')) ?? today(),
        );
        return {'added': expense.toJson()};
      },
    ),
    ToolDefinition(
      name: 'set_budget',
      description: 'Sets the monthly budget of a category.',
      parameters: [
        ToolParam.string('category', description: categories, required: true),
        ToolParam.integer('amount', description: 'Whole won.', required: true),
      ],
      handler: (params) async {
        final category = _category(params.getRequiredString('category'))!;
        final amount = params.getRequiredInt('amount');
        if (amount < 0) throw ArgumentError('amount cannot be negative.');
        final previous = ledger.setBudget(category, amount);
        return {
          'category': category.name,
          'previous': previous,
          'budget': amount,
        };
      },
    ),
    ToolDefinition(
      name: 'delete_expenses',
      description:
          'Deletes expenses by id after the user approves. Find the ids '
          'first.',
      parameters: [
        ToolParam.array(
          'ids',
          itemType: ToolParam.integer('id'),
          required: true,
        ),
      ],
      handler: (params) async {
        final ids = params.getRequiredList<Object?>('ids').whereType<int>();
        final wanted = ids.toSet();
        final matches = [
          for (final e in ledger.expenses)
            if (wanted.contains(e.id)) e,
        ];
        if (matches.isEmpty) {
          throw ArgumentError('No expense has the ids ${wanted.join(', ')}.');
        }
        final question = [
          'Delete ${matches.length} expense${matches.length == 1 ? '' : 's'}?',
          for (final e in matches)
            '${formatDay(e.date)}  ${e.merchant}  ${won(e.amount)}',
        ].join('\n');
        if (!await confirm(question)) {
          return {'deleted': 0, 'note': 'The user declined.'};
        }
        return {
          'deleted': [for (final e in ledger.delete(wanted)) e.id],
        };
      },
    ),
  ];
}

Category? _category(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  return Category.parse(name) ??
      (throw ArgumentError(
        'Unknown category "$name". Use one of '
        '${Category.values.map((c) => c.name).join(', ')}.',
      ));
}

DateTime? _date(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (m == null) throw FormatException('Dates are YYYY-MM-DD, not "$value".');
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

DateTime _monthStart(DateTime day) => DateTime(day.year, day.month);
