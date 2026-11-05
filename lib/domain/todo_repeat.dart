part of 'models.dart';

class TodoRepeatNode {
  final RecurrenceNode item;
  // Null means the next cycle's boundary; explicit offsets start at Day1 00:00.
  final int? deadlineMinutes;
  final bool removeAfterCycle;
  const TodoRepeatNode({
    required this.item,
    this.deadlineMinutes,
    this.removeAfterCycle = true,
  });
  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'deadlineMinutes': deadlineMinutes,
    'removeAfterCycle': removeAfterCycle,
  };
  factory TodoRepeatNode.fromJson(Map<String, dynamic> json) => TodoRepeatNode(
    item: RecurrenceNode.fromJson(
      Map<String, dynamic>.from(json['item'] as Map),
    ),
    deadlineMinutes: json['deadlineMinutes'] as int?,
    removeAfterCycle: json['removeAfterCycle'] as bool? ?? true,
  );
}

class TodoRepeatRule {
  final RepeatFrequency frequency;
  final int intervalDays;
  final HolidayPolicy holidayPolicy;
  final WeekendHolidayPriority weekendHolidayPriority;
  final List<TodoRepeatNode> nodes;
  const TodoRepeatRule({
    this.frequency = RepeatFrequency.daily,
    this.intervalDays = 1,
    this.holidayPolicy = HolidayPolicy.ignore,
    this.weekendHolidayPriority = WeekendHolidayPriority.holiday,
    required this.nodes,
  });
  int get periodDays => switch (frequency) {
    RepeatFrequency.daily => 1,
    RepeatFrequency.weekly => 7,
    RepeatFrequency.monthly => 31,
    RepeatFrequency.interval => intervalDays,
  };
  void validate(String groupTitle) {
    if (intervalDays < 1 ||
        intervalDays > 365 ||
        nodes.isEmpty ||
        nodes.length > 96 ||
        nodes.map((n) => n.item.id).toSet().length != nodes.length) {
      throw const FormatException('周期需为1—365天，每组需有1—96项待办');
    }
    for (final n in nodes) {
      n.item.validate(1);
      if (n.item.dayOffset != 0 ||
          n.item.minute != 0 ||
          n.item.allDay ||
          n.item.durationMinutes != 0 ||
          (groupTitle.trim().isEmpty && n.item.title.trim().isEmpty)) {
        throw const FormatException('组标题和每项待办标题至少填写一个');
      }
      if (n.deadlineMinutes != null &&
          (n.deadlineMinutes! < 0 || n.deadlineMinutes! >= periodDays * 1440)) {
        throw const FormatException('待办截止时间需在一个循环周期内');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'intervalDays': intervalDays,
    'holidayPolicy': holidayPolicy.name,
    'weekendHolidayPriority': weekendHolidayPriority.name,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };
  factory TodoRepeatRule.fromJson(Map<String, dynamic> json) => TodoRepeatRule(
    frequency: RepeatFrequency.values.byName(json['frequency'] as String),
    intervalDays: json['intervalDays'] as int,
    holidayPolicy: HolidayPolicy.values.byName(json['holidayPolicy'] as String),
    weekendHolidayPriority: WeekendHolidayPriority.values.byName(
      json['weekendHolidayPriority'] as String,
    ),
    nodes: (json['nodes'] as List)
        .map(
          (n) => TodoRepeatNode.fromJson(Map<String, dynamic>.from(n as Map)),
        )
        .toList(),
  );
}

String combinedTitle(String group, String item) =>
    [group.trim(), item.trim()].where((s) => s.isNotEmpty).join('-');

bool hasValidGroupTitle(String title, List<RecurrenceNode> nodes) =>
    title.trim().isNotEmpty ||
    (nodes.isNotEmpty && nodes.every((n) => n.title.trim().isNotEmpty));
