import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import 'copilot_tools.dart';
import 'ledger.dart';

/// A tool call the copilot made, and its result once the tool returned.
class ToolActivity {
  /// Creates an activity for a call to [name] with [arguments].
  ToolActivity(this.name, this.arguments);

  /// Tool name.
  final String name;

  /// Arguments the model passed.
  final Map<String, dynamic> arguments;

  /// What the tool returned, once it has.
  Object? result;

  /// The call as one line, such as `find_expenses(category: delivery)`.
  String get signature =>
      '$name(${arguments.entries.map((e) => '${e.key}: ${jsonEncode(e.value)}').join(', ')})';
}

/// The copilot's answer to one request.
class CopilotReply {
  /// Creates a reply.
  const CopilotReply({
    required this.text,
    required this.activities,
    required this.stopReason,
  });

  /// The answer.
  final String text;

  /// Tool calls made for it, in order.
  final List<ToolActivity> activities;

  /// Why the tool loop stopped.
  final LlamaToolLoopStopReason stopReason;
}

/// The system prompt for a copilot on [today].
String copilotInstructions(DateTime today) {
  final month = DateTime(today.year, today.month);
  final lastMonth = DateTime(today.year, today.month - 1);
  final lastMonthEnd = DateTime(today.year, today.month, 0);
  return '''
You are the copilot inside a personal budget app. You read and change the user's data only through your tools; never guess a number.

Today is ${formatDay(today)}. This month runs from ${formatDay(month)}; last month ran from ${formatDay(lastMonth)} to ${formatDay(lastMonthEnd)}.
Amounts are whole Korean won. Categories: ${Category.values.map((c) => c.name).join(', ')}.

Find ids with find_expenses before deleting. After a change, say what changed. Answer in one or two short sentences in the user's language, writing amounts like ₩12,000.''';
}

/// A chat with the budget app's data, through [ledgerTools].
class Copilot {
  /// Creates a copilot on [engine] over [ledger]. [confirm] asks the user
  /// before an expense is deleted.
  Copilot(
    LlamaEngine engine,
    Ledger ledger, {
    required Confirm confirm,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _session = ChatSession(engine) {
    _tools = ledgerTools(ledger, today: _now, confirm: confirm);
  }

  final DateTime Function() _now;
  final ChatSession _session;
  late final List<ToolDefinition> _tools;

  /// The engine, to cancel a request.
  LlamaEngine get engine => _session.engine;

  /// Answers [request], calling tools as needed. [onActivity] hears each
  /// call when the model makes it and again when its result is in.
  Future<CopilotReply> ask(
    String request, {
    void Function(ToolActivity activity)? onActivity,
  }) async {
    _session.systemPrompt = copilotInstructions(_now());
    final activities = <ToolActivity>[];
    final byId = <String, ToolActivity>{};
    final result = await _session.sendWithTools(
      request,
      tools: _tools,
      maxRounds: 6,
      enableThinking: false,
      params: const GenerationParams(maxTokens: 512, temp: 0),
      onMessageAdded: (message) {
        for (final part in message.parts) {
          if (part is LlamaToolCallContent) {
            final activity = ToolActivity(part.name, part.arguments);
            activities.add(activity);
            if (part.id case final id?) byId[id] = activity;
            onActivity?.call(activity);
          } else if (part is LlamaToolResultContent) {
            final activity =
                byId[part.id] ??
                activities.lastWhere(
                  (a) => a.name == part.name && a.result == null,
                  orElse: () => ToolActivity(part.name, const {}),
                );
            activity.result = part.result;
            onActivity?.call(activity);
          }
        }
      },
    );
    return CopilotReply(
      text: switch (result.stopReason) {
        LlamaToolLoopStopReason.completed => result.text.trim(),
        LlamaToolLoopStopReason.cancelled => 'Stopped.',
        _ => 'I could not finish that (${result.stopReason.name}).',
      },
      activities: activities,
      stopReason: result.stopReason,
    );
  }

  /// Forgets the conversation.
  void reset() => _session.reset();
}
