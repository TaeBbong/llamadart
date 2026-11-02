import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_inbox_example/src/triage.dart';

void main() {
  group('sortScreenshotTool', () {
    Future<Triage?> sort(Map<String, dynamic> arguments) async {
      Triage? sorted;
      final tool = sortScreenshotTool(
        (t) => sorted = t,
        elapsed: () => const Duration(seconds: 2),
      );
      expect(await tool.invoke(arguments), {'status': 'sorted'});
      return sorted;
    }

    test('turns filled follow-ups into actions in order', () async {
      final triage = (await sort({
        'kind': 'coupon',
        'summary': ' 5,000 won off ',
        'event_title': 'Coupon expires',
        'event_date': '2026-11-30',
        'map_place': 'Gangnam Station',
        'copy_label': 'Coupon code',
        'copy_text': 'WINTER5K-82QX',
      }))!;

      expect(triage.kind, ScreenshotKind.coupon);
      expect(triage.summary, '5,000 won off');
      expect(triage.elapsed, const Duration(seconds: 2));
      expect(triage.actions, hasLength(3));
      final event = triage.actions[0] as AddEventAction;
      expect(event.title, 'Coupon expires');
      expect(event.allDay, isTrue);
      expect((triage.actions[1] as OpenMapAction).query, 'Gangnam Station');
      final copy = triage.actions[2] as CopyTextAction;
      expect((copy.label, copy.text), ('Coupon code', 'WINTER5K-82QX'));
    });

    test('searches the map for an event location without a place', () async {
      final triage = (await sort({
        'kind': 'event',
        'summary': 'Meetup',
        'event_title': 'Meetup',
        'event_date': '2026-11-14',
        'event_start_time': '19:00',
        'event_location': 'D2 Startup Factory',
      }))!;

      expect(triage.actions.map((a) => a.runtimeType), [
        AddEventAction,
        OpenMapAction,
      ]);
      expect((triage.actions[1] as OpenMapAction).query, 'D2 Startup Factory');
    });

    test(
      'leaves out blank follow-ups, a bad event and a missing label',
      () async {
        final triage = (await sort({
          'kind': 'delivery',
          'summary': 'Parcel shipped',
          'event_title': 'Arrives',
          'event_date': 'next Wednesday',
          'map_place': '  ',
          'copy_text': '6857 2210 3394',
        }))!;

        expect(triage.actions, hasLength(1));
        expect((triage.actions.single as CopyTextAction).label, 'Text');
      },
    );

    test('files an unknown kind as other', () async {
      final triage = (await sort({'kind': 'poster', 'summary': 'x'}))!;

      expect(triage.kind, ScreenshotKind.other);
      expect(triage.actions, isEmpty);
    });
  });

  group('eventFrom', () {
    test('makes a dated event without a time an all-day event', () {
      final event = eventFrom(title: ' Due ', date: '2026-12-31');

      expect(event.title, 'Due');
      expect(event.allDay, isTrue);
      expect(event.start, DateTime(2026, 12, 31));
      expect(event.end, DateTime(2027));
      expect(event.location, isNull);
    });

    test('ends a timed event at its end time or an hour later', () {
      final withEnd = eventFrom(
        title: 'Talk',
        date: '2026-11-14',
        startTime: '19:00',
        endTime: '21:30',
        location: ' ',
      );
      expect(withEnd.start, DateTime(2026, 11, 14, 19));
      expect(withEnd.end, DateTime(2026, 11, 14, 21, 30));
      expect(withEnd.location, isNull);

      final backwards = eventFrom(
        title: 'Talk',
        date: '2026-11-14',
        startTime: '19:00',
        endTime: '18:00',
      );
      expect(backwards.end, DateTime(2026, 11, 14, 20));
    });

    test('rejects a date or time it cannot read', () {
      expect(
        () => eventFrom(title: 't', date: '14/11/2026'),
        throwsFormatException,
      );
      expect(
        () => eventFrom(title: 't', date: '2026-11-14', startTime: '7 PM'),
        throwsFormatException,
      );
      expect(
        () => eventFrom(title: 't', date: '2026-11-14', startTime: '24:00'),
        throwsFormatException,
      );
    });
  });

  test('triageInstructions gives the date, weekday and language', () {
    final prompt = triageInstructions(DateTime(2026, 11, 2), 'ko-KR');

    expect(prompt, contains('Today is 2026-11-02, a Monday.'));
    expect(prompt, contains("user's language (ko-KR)"));
    expect(prompt, contains('sort_screenshot'));
  });
}
