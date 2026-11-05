import 'models.dart';

String reminderLabel(int minutes) {
  if (minutes == 0) return '开始时';
  final days = minutes ~/ 1440,
      hours = minutes % 1440 ~/ 60,
      mins = minutes % 60;
  return '提前${days > 0 ? '$days天' : ''}${hours > 0 ? '$hours小时' : ''}${mins > 0 ? '$mins分钟' : ''}';
}

String reminderBody(ScheduleEvent event, DateTime now) {
  final remaining = event.start.difference(now);
  final minutes = (remaining.inSeconds / 60).ceil();
  final when = minutes <= 0
      ? '现在开始'
      : minutes >= 1440
      ? '${minutes ~/ 1440}天${minutes % 1440 ~/ 60 > 0 ? '${minutes % 1440 ~/ 60}小时' : ''}后开始'
      : minutes >= 60
      ? '${minutes ~/ 60}小时${minutes % 60 > 0 ? '${minutes % 60}分钟' : ''}后开始'
      : '$minutes分钟后开始';
  final timing = event.isTodo ? when.replaceAll('开始', '截止') : when;
  return '$timing · ${event.isTodo ? '截止' : '开始'}：${dateKey(event.start)} ${event.allDay ? '全天' : clockText(event.start)}${event.notes.isEmpty ? '' : '\n${event.notes}'}';
}

class ReminderRequest {
  final String key;
  final int id;
  final ScheduleEvent event;
  final int offset;
  final DateTime at;
  final bool sound;
  const ReminderRequest(
    this.key,
    this.id,
    this.event,
    this.offset,
    this.at,
    this.sound,
  );
  String get body => reminderBody(event, at);
  DateTime get expires =>
      event.isPoint ? event.start.add(const Duration(minutes: 1)) : event.end;
  String get fingerprint =>
      '$key:${event.title}:$body:$sound:${expires.toUtc().millisecondsSinceEpoch}';
}

String reminderKey(ScheduleEvent event, int offset) =>
    '${event.id}:${event.start.toUtc().millisecondsSinceEpoch}:$offset';

/// Keep the Windows queue bounded and refill while the tray process is running.
/// Hash collisions are resolved against the whole selected queue, deterministically.
List<ReminderRequest> planReminders(
  List<ScheduleEvent> events,
  AppSettings settings,
  DateTime now, {
  int limit = 512,
}) {
  if (!settings.remindersEnabled || !settings.systemNotificationsEnabled) {
    return [];
  }
  final candidates = <(ScheduleEvent, int, DateTime, String)>[];
  final horizon = now.add(const Duration(days: 30));
  for (final e in events.where((e) => !e.completed && !e.deleted)) {
    if (e.isTodo && (!e.hasDeadline || e.todoRepeat != null)) continue;
    for (final offset in e.reminderOffsets) {
      final at = e.start.subtract(Duration(minutes: offset));
      if (e.todoCycleStart != null && at.isBefore(e.todoCycleStart!)) continue;
      if (at.isAfter(now) && !at.isAfter(horizon)) {
        candidates.add((e, offset, at, reminderKey(e, offset)));
      }
    }
  }
  candidates.sort((a, b) {
    final time = a.$3.compareTo(b.$3);
    return time != 0 ? time : a.$4.compareTo(b.$4);
  });
  final ids = <int>{};
  return [
    for (final row in candidates.take(limit))
      () {
        var hash = 0x811c9dc5;
        for (final unit in row.$4.codeUnits) {
          hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
        }
        while (!ids.add(hash)) {
          hash = (hash + 1) & 0x7fffffff;
        }
        return ReminderRequest(
          row.$4,
          hash,
          row.$1,
          row.$2,
          row.$3,
          settings.notificationSound && row.$1.reminderSound,
        );
      }(),
  ];
}
