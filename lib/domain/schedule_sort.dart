import 'models.dart';

List<ScheduleEvent> sortSchedules(
  Iterable<ScheduleEvent> events,
  AppSettings settings,
  DateTime now,
) {
  final rows = events.toList();
  rows.sort((a, b) {
    int rank(ScheduleStatus status) => switch (status) {
      ScheduleStatus.ongoing => 0,
      ScheduleStatus.pending => 1,
      ScheduleStatus.overdue => 2,
      ScheduleStatus.completed => 3,
    };
    final result = switch (settings.scheduleSort) {
      ScheduleSort.start => a.start.compareTo(b.start),
      ScheduleSort.end => a.end.compareTo(b.end),
      ScheduleSort.updated => a.updatedAt.compareTo(b.updatedAt),
      ScheduleSort.title => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      ScheduleSort.status => rank(
        a.statusAt(now),
      ).compareTo(rank(b.statusAt(now))),
    };
    if (result != 0) return settings.sortDescending ? -result : result;
    final time = a.start.compareTo(b.start);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  return rows;
}
