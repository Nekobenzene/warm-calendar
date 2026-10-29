import 'models.dart';

ScheduleEvent? nextScheduledEvent(
  Iterable<ScheduleEvent> events,
  DateTime now,
) {
  ScheduleEvent? next;
  for (final event in events) {
    if (event.deleted || event.completed || !event.start.isAfter(now)) continue;
    if (next == null || event.start.isBefore(next.start)) next = event;
  }
  return next;
}

String countdownText(DateTime start, DateTime now) {
  final milliseconds = start.difference(now).inMilliseconds;
  final seconds = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  final days = seconds ~/ 86400;
  final clock =
      '${pad2(seconds ~/ 3600 % 24)}:${pad2(seconds ~/ 60 % 60)}:${pad2(seconds % 60)}';
  return days > 0 ? '$days天 $clock' : clock;
}
