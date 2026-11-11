part of 'models.dart';

/// A stable identity is independent of its time and position in the editor.
class RecurrenceNode {
  // An unsaved paste token; never written to backups or synchronization data.
  final String? pasteDraftId;
  final ItemAutomation automation;
  final String id, title, notes;
  final int dayOffset, minute, durationMinutes, color, completedColor;
  final bool allDay, reminderSound;
  final List<int> reminderOffsets;
  final HolidayPolicy holidayPolicy;
  final WeekendHolidayPriority weekendHolidayPriority;
  final int? legacyMinute;
  const RecurrenceNode({
    this.pasteDraftId,
    this.automation = const ItemAutomation(),
    required this.id,
    this.title = '',
    this.notes = '',
    this.dayOffset = 0,
    this.minute = 540,
    this.durationMinutes = 60,
    this.allDay = false,
    this.color = 0xFFE4EAD9,
    this.completedColor = 0xFFE2E3DF,
    this.reminderOffsets = const [10],
    this.reminderSound = true,
    this.holidayPolicy = HolidayPolicy.ignore,
    this.weekendHolidayPriority = WeekendHolidayPriority.holiday,
    this.legacyMinute,
  });
  bool get isPoint => !allDay && durationMinutes == 0;
  RecurrenceNode copyWith({
    ItemAutomation? automation,
    String? id,
    String? title,
    String? notes,
    int? dayOffset,
    int? minute,
    int? durationMinutes,
  }) => RecurrenceNode(
    pasteDraftId: id == null || id == this.id ? pasteDraftId : null,
    automation: automation ?? this.automation,
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    dayOffset: dayOffset ?? this.dayOffset,
    minute: minute ?? this.minute,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    allDay: allDay,
    color: color,
    completedColor: completedColor,
    reminderOffsets: reminderOffsets,
    reminderSound: reminderSound,
    holidayPolicy: holidayPolicy,
    weekendHolidayPriority: weekendHolidayPriority,
    legacyMinute: id != null && id != this.id ? null : legacyMinute,
  );
  void validate(int periodDays, {bool monthly = false}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
        title.length > 120 ||
        notes.length > 4000 ||
        dayOffset < 0 ||
        dayOffset >= periodDays ||
        minute < 0 ||
        minute > 1439 ||
        durationMinutes < 0 ||
        durationMinutes > (monthly ? 28 : periodDays) * 1440 ||
        (allDay &&
            (minute != 0 ||
                durationMinutes == 0 ||
                durationMinutes % 1440 != 0)) ||
        color < 0 ||
        color > 0xFFFFFFFF ||
        completedColor < 0 ||
        completedColor > 0xFFFFFFFF ||
        reminderOffsets.length > 12 ||
        reminderOffsets.toSet().length != reminderOffsets.length ||
        reminderOffsets.any((m) => m < 0 || m > 525600)) {
      throw const FormatException('节点日期或时长无效；重复周期不能短于单个节点时长');
    }
    if (legacyMinute != null && (legacyMinute! < 0 || legacyMinute! > 1439)) {
      throw const FormatException('原时间点关联无效');
    }
  }

  Map<String, dynamic> toJson() => {
    'automation': automation.toJson(),
    'id': id,
    'title': title,
    'notes': notes,
    'dayOffset': dayOffset,
    'minute': minute,
    'durationMinutes': durationMinutes,
    'allDay': allDay,
    'color': color,
    'completedColor': completedColor,
    'reminderOffsets': reminderOffsets,
    'reminderSound': reminderSound,
    'holidayPolicy': holidayPolicy.name,
    'weekendHolidayPriority': weekendHolidayPriority.name,
    if (legacyMinute != null) 'legacyMinute': legacyMinute,
  };
  factory RecurrenceNode.fromJson(Map<String, dynamic> j) => RecurrenceNode(
    automation: ItemAutomation.fromJson(
      j['automation'] == null
          ? null
          : Map<String, dynamic>.from(j['automation'] as Map),
    ),
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    dayOffset: j['dayOffset'] as int,
    minute: j['minute'] as int,
    durationMinutes: j['durationMinutes'] as int,
    allDay: j['allDay'] == true,
    color: j['color'] as int,
    completedColor: j['completedColor'] as int,
    reminderOffsets: (j['reminderOffsets'] as List).cast<int>(),
    reminderSound: j['reminderSound'] != false,
    holidayPolicy: HolidayPolicy.values.byName(
      j['holidayPolicy'] as String? ?? 'ignore',
    ),
    weekendHolidayPriority: WeekendHolidayPriority.values.byName(
      j['weekendHolidayPriority'] as String? ?? 'holiday',
    ),
    legacyMinute: j['legacyMinute'] as int?,
  );
}
