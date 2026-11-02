import 'package:flutter/material.dart';

import '../ledger.dart';
import 'copilot_panel.dart';
import 'ledger_view.dart';

/// The budget app with its copilot: side by side on a wide window, the
/// copilot under the app on a phone.
class BudgetPage extends StatelessWidget {
  /// Creates the page.
  const BudgetPage({
    super.key,
    required this.ledger,
    required this.today,
    required this.status,
    required this.ask,
    this.onStop,
  });

  /// The app's data.
  final Ledger ledger;

  /// The day whose month the budgets cover.
  final DateTime today;

  /// The model's state: progress while loading, then where it runs.
  final String status;

  /// Sends a request to the copilot, once the model is ready.
  final Ask? ask;

  /// Stops the request being answered.
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final copilot = CopilotPanel(ask: ask, onStop: onStop);
    final app = LedgerView(ledger: ledger, today: today);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  ask == null ? Icons.downloading : Icons.memory,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, size) => size.maxWidth >= 860
            ? Row(
                children: [
                  Expanded(child: app),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 400, child: copilot),
                ],
              )
            : Column(
                children: [
                  Expanded(child: app),
                  const Divider(height: 1),
                  SizedBox(height: size.maxHeight * 0.45, child: copilot),
                ],
              ),
      ),
    );
  }
}
