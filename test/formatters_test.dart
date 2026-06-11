import 'package:flutter_test/flutter_test.dart';
import 'package:trupp_app/utils/formatters.dart';

void main() {
  final dt = DateTime(2026, 6, 11, 9, 5, 7);

  test('fmtTime', () => expect(fmtTime(dt), '09:05:07'));
  test('fmtTimeShort', () => expect(fmtTimeShort(dt), '09:05'));
  test('fmtDate', () => expect(fmtDate(dt), '11.06.2026'));
  test('fmtDateTime', () => expect(fmtDateTime(dt), '11.06.2026 09:05'));
  test('fmtDateTimeShort', () => expect(fmtDateTimeShort(dt), '11.06 09:05'));

  test('fmtTimeFromMs', () {
    expect(fmtTimeFromMs(dt.millisecondsSinceEpoch), '09:05:07');
  });

  test('fmtAlarmTs heute → HH:mm Uhr', () {
    final today = DateTime.now();
    final iso = DateTime(today.year, today.month, today.day, 14, 30)
        .toIso8601String();
    expect(fmtAlarmTs(iso), '14:30 Uhr');
  });

  test('fmtAlarmTs anderer Tag → dd.MM. HH:mm', () {
    expect(fmtAlarmTs('2020-01-02T08:09:00'), '02.01. 08:09');
  });

  test('fmtAlarmTs mit ungültigem Input gibt Rohwert zurück', () {
    expect(fmtAlarmTs('kein-datum'), 'kein-datum');
  });

  test('fmtAlarmTsLong', () {
    expect(fmtAlarmTsLong('2020-01-02T08:09:00'), '02.01.2020  08:09 Uhr');
  });
}
