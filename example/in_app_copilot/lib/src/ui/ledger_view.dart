import 'dart:async';

import 'package:flutter/material.dart';

import '../ledger.dart';

/// The budget app itself: this month's budgets and the newest expenses,
/// rebuilt on every ledger change with the changed rows lit up.
class LedgerView extends StatefulWidget {
  /// Creates the view of [ledger] as of [today].
  const LedgerView({super.key, required this.ledger, required this.today});

  /// The app's data.
  final Ledger ledger;

  /// The day whose month the budgets cover.
  final DateTime today;

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  late final StreamSubscription<void> _changes;
  Timer? _fade;
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.ledger.changes.listen((_) {
      _fade?.cancel();
      _fade = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _lit = false);
      });
      setState(() => _lit = true);
    });
  }

  @override
  void dispose() {
    _fade?.cancel();
    unawaited(_changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = widget.ledger;
    final monthStart = DateTime(widget.today.year, widget.today.month);
    final highlight = theme.colorScheme.tertiaryContainer;
    final budgets = ledger.budgets;
    final spent = {
      for (final c in budgets.keys)
        c: ledger.spent(c, from: monthStart, to: widget.today),
    };
    final total = spent.values.fold(0, (a, b) => a + b);
    final budgeted = budgets.values.fold(0, (a, b) => a + b);
    final recent = ledger.expenses.take(40).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spent this month', style: theme.textTheme.labelLarge),
                Text(won(total), style: theme.textTheme.headlineMedium),
                Text(
                  'of ${won(budgeted)} budgeted',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SliverList.list(
          children: [
            for (final MapEntry(key: category, value: budget)
                in budgets.entries)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                color: _lit && ledger.lastBudgeted.contains(category)
                    ? highlight
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: _BudgetRow(
                  category: category,
                  spent: spent[category]!,
                  budget: budget,
                ),
              ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text('Recent', style: theme.textTheme.titleSmall),
          ),
        ),
        SliverList.builder(
          itemCount: recent.length,
          itemBuilder: (context, index) {
            final e = recent[index];
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              color: _lit && ledger.lastAdded.contains(e.id)
                  ? highlight
                  : Colors.transparent,
              child: ListTile(
                dense: true,
                title: Text(e.merchant),
                subtitle: Text('${formatDay(e.date)} · ${e.category.title}'),
                trailing: Text(won(e.amount)),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.category,
    required this.spent,
    required this.budget,
  });

  final Category category;
  final int spent;
  final int budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = spent > budget;
    final fraction = budget == 0 ? 1.0 : (spent / budget).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(category.title)),
            Text(
              '${won(spent)} / ${won(budget)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: over ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: over ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}
