import 'package:flutter/material.dart';

import '../copilot.dart';

/// Answers a request, reporting each tool call as it happens.
typedef Ask =
    Future<CopilotReply> Function(
      String request, {
      void Function(ToolActivity activity)? onActivity,
    });

/// Requests the panel suggests before the first one.
const List<String> suggestions = [
  'How much did I spend on delivery last month?',
  'Where did I spend the most last month?',
  'Lunch at Kimbap House was ₩9,000 today',
  'Cut my delivery budget by 20%',
  'Was any taxi ride charged twice? Delete the extra one',
];

/// The copilot's chat: requests, the tool calls each one made, and answers.
class CopilotPanel extends StatefulWidget {
  /// Creates the panel. It is disabled while [ask] is null.
  const CopilotPanel({super.key, required this.ask, this.onStop});

  /// Sends a request to the copilot, once the model is ready.
  final Ask? ask;

  /// Stops the request being answered.
  final VoidCallback? onStop;

  @override
  State<CopilotPanel> createState() => _CopilotPanelState();
}

class _Turn {
  _Turn(this.request);

  final String request;
  final List<ToolActivity> activities = [];
  String? answer;
}

class _CopilotPanelState extends State<CopilotPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Turn> _turns = [];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final ask = widget.ask;
    final request = text.trim();
    if (ask == null || _busy || request.isEmpty) return;
    final turn = _Turn(request);
    setState(() {
      _turns.add(turn);
      _busy = true;
      _input.clear();
    });
    try {
      final reply = await ask(
        request,
        onActivity: (activity) {
          if (!mounted) return;
          setState(() {
            if (!turn.activities.contains(activity)) {
              turn.activities.add(activity);
            }
          });
        },
      );
      turn.answer = reply.text;
    } catch (e) {
      turn.answer = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = widget.ask != null;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Copilot', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Asks and changes your budget through the app\'s own '
                        'functions, on this device.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in suggestions)
                            ActionChip(
                              label: Text(s),
                              onPressed: ready ? () => _send(s) : null,
                            ),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _turns.length,
                    itemBuilder: (context, index) =>
                        _TurnView(turn: _turns[_turns.length - 1 - index]),
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: ready && !_busy,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: ready ? 'Ask your budget…' : 'Loading model…',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _busy
                    ? IconButton.outlined(
                        tooltip: 'Stop',
                        onPressed: widget.onStop,
                        icon: const Icon(Icons.stop),
                      )
                    : IconButton.filled(
                        tooltip: 'Send',
                        onPressed: ready ? () => _send(_input.text) : null,
                        icon: const Icon(Icons.arrow_upward),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(turn.request),
            ),
          ),
          for (final activity in turn.activities)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    activity.result == null ? Icons.sync : Icons.build_circle,
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      activity.signature,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (turn.answer case final answer?)
            Text(answer)
          else
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
