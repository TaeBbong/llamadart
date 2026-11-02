import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_inbox_example/src/actions.dart';
import 'package:screenshot_inbox_example/src/triage.dart';

void main() {
  group('calendarFile', () {
    test('writes a timed event in local time with escaped text', () {
      final ics = calendarFile(
        AddEventAction(
          title: 'Meetup; talks, pizza',
          start: DateTime(2026, 11, 14, 19),
          end: DateTime(2026, 11, 14, 21, 30),
          allDay: false,
          location: r'Gangnam\Seoul',
        ),
        stamp: DateTime.utc(2026, 11, 2, 8, 5, 9),
      );

      final lines = ics.split('\r\n');
      expect(lines.first, 'BEGIN:VCALENDAR');
      expect(lines, contains('DTSTAMP:20261102T080509Z'));
      expect(lines, contains('DTSTART:20261114T190000'));
      expect(lines, contains('DTEND:20261114T213000'));
      expect(lines, contains(r'SUMMARY:Meetup\; talks\, pizza'));
      expect(lines, contains(r'LOCATION:Gangnam\\Seoul'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
    });

    test('writes an all-day event as dates, without a location', () {
      final ics = calendarFile(
        AddEventAction(
          title: 'Coupon expires',
          start: DateTime(2026, 11, 30),
          end: DateTime(2026, 12),
          allDay: true,
        ),
        stamp: DateTime.utc(2026, 11, 2),
      );

      expect(ics, contains('DTSTART;VALUE=DATE:20261130\r\n'));
      expect(ics, contains('DTEND;VALUE=DATE:20261201\r\n'));
      expect(ics, isNot(contains('LOCATION')));
    });
  });

  test('mapSearch uses geo: on Android and Apple Maps elsewhere', () {
    expect(
      mapSearch('D2 Startup Factory, Seoul', android: true).toString(),
      'geo:0,0?q=D2%20Startup%20Factory%2C%20Seoul',
    );
    final apple = mapSearch('D2 Startup Factory', android: false);
    expect(apple.host, 'maps.apple.com');
    expect(apple.queryParameters, {'q': 'D2 Startup Factory'});
  });
}
