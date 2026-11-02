import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

/// Long edge, in pixels, of the image the model reads. At 768 the 4B model
/// misread coupon codes; larger images barely change the time per
/// screenshot.
const int previewEdge = 1024;

/// What a screenshot mostly shows.
enum ScreenshotKind {
  event('Event'),
  coupon('Coupon'),
  place('Place'),
  ticket('Ticket'),
  delivery('Delivery'),
  receipt('Receipt'),
  shopping('Shopping'),
  chat('Chat'),
  article('Article'),
  meme('Meme'),
  other('Other');

  const ScreenshotKind(this.title);

  /// Name shown on the screenshot's card.
  final String title;
}

/// A follow-up the agent proposes for a screenshot. The app runs it only
/// when the user taps it.
sealed class InboxAction {
  const InboxAction();
}

/// Adds an event to the calendar.
final class AddEventAction extends InboxAction {
  /// Creates an event from [start] to [end], or a whole day when [allDay].
  const AddEventAction({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
  });

  /// Event title.
  final String title;

  /// Start, local time. Midnight for an all-day event.
  final DateTime start;

  /// End, local time. The next midnight for an all-day event.
  final DateTime end;

  /// Whether the event has no time of day.
  final bool allDay;

  /// Where it takes place, as written in the screenshot.
  final String? location;
}

/// Searches for a place in the maps app.
final class OpenMapAction extends InboxAction {
  /// Creates a search for [query].
  const OpenMapAction(this.query);

  /// Place name or address.
  final String query;
}

/// Copies a code or number to the clipboard.
final class CopyTextAction extends InboxAction {
  /// Creates an action that copies [text], shown as [label].
  const CopyTextAction({required this.label, required this.text});

  /// What the text is, such as `Coupon code`.
  final String label;

  /// The exact text.
  final String text;
}

/// What the agent made of one screenshot.
class Triage {
  /// Creates a triage.
  const Triage({
    required this.kind,
    required this.summary,
    required this.actions,
    required this.elapsed,
  });

  /// What the screenshot shows.
  final ScreenshotKind kind;

  /// One line about it.
  final String summary;

  /// Proposed follow-ups, in the order the model proposed them.
  final List<InboxAction> actions;

  /// How long the model took.
  final Duration elapsed;
}

