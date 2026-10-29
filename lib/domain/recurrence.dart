import 'calendar_service.dart';
import 'models.dart';

const maxSeriesOccurrences = 10000;

String occurrenceId(String seriesId, String key) => '$seriesId::$key';

/// Rules stay in one record; only individually handled instances are persisted.
/// Calendar dates are advanced by components, never by 24h across DST changes.
List<ScheduleEvent> expandSeries(
  ScheduleEvent template,
  CalendarService calendar, {
  bool validate = false,
}) {
  final rule = template.recurrence!;
  rule.validate(template.start, allDay: template.allDay);
  final shift = Duration(minutes: rule.shiftMinutes);
  final baseStart = template.start.subtract(shift);
  final first = dayOnly(baseStart);
  final duration = template.end.difference(template.start);
  final baseEnd = template.end.subtract(shift);
  final daySpan = DateTime.utc(
    baseEnd.year,
    baseEnd.month,
    baseEnd.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
  final rows = <ScheduleEvent>[];
  var offset = 0;
  for (
    var day = first;
    !day.isAfter(rule.until);
    day = DateTime(day.year, day.month, day.day + 1), offset++
  ) {
    final matches = switch (rule.frequency) {
      RepeatFrequency.daily => true,
      RepeatFrequency.weekly => rule.weekdays.contains(day.weekday),
      RepeatFrequency.monthly => rule.monthDays.contains(day.day),
      RepeatFrequency.interval => offset % rule.intervalDays == 0,
    };
    if (!matches) continue;
    for (final minute in [...rule.minutes]..sort()) {
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      ).add(shift);
      if (start.isBefore(template.start)) continue;
      if (rule.holidayPolicy != HolidayPolicy.ignore) {
        final rest = calendar.isRestDay(start);
        if (rest == null) {
          if (validate) {
            throw FormatException('${start.year}年节假日未收录，请缩短重复范围或选择无视节假日');
          }
          continue;
        }
        if (rule.holidayPolicy == HolidayPolicy.skip ? rest : !rest) continue;
      }
      final end = template.allDay
          ? DateTime(day.year, day.month, day.day + daySpan).add(shift)
          : start.add(duration);
      if (start.year < 1901 || end.year > 2099) {
        throw const FormatException('重复日程的结束时间需在2099年内');
      }
      final key = '${dateKey(day)}T${pad2(minute ~/ 60)}${pad2(minute % 60)}';
      rows.add(
        ScheduleEvent(
          id: occurrenceId(template.id, key),
          title: template.title,
          notes: template.notes,
          start: start,
          end: end,
          allDay: template.allDay,
          reminderMinutes: template.reminderMinutes,
          reminderOffsets: template.reminderOffsets,
          reminderSound: template.reminderSound,
          updatedAt: template.updatedAt,
          revision: template.revision,
          seriesId: template.id,
          occurrenceKey: key,
          color: template.color,
          completedColor: template.completedColor,
        ),
      );
      if (rows.length > maxSeriesOccurrences) {
        throw const FormatException('重复次数超过10000，请缩短范围或减少每日时间点');
      }
    }
  }
  if (validate && rows.isEmpty) {
    throw const FormatException('此规则没有匹配的日程，请调整日期或节假日选项');
  }
  return rows;
}

List<ScheduleEvent> resolveEvents(
  List<ScheduleEvent> records,
  CalendarService calendar,
) {
  final roots = {
    for (final e in records.where((e) => e.recurrence != null)) e.id: e,
  };
  final exceptions = {
    for (final e in records.where((e) => e.seriesId != null)) e.id: e,
  };
  final result = <ScheduleEvent>[
    ...records.where(
      (e) => !e.deleted && e.recurrence == null && e.seriesId == null,
    ),
  ];
  for (final root in roots.values.where((e) => !e.deleted)) {
    final instances = {for (final e in expandSeries(root, calendar)) e.id: e};
    // Keep handled history and moved instances when the series rule changes.
    instances.addAll(
      Map.fromEntries(
        exceptions.entries.where((e) => e.value.seriesId == root.id),
      ),
    );
    result.addAll(instances.values.where((e) => !e.deleted));
  }
  return result..sort((a, b) {
    final order = a.start.compareTo(b.start);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
}
