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
  bool requireAny = true,
}) {
  final rule = template.recurrence!;
  rule.validate(template.start, allDay: template.allDay);
  if (rule.kind == RepeatKind.cycle) {
    return _expandCycle(template, calendar, validate: validate);
  }
  if (rule.nodes.isNotEmpty) {
    return _expandNodeEvents(template, calendar, validate: validate);
  }
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
    final cycleIndex = switch (rule.frequency) {
      RepeatFrequency.daily => offset,
      RepeatFrequency.interval => offset ~/ rule.intervalDays,
      RepeatFrequency.weekly => (offset + first.weekday - 1) ~/ 7,
      RepeatFrequency.monthly =>
        (day.year - first.year) * 12 + day.month - first.month,
    };
    if (rule.cycleCount != null && cycleIndex >= rule.cycleCount!) break;
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
        final allowed = calendar.allowsDate(
          start,
          rule.holidayPolicy,
          rule.weekendHolidayPriority,
        );
        if (allowed == null) {
          if (validate) {
            throw FormatException('${start.year}年节假日未收录，请缩短重复范围或选择无视节假日');
          }
          continue;
        }
        if (!allowed) continue;
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
  if (validate && requireAny && rows.isEmpty) {
    throw const FormatException('此规则没有匹配的日程，请调整日期或节假日选项');
  }
  return rows;
}

List<ScheduleEvent> _expandCycle(
  ScheduleEvent template,
  CalendarService calendar, {
  required bool validate,
}) {
  final rule = template.recurrence!;
  final first = dayOnly(
    template.start.subtract(Duration(minutes: rule.shiftMinutes)),
  );
  var anchor = rule.frequency == RepeatFrequency.monthly
      ? DateTime(first.year, first.month)
      : rule.frequency == RepeatFrequency.weekly && rule.weekLabels
      ? DateTime(first.year, first.month, first.day - first.weekday + 1)
      : first;
  final rows = <ScheduleEvent>[];
  for (
    var cycle = 0;
    !anchor.isAfter(rule.until) &&
        (rule.cycleCount == null || cycle < rule.cycleCount!);
    cycle++
  ) {
    for (final node in rule.nodes) {
      final base = DateTime(
        anchor.year,
        anchor.month,
        anchor.day + node.dayOffset,
        0,
        node.minute,
      );
      if (rule.frequency == RepeatFrequency.monthly &&
          base.month != anchor.month) {
        continue;
      }
      if (base.isBefore(first) || dayOnly(base).isAfter(rule.until)) continue;
      final start = base.add(Duration(minutes: rule.shiftMinutes));
      final allowed = calendar.allowsDate(
        start,
        node.holidayPolicy,
        node.weekendHolidayPriority,
      );
      if (allowed == null) {
        if (validate) {
          throw FormatException('${start.year}年节假日未收录，请调整节点节假日设置或结束范围');
        }
        continue;
      }
      if (!allowed) continue;
      final end = node.allDay
          ? DateTime(
              start.year,
              start.month,
              start.day + node.durationMinutes ~/ 1440,
            )
          : start.add(Duration(minutes: node.durationMinutes));
      if (start.year < 1901 || end.year > 2099) {
        throw const FormatException('节点结束日期需在2099年内');
      }
      final key = node.legacyMinute != null
          ? '${dateKey(base)}T${pad2(node.legacyMinute! ~/ 60)}${pad2(node.legacyMinute! % 60)}'
          : '${dateKey(anchor)}T0000~${node.id}';
      rows.add(
        ScheduleEvent(
          id: occurrenceId(template.id, key),
          title: node.title.trim().isEmpty
              ? template.title
              : '${template.title}-${node.title}',
          notes: [
            node.notes,
            template.notes,
          ].where((s) => s.isNotEmpty).join('\n'),
          start: start,
          end: end,
          allDay: node.allDay,
          reminderOffsets: node.reminderOffsets,
          reminderSound: node.reminderSound,
          updatedAt: template.updatedAt,
          revision: template.revision,
          seriesId: template.id,
          occurrenceKey: key,
          nodeId: node.id,
          color: node.color,
          completedColor: node.completedColor,
        ),
      );
      if (rows.length > maxSeriesOccurrences) {
        throw const FormatException('展开超过10000项，请缩短范围或减少节点');
      }
    }
    anchor = rule.frequency == RepeatFrequency.monthly
        ? DateTime(anchor.year, anchor.month + 1)
        : DateTime(anchor.year, anchor.month, anchor.day + rule.periodDays);
  }
  if (validate && rows.isEmpty) {
    throw const FormatException('周期中没有匹配的节点，请检查日期和节假日设置');
  }
  return rows;
}

List<ScheduleEvent> _expandNodeEvents(
  ScheduleEvent root,
  CalendarService calendar, {
  required bool validate,
}) {
  final rule = root.recurrence!;
  final rows = <ScheduleEvent>[];
  final shift = Duration(minutes: rule.shiftMinutes);
  final base = dayOnly(root.start.subtract(shift));
  for (final node in rule.nodes) {
    node.validate(
      rule.periodDays,
      monthly: rule.frequency == RepeatFrequency.monthly,
    );
    final start = DateTime(
      base.year,
      base.month,
      base.day,
      0,
      node.minute,
    ).add(shift);
    final items = expandSeries(
      ScheduleEvent(
        id: root.id,
        title: node.title.isEmpty ? root.title : '${root.title}-${node.title}',
        notes: [node.notes, root.notes].where((s) => s.isNotEmpty).join('\n'),
        start: start,
        end: start.add(Duration(minutes: node.durationMinutes)),
        allDay: node.allDay,
        updatedAt: root.updatedAt,
        revision: root.revision,
        reminderOffsets: node.reminderOffsets,
        reminderSound: node.reminderSound,
        color: node.color,
        completedColor: node.completedColor,
        recurrence: RecurrenceRule(
          frequency: rule.frequency,
          until: rule.until,
          intervalDays: rule.intervalDays,
          weekdays: rule.weekdays,
          monthDays: rule.monthDays,
          minutes: [node.minute],
          holidayPolicy: node.holidayPolicy,
          weekendHolidayPriority: node.weekendHolidayPriority,
          shiftMinutes: rule.shiftMinutes,
          cycleCount: rule.cycleCount,
        ),
      ),
      calendar,
      validate: validate,
      requireAny: false,
    );
    for (final item in items) {
      final key = node.legacyMinute != null
          ? '${dateKey(item.start.subtract(shift))}T${pad2(node.legacyMinute! ~/ 60)}${pad2(node.legacyMinute! % 60)}'
          : '${dateKey(item.start.subtract(shift))}T0000~${node.id}';
      rows.add(
        ScheduleEvent(
          id: occurrenceId(root.id, key),
          title: item.title,
          notes: item.notes,
          start: item.start,
          end: item.end,
          allDay: item.allDay,
          updatedAt: item.updatedAt,
          revision: item.revision,
          reminderOffsets: item.reminderOffsets,
          reminderSound: item.reminderSound,
          color: item.color,
          completedColor: item.completedColor,
          seriesId: root.id,
          occurrenceKey: key,
          nodeId: node.id,
        ),
      );
    }
    if (rows.length > maxSeriesOccurrences) {
      throw const FormatException('展开超过10000项，请缩短重复范围');
    }
  }
  if (validate && rows.isEmpty) {
    throw const FormatException('没有匹配的重复节点，请调整日期或节假日设置');
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
