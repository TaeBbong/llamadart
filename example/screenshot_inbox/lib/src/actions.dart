import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'triage.dart';

/// Runs [action] through the platform's own UI: the system sheet for a new
/// calendar event (on macOS, Calendar's import of an `.ics` file), the maps
/// app, or the clipboard. Returns whether it ran.
Future<bool> runAction(InboxAction action) async {
  switch (action) {
    case AddEventAction():
      if (Platform.isMacOS) {
        final dir = await Directory.systemTemp.createTemp('inbox');
        final file = File('${dir.path}/event.ics');
        await file.writeAsString(calendarFile(action, stamp: DateTime.now()));
        return launchUrl(Uri.file(file.path));
      }
      return Add2Calendar.addEvent2Cal(
        Event(
          title: action.title,
          location: action.location,
          startDate: action.start,
          endDate: action.end,
          allDay: action.allDay,
        ),
      );
    case OpenMapAction(:final query):
      return launchUrl(
        mapSearch(query, android: Platform.isAndroid),
        mode: LaunchMode.externalApplication,
      );
    case CopyTextAction(:final text):
      await Clipboard.setData(ClipboardData(text: text));
      return true;
  }
}

/// A maps search for [query]: a `geo:` link on Android, which opens any
/// installed maps app, and Apple Maps elsewhere.
Uri mapSearch(String query, {required bool android}) => android
    ? Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}')
    : Uri.https('maps.apple.com', '/', {'q': query});

/// An iCalendar file with [event] in local time, stamped [stamp].
String calendarFile(AddEventAction event, {required DateTime stamp}) {
  String two(int n) => n.toString().padLeft(2, '0');
  String day(DateTime t) => '${t.year}${two(t.month)}${two(t.day)}';
  String time(DateTime t) =>
      '${day(t)}T${two(t.hour)}${two(t.minute)}${two(t.second)}';
  String text(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');
  final utc = stamp.toUtc();
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//llamadart//Screenshot Inbox//EN',
    'BEGIN:VEVENT',
    'UID:${utc.microsecondsSinceEpoch}@screenshot-inbox',
    'DTSTAMP:${time(utc)}Z',
    if (event.allDay) ...[
      'DTSTART;VALUE=DATE:${day(event.start)}',
      'DTEND;VALUE=DATE:${day(event.end)}',
    ] else ...[
      'DTSTART:${time(event.start)}',
      'DTEND:${time(event.end)}',
    ],
    'SUMMARY:${text(event.title)}',
    if (event.location case final location?) 'LOCATION:${text(location)}',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}
