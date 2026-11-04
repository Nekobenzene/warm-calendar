import 'models.dart';

enum TodoFilter { pending, completed, overdue, all }

extension TodoFilterLabel on TodoFilter {
  String get label => switch (this) {
    TodoFilter.pending => '未完成',
    TodoFilter.completed => '已完成',
    TodoFilter.overdue => '已逾期',
    TodoFilter.all => '全部',
  };
}

List<ScheduleEvent> orderedTodos(
  Iterable<ScheduleEvent> tasks,
  AppSettings settings,
) {
  final result = tasks.where((e) => e.isTodo && !e.deleted).toList();
  result.sort((a, b) {
    var c = switch (settings.todoSort) {
      TodoSort.created => a.createdAt.compareTo(b.createdAt),
      TodoSort.importance => a.todoOrder.compareTo(b.todoOrder),
      TodoSort.deadline =>
        a.deadline == null
            ? b.deadline == null
                  ? 0
                  : 1
            : b.deadline == null
            ? -1
            : a.deadline!.compareTo(b.deadline!),
    };
    if (c == 0) c = a.createdAt.compareTo(b.createdAt);
    if (c == 0) c = a.id.compareTo(b.id);
    return settings.todoSortDescending ? -c : c;
  });
  return result;
}

bool matchesTodo(ScheduleEvent e, TodoFilter filter, DateTime now) =>
    switch (filter) {
      TodoFilter.pending => !e.completed,
      TodoFilter.completed => e.completed,
      TodoFilter.overdue => e.statusAt(now) == ScheduleStatus.overdue,
      TodoFilter.all => true,
    };