/// The tool the agent sorts a screenshot with: a kind, a summary and at
/// most one of each follow-up, all in one call. [onSorted] receives them.
///
/// One call does it all because a round after a tool result would evaluate
/// the whole prompt, image included, again on Qwen3.5, whose recurrent
/// layers cannot reuse part of a cached prompt, and the small Qwen3.5
/// models make one call per reply.
ToolDefinition sortScreenshotTool(
  void Function(Triage triage) onSorted, {
  Duration Function()? elapsed,
}) => ToolDefinition(
  name: 'sort_screenshot',
  description:
      'Files the screenshot and proposes follow-ups the user can run with '
      'one tap. Leave out every follow-up the screenshot does not clearly '
      'call for.',
  parameters: [
    ToolParam.enumType(
      'kind',
      values: [for (final k in ScreenshotKind.values) k.name],
      required: true,
    ),
    ToolParam.string(
      'summary',
      description: 'What the screenshot is about, at most 12 words.',
      required: true,
    ),
    ToolParam.string(
      'event_title',
      description:
          'For a dated event, appointment, reservation, delivery, deadline '
          'or coupon expiry: a calendar event title.',
    ),
    ToolParam.string('event_date', description: 'YYYY-MM-DD.'),
    ToolParam.string(
      'event_start_time',
      description: 'HH:MM, 24-hour. Leave out for an all-day event.',
    ),
    ToolParam.string('event_end_time', description: 'HH:MM, 24-hour.'),
    ToolParam.string('event_location'),
    ToolParam.string(
      'map_place',
      description:
          'For a specific place or address: its name and address as '
          'written, to search in the maps app.',
    ),
    ToolParam.string(
      'copy_label',
      description: 'What copy_text is, such as "Coupon code".',
    ),
    ToolParam.string(
      'copy_text',
      description:
          'A coupon code, booking number, tracking number or account number '
          'exactly as written, to copy. Never ordinary words.',
    ),
  ],
  handler: (params) async {
    String? text(String name) {
      final value = params.getString(name)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final kindName = params.getRequiredString('kind');
    final actions = <InboxAction>[];
    final eventTitle = text('event_title'), eventDate = text('event_date');
    if (eventTitle != null && eventDate != null) {
      try {
        actions.add(
          eventFrom(
            title: eventTitle,
            date: eventDate,
            startTime: text('event_start_time'),
            endTime: text('event_end_time'),
            location: text('event_location'),
          ),
        );
      } on FormatException {
        // An event the calendar cannot take is left out.
      }
    }
    // An event's location is worth a map search when the model gave none.
    final place =
        text('map_place') ??
        actions.whereType<AddEventAction>().firstOrNull?.location;
    if (place != null) actions.add(OpenMapAction(place));
    if (text('copy_text') case final copy?) {
      actions.add(
        CopyTextAction(label: text('copy_label') ?? 'Text', text: copy),
      );
    }
    onSorted(
      Triage(
        kind: ScreenshotKind.values.firstWhere(
          (k) => k.name == kindName,
          orElse: () => ScreenshotKind.other,
        ),
        summary: params.getRequiredString('summary').trim(),
        actions: actions,
        elapsed: elapsed?.call() ?? Duration.zero,
      ),
    );
    return const {'status': 'sorted'};
  },
);

/// An [AddEventAction] from the model's strings. A bad date or time throws
/// [FormatException].
AddEventAction eventFrom({
  required String title,
  required String date,
  String? startTime,
  String? endTime,
  String? location,
}) {
  final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.trim());
  if (day == null) {
    throw FormatException('date must be YYYY-MM-DD', date);
  }
  final midnight = DateTime(
    int.parse(day[1]!),
    int.parse(day[2]!),
    int.parse(day[3]!),
  );
  (int, int)? clock(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    final (h, min) = m == null ? (99, 0) : (int.parse(m[1]!), int.parse(m[2]!));
    if (h > 23 || min > 59) {
      throw FormatException('times must be HH:MM, 24-hour', value);
    }
    return (h, min);
  }

  final place = location?.trim();
  final start = clock(startTime);
  if (start == null) {
    return AddEventAction(
      title: title.trim(),
      start: midnight,
      end: DateTime(midnight.year, midnight.month, midnight.day + 1),
      allDay: true,
      location: place == null || place.isEmpty ? null : place,
    );
  }
  final from = midnight.copyWith(hour: start.$1, minute: start.$2);
  final end = clock(endTime);
  final to = end == null
      ? from.add(const Duration(hours: 1))
      : midnight.copyWith(hour: end.$1, minute: end.$2);
  return AddEventAction(
    title: title.trim(),
    start: from,
    end: to.isAfter(from) ? to : from.add(const Duration(hours: 1)),
    allDay: false,
    location: place == null || place.isEmpty ? null : place,
  );
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The system prompt for a screenshot taken around [today], with summaries
/// and titles in [language], a BCP 47 tag such as `ko-KR`.
String triageInstructions(DateTime today, String language) {
  final date =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  return '''
You sort the user's phone screenshots. Today is $date, a ${_weekdays[today.weekday - 1]}.

Call sort_screenshot once for the screenshot you are given. Fill a follow-up only when the screenshot clearly calls for it:
- an event for a dated event, appointment, reservation, delivery, deadline or coupon expiry
- a map place for a specific place or address
- a copy text for a coupon code, booking number, tracking number or account number
A meme or a chat usually needs none.

Work out dates relative to today; a date without a year is its next occurrence. Copy names, places and codes exactly as written. Write summaries and titles in the user's language ($language).''';
}

/// Sorts screenshots with a vision model that calls [sortScreenshotTool].
class ScreenshotTriager {
  /// Creates a triager on [engine], which must have a projector loaded.
  ScreenshotTriager(
    this._engine, {
    this.language = 'en',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LlamaEngine _engine;
  final DateTime Function() _now;

  /// BCP 47 tag of the language for summaries and titles.
  final String language;

  /// Sorts one screenshot, sent as encoded JPEG or PNG [image] bytes. The
  /// model must call [sortScreenshotTool]; without a call the screenshot is
  /// [ScreenshotKind.other] with the model's reply as its summary.
  Future<Triage> triage(Uint8List image) async {
    final stopwatch = Stopwatch()..start();
    Triage? sorted;
    final tool = sortScreenshotTool(
      (t) => sorted = t,
      elapsed: () => stopwatch.elapsed,
    );
    final reply = await _engine.complete(
      [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: triageInstructions(_now(), language),
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(bytes: image),
            const LlamaTextContent('Sort this screenshot.'),
          ],
        ),
      ],
      tools: [tool],
      toolChoice: ToolChoice.required,
      enableThinking: false,
      params: const GenerationParams(maxTokens: 512, temp: 0),
    );
    if (reply.toolCalls.firstOrNull case final call?) {
      try {
        await tool.invoke(call.arguments);
      } on Exception {
        // Arguments the tool rejects leave the screenshot unsorted.
      }
    }
    return sorted ??
        Triage(
          kind: ScreenshotKind.other,
          summary: reply.text.trim(),
          actions: const [],
          elapsed: stopwatch.elapsed,
        );
  }
}
