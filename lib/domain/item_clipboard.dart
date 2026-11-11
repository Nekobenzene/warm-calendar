import 'models.dart';

RecurrenceNode clipboardNode(
  ScheduleEvent draft, {
  int day = 0,
  int periodDays = 1,
}) {
  final duration = draft.end.difference(draft.start).inMinutes;
  final validDuration = duration >= 0 && duration <= periodDays * 1440;
  return RecurrenceNode(
    id: 'node-${DateTime.now().microsecondsSinceEpoch}',
    pasteDraftId: draft.id,
    title: draft.title,
    notes: draft.notes,
    dayOffset: day,
    minute: draft.allDay ? 0 : draft.start.hour * 60 + draft.start.minute,
    durationMinutes: validDuration ? duration : (draft.allDay ? 1440 : 60),
    allDay: draft.allDay,
    color: draft.color,
    completedColor: draft.completedColor,
    reminderOffsets: draft.reminderOffsets,
    reminderSound: draft.reminderSound,
    automation: draft.automation.copyWith(deleteExpired: false),
  );
}

class ItemClipboardEntry {
  final ScheduleEvent item;
  final bool cut;
  const ItemClipboardEntry(this.item, {this.cut = false});
}

/// Copying a task never replaces the independent schedule clipboard.
class ItemClipboard {
  ItemClipboardEntry? schedule, todo;
  ItemClipboardEntry? entry(bool isTodo) => isTodo ? todo : schedule;
  void put(ScheduleEvent item, {bool cut = false}) {
    if (item.isTodo) {
      todo = ItemClipboardEntry(item, cut: cut);
    } else {
      schedule = ItemClipboardEntry(item, cut: cut);
    }
  }

  ScheduleEvent? draft(
    bool isTodo,
    DateTime now, {
    DateTime? date,
    int todoOrder = 0,
  }) {
    final source = entry(isTodo)?.item;
    if (source == null) return null;
    final start = date == null
        ? source.start
        : DateTime(
            date.year,
            date.month,
            date.day,
            source.start.hour,
            source.start.minute,
          );
    return ScheduleEvent(
      id: 'paste-${DateTime.now().microsecondsSinceEpoch}',
      isTodo: isTodo,
      hasDeadline: isTodo && source.hasDeadline,
      taskCreatedAt: isTodo ? now.toUtc() : null,
      todoOrder: todoOrder,
      title: source.title.substring(0, source.title.length.clamp(0, 120)),
      notes: source.notes.substring(0, source.notes.length.clamp(0, 4000)),
      start: start,
      end: isTodo ? start : start.add(source.end.difference(source.start)),
      allDay: !isTodo && source.allDay,
      color: source.color,
      completedColor: source.completedColor,
      reminderOffsets: source.reminderOffsets,
      reminderSound: source.reminderSound,
      automation: source.automation.copyWith(
        deleteExpired:
            source.seriesId == null &&
                source.recurrence == null &&
                source.todoRepeat == null
            ? source.automation.deleteExpired
            : false,
      ),
      updatedAt: now.toUtc(),
    );
  }
}
