import 'dart:convert';

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) => dateKey(a) == dateKey(b);
String pad2(int n) => n.toString().padLeft(2, '0');
String clockText(DateTime d, {bool seconds = false, bool hour24 = true}) {
  final hour = hour24 ? d.hour : (d.hour % 12 == 0 ? 12 : d.hour % 12);
  final period = hour24 ? '' : (d.hour < 12 ? '上午 ' : '下午 ');
  return '$period${pad2(hour)}:${pad2(d.minute)}${seconds ? ':${pad2(d.second)}' : ''}';
}

enum ScheduleStatus { pending, ongoing, completed, overdue }

enum RepeatFrequency { daily, weekly, monthly, interval }

enum HolidayPolicy { ignore, skip, only }

enum ScheduleSort { start, end, updated, title, status }

extension ScheduleSortLabel on ScheduleSort {
  String get label => switch (this) {
    ScheduleSort.start => '开始时间',
    ScheduleSort.end => '结束时间',
    ScheduleSort.updated => '最近修改',
    ScheduleSort.title => '标题',
    ScheduleSort.status => '状态',
  };
}

class RecurrenceRule {
  final RepeatFrequency frequency;
  final DateTime until;
  final int intervalDays;
  final List<int> weekdays;
  final List<int> monthDays;
  final List<int> minutes;
  final HolidayPolicy holidayPolicy;
  final int shiftMinutes;

  const RecurrenceRule({
    required this.frequency,
    required this.until,
    this.intervalDays = 2,
    this.weekdays = const [],
    this.monthDays = const [],
    this.minutes = const [540],
    this.holidayPolicy = HolidayPolicy.ignore,
    this.shiftMinutes = 0,
  });

  void validate(DateTime start, {required bool allDay}) {
    bool validList(List<int> values, int min, int max) =>
        values.isNotEmpty &&
        values.toSet().length == values.length &&
        values.every((v) => v >= min && v <= max);
    if (shiftMinutes.abs() > 105000000 ||
        until.isBefore(
          dayOnly(start.subtract(Duration(minutes: shiftMinutes))),
        ) ||
        until.year > 2099 ||
        intervalDays < 1 ||
        intervalDays > 365 ||
        !validList(minutes, 0, 1439) ||
        minutes.length > 24 ||
        (allDay && (minutes.length != 1 || minutes.first != 0)) ||
        (frequency == RepeatFrequency.weekly && !validList(weekdays, 1, 7)) ||
        (frequency == RepeatFrequency.monthly &&
            !validList(monthDays, 1, 31))) {
      throw const FormatException('重复规则无效，请检查日期、时间点和重复范围');
    }
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'until': dateKey(until),
    'intervalDays': intervalDays,
    'weekdays': weekdays,
    'monthDays': monthDays,
    'minutes': minutes,
    'holidayPolicy': holidayPolicy.name,
    'shiftMinutes': shiftMinutes,
  };

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) {
    final until = DateTime.parse(j['until'] as String);
    if (dateKey(until) != j['until']) {
      throw const FormatException('重复结束日期无效');
    }
    return RecurrenceRule(
      frequency: RepeatFrequency.values.byName(j['frequency'] as String),
      until: until,
      intervalDays: j['intervalDays'] as int? ?? 2,
      weekdays: (j['weekdays'] as List? ?? []).cast<int>(),
      monthDays: (j['monthDays'] as List? ?? []).cast<int>(),
      minutes: (j['minutes'] as List).cast<int>(),
      holidayPolicy: HolidayPolicy.values.byName(j['holidayPolicy'] as String),
      shiftMinutes: j['shiftMinutes'] as int? ?? 0,
    );
  }
}

extension StatusLabel on ScheduleStatus {
  String get label => switch (this) {
    ScheduleStatus.pending => '未完成',
    ScheduleStatus.ongoing => '进行中',
    ScheduleStatus.completed => '已完成',
    ScheduleStatus.overdue => '逾期',
  };
}

class ScheduleEvent {
  final String id;
  final String title;
  final String notes;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool completed;
  final int? _legacyReminderMinutes;
  final List<int>? _reminderOffsets;
  final bool reminderSound;
  List<int> get reminderOffsets => List.unmodifiable(
    _reminderOffsets ??
        (_legacyReminderMinutes == null ? <int>[] : [_legacyReminderMinutes]),
  );
  // Compatibility for older callers; new code uses every offset.
  int? get reminderMinutes => reminderOffsets.firstOrNull;
  final DateTime updatedAt;
  final bool deleted;
  final int revision;
  final RecurrenceRule? recurrence;
  final String? seriesId;
  // Original local date and time; remains stable after editing one occurrence.
  final String? occurrenceKey;
  final int color;
  final int completedColor;
  int get displayColor => completed ? completedColor : color;

  const ScheduleEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.updatedAt,
    this.notes = '',
    this.allDay = false,
    this.completed = false,
    int? reminderMinutes = 10,
    List<int>? reminderOffsets,
    this.reminderSound = true,
    this.deleted = false,
    this.revision = 1,
    this.recurrence,
    this.seriesId,
    this.occurrenceKey,
    this.color = 0xFFE4EAD9,
    this.completedColor = 0xFFE2E3DF,
  }) : _legacyReminderMinutes = reminderMinutes,
       _reminderOffsets = reminderOffsets;

  ScheduleStatus statusAt(DateTime now) => completed
      ? ScheduleStatus.completed
      : !end.isAfter(now)
      ? ScheduleStatus.overdue
      : !now.isBefore(start)
      ? ScheduleStatus.ongoing
      : ScheduleStatus.pending;
  bool get isOverdue => statusAt(DateTime.now()) == ScheduleStatus.overdue;
  bool get isPoint => !allDay && end.isAtSameMomentAs(start);
  bool occursOn(DateTime day) {
    if (isPoint) return sameDay(start, day);
    final d = dayOnly(day);
    return start.isBefore(DateTime(d.year, d.month, d.day + 1)) &&
        end.isAfter(d);
  }

  DateTime? get remindAt => reminderMinutes == null
      ? null
      : start.subtract(Duration(minutes: reminderMinutes!));

  ScheduleEvent copyWith({
    bool? completed,
    bool? deleted,
    DateTime? start,
    DateTime? end,
    RecurrenceRule? recurrence,
  }) => ScheduleEvent(
    id: id,
    title: title,
    start: start ?? this.start,
    end: end ?? this.end,
    updatedAt: DateTime.now().toUtc(),
    notes: notes,
    allDay: allDay,
    completed: completed ?? this.completed,
    reminderMinutes: reminderMinutes,
    reminderOffsets: reminderOffsets,
    reminderSound: reminderSound,
    deleted: deleted ?? this.deleted,
    revision: revision + 1,
    recurrence: recurrence ?? this.recurrence,
    seriesId: seriesId,
    occurrenceKey: occurrenceKey,
    color: color,
    completedColor: completedColor,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'start': allDay ? dateKey(start) : start.toUtc().toIso8601String(),
    'end': allDay ? dateKey(end) : end.toUtc().toIso8601String(),
    'allDay': allDay,
    'completed': completed,
    'reminderMinutes': reminderMinutes,
    'reminderOffsets': reminderOffsets,
    'reminderSound': reminderSound,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
    'revision': revision,
    'color': color,
    'completedColor': completedColor,
    if (recurrence != null) 'recurrence': recurrence!.toJson(),
    if (seriesId != null) 'seriesId': seriesId,
    if (occurrenceKey != null) 'occurrenceKey': occurrenceKey,
  };

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) {
    final allDay = json['allDay'] == true;
    DateTime parseDate(String key) {
      final d = DateTime.parse(json[key] as String);
      return allDay ? dayOnly(d) : d.toLocal();
    }

    final event = ScheduleEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String? ?? '',
      start: parseDate('start'),
      end: parseDate('end'),
      allDay: allDay,
      completed: json['completed'] == true,
      reminderMinutes: json['reminderMinutes'] as int?,
      reminderOffsets: (json['reminderOffsets'] as List?)?.cast<int>(),
      reminderSound: json['reminderSound'] != false,
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      deleted: json['deleted'] == true,
      revision: json['revision'] as int? ?? 1,
      color: json['color'] as int? ?? 0xFFE4EAD9,
      completedColor: json['completedColor'] as int? ?? 0xFFE2E3DF,
      recurrence: json['recurrence'] == null
          ? null
          : RecurrenceRule.fromJson(
              Map<String, dynamic>.from(json['recurrence'] as Map),
            ),
      seriesId: json['seriesId'] as String?,
      occurrenceKey: json['occurrenceKey'] as String?,
    );
    if (event.id.isEmpty ||
        event.title.trim().isEmpty ||
        event.title.length > 120 ||
        event.notes.length > 4000 ||
        event.color < 0 ||
        event.color > 0xFFFFFFFF ||
        event.completedColor < 0 ||
        event.completedColor > 0xFFFFFFFF ||
        event.end.isBefore(event.start) ||
        (event.allDay && event.end == event.start) ||
        event.start.year < 1901 ||
        event.end.year > 2099 ||
        event.reminderOffsets.length > 12 ||
        event.reminderOffsets.toSet().length != event.reminderOffsets.length ||
        event.reminderOffsets.any((m) => m < 0 || m > 525600)) {
      throw const FormatException('日程数据不完整或日期超出范围');
    }
    event.recurrence?.validate(event.start, allDay: event.allDay);
    if ((event.seriesId == null) != (event.occurrenceKey == null) ||
        (event.seriesId != null &&
            (event.seriesId!.isEmpty ||
                event.recurrence != null ||
                !RegExp(
                  r'^\d{4}-\d{2}-\d{2}T\d{4}$',
                ).hasMatch(event.occurrenceKey!)))) {
      throw const FormatException('重复日程关联信息无效');
    }
    return event;
  }
}

class AppSettings {
  final bool autoUpdateHolidays;
  final int holidayCheckedAt;
  final Map<String, String> holidayCache;
  final int themeColor;
  final String backgroundImage;
  final double mainBlur, sidebarBlur, mainImageOpacity, sidebarImageOpacity;
  final String deviceName;
  final bool mondayFirst;
  final bool hour24;
  final bool showLunar;
  final bool remindersEnabled;
  final bool autoCompleteExpired;
  final bool calendarDragEnabled;
  final bool calendarLocked;
  final bool snapToGrid;
  final ScheduleSort scheduleSort;
  final bool sortDescending;
  final bool systemNotificationsEnabled;
  final bool notificationSound;
  final bool notificationVibration;
  final bool closeToTray;
  final bool launchAtStartup;
  const AppSettings({
    this.autoUpdateHolidays = true,
    this.holidayCheckedAt = 0,
    this.holidayCache = const {},
    this.themeColor = 0xFF536445,
    this.backgroundImage = '',
    this.mainBlur = 8,
    this.sidebarBlur = 16,
    this.mainImageOpacity = .16,
    this.sidebarImageOpacity = .12,
    this.deviceName = '',
    this.mondayFirst = true,
    this.hour24 = true,
    this.showLunar = true,
    this.remindersEnabled = true,
    this.autoCompleteExpired = false,
    this.calendarDragEnabled = false,
    this.calendarLocked = false,
    this.snapToGrid = true,
    this.scheduleSort = ScheduleSort.start,
    this.sortDescending = false,
    this.systemNotificationsEnabled = true,
    this.notificationSound = true,
    this.notificationVibration = true,
    this.closeToTray = true,
    this.launchAtStartup = false,
  });
  AppSettings copyWith({
    bool? autoUpdateHolidays,
    int? holidayCheckedAt,
    Map<String, String>? holidayCache,
    int? themeColor,
    String? backgroundImage,
    double? mainBlur,
    double? sidebarBlur,
    double? mainImageOpacity,
    double? sidebarImageOpacity,
    String? deviceName,
    bool? mondayFirst,
    bool? hour24,
    bool? showLunar,
    bool? remindersEnabled,
    bool? autoCompleteExpired,
    bool? calendarDragEnabled,
    bool? calendarLocked,
    bool? snapToGrid,
    ScheduleSort? scheduleSort,
    bool? sortDescending,
    bool? systemNotificationsEnabled,
    bool? notificationSound,
    bool? notificationVibration,
    bool? closeToTray,
    bool? launchAtStartup,
  }) => AppSettings(
    autoUpdateHolidays: autoUpdateHolidays ?? this.autoUpdateHolidays,
    holidayCheckedAt: holidayCheckedAt ?? this.holidayCheckedAt,
    holidayCache: holidayCache ?? this.holidayCache,
    themeColor: themeColor ?? this.themeColor,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    mainBlur: mainBlur ?? this.mainBlur,
    sidebarBlur: sidebarBlur ?? this.sidebarBlur,
    mainImageOpacity: mainImageOpacity ?? this.mainImageOpacity,
    sidebarImageOpacity: sidebarImageOpacity ?? this.sidebarImageOpacity,
    deviceName: deviceName ?? this.deviceName,
    mondayFirst: mondayFirst ?? this.mondayFirst,
    hour24: hour24 ?? this.hour24,
    showLunar: showLunar ?? this.showLunar,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    autoCompleteExpired: autoCompleteExpired ?? this.autoCompleteExpired,
    calendarDragEnabled: calendarDragEnabled ?? this.calendarDragEnabled,
    calendarLocked: calendarLocked ?? this.calendarLocked,
    snapToGrid: snapToGrid ?? this.snapToGrid,
    scheduleSort: scheduleSort ?? this.scheduleSort,
    sortDescending: sortDescending ?? this.sortDescending,
    systemNotificationsEnabled:
        systemNotificationsEnabled ?? this.systemNotificationsEnabled,
    notificationSound: notificationSound ?? this.notificationSound,
    notificationVibration: notificationVibration ?? this.notificationVibration,
    closeToTray: closeToTray ?? this.closeToTray,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
  );
  Map<String, dynamic> toJson() => {
    'autoUpdateHolidays': autoUpdateHolidays,
    'holidayCheckedAt': holidayCheckedAt,
    'holidayCache': holidayCache,
    'themeColor': themeColor,
    'backgroundImage': backgroundImage,
    'mainBlur': mainBlur,
    'sidebarBlur': sidebarBlur,
    'mainImageOpacity': mainImageOpacity,
    'sidebarImageOpacity': sidebarImageOpacity,
    'deviceName': deviceName,
    'mondayFirst': mondayFirst,
    'hour24': hour24,
    'showLunar': showLunar,
    'remindersEnabled': remindersEnabled,
    'autoCompleteExpired': autoCompleteExpired,
    'calendarDragEnabled': calendarDragEnabled,
    'calendarLocked': calendarLocked,
    'snapToGrid': snapToGrid,
    'scheduleSort': scheduleSort.name,
    'sortDescending': sortDescending,
    'systemNotificationsEnabled': systemNotificationsEnabled,
    'notificationSound': notificationSound,
    'notificationVibration': notificationVibration,
    'closeToTray': closeToTray,
    'launchAtStartup': launchAtStartup,
  };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    autoUpdateHolidays: j['autoUpdateHolidays'] != false,
    holidayCheckedAt: j['holidayCheckedAt'] is int && j['holidayCheckedAt'] >= 0
        ? j['holidayCheckedAt'] as int
        : 0,
    holidayCache: j['holidayCache'] is Map
        ? {
            for (final entry in (j['holidayCache'] as Map).entries.take(60))
              if (entry.key is String &&
                  RegExp(r'^\d{4}$').hasMatch(entry.key) &&
                  entry.value is String &&
                  (entry.value as String).length < 100000)
                entry.key as String: entry.value as String,
          }
        : const {},
    themeColor:
        j['themeColor'] is int &&
            j['themeColor'] >= 0 &&
            j['themeColor'] <= 0xffffffff
        ? (j['themeColor'] as int) | 0xff000000
        : 0xff536445,
    backgroundImage:
        j['backgroundImage'] is String &&
            (j['backgroundImage'] as String).length <= 5600000
        ? j['backgroundImage'] as String
        : '',
    mainBlur: _settingNumber(j['mainBlur'], 8, 0, 30),
    sidebarBlur: _settingNumber(j['sidebarBlur'], 16, 0, 30),
    mainImageOpacity: _settingNumber(j['mainImageOpacity'], .16, 0, .65),
    sidebarImageOpacity: _settingNumber(j['sidebarImageOpacity'], .12, 0, .65),
    deviceName:
        j['deviceName'] is String &&
            (j['deviceName'] as String).trim().length <= 60
        ? (j['deviceName'] as String).trim()
        : '',
    mondayFirst: j['mondayFirst'] != false,
    hour24: j['hour24'] != false,
    showLunar: j['showLunar'] != false,
    remindersEnabled: j['remindersEnabled'] != false,
    autoCompleteExpired: j['autoCompleteExpired'] == true,
    calendarDragEnabled: j['calendarDragEnabled'] == true,
    calendarLocked: j['calendarLocked'] == true,
    snapToGrid: j['snapToGrid'] != false,
    scheduleSort:
        ScheduleSort.values
            .where((v) => v.name == j['scheduleSort'])
            .firstOrNull ??
        ScheduleSort.start,
    sortDescending: j['sortDescending'] == true,
    systemNotificationsEnabled: j['systemNotificationsEnabled'] != false,
    notificationSound: j['notificationSound'] != false,
    notificationVibration: j['notificationVibration'] != false,
    closeToTray: j['closeToTray'] != false,
    launchAtStartup: j['launchAtStartup'] == true,
  );
}

double _settingNumber(dynamic value, double fallback, double min, double max) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;

class BackupData {
  final List<ScheduleEvent> events;
  final AppSettings settings;
  BackupData(this.events, this.settings);
  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': 'warm-calendar',
    'version': 3,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
    'settings': settings.toJson(),
  });
  factory BackupData.decode(String source) {
    if (source.length > 10 * 1024 * 1024) {
      throw const FormatException('备份文件不能超过 10 MB');
    }
    final j = jsonDecode(source);
    if (j is! Map<String, dynamic> ||
        j['format'] != 'warm-calendar' ||
        ![1, 2, 3].contains(j['version']) ||
        j['events'] is! List ||
        j['settings'] is! Map<String, dynamic>) {
      throw const FormatException('请选择本应用导出的 JSON 备份');
    }
    final rows = j['events'] as List;
    if (rows.length > 20000) throw const FormatException('备份日程数量超过上限');
    final events = rows
        .map((e) => ScheduleEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (events.map((e) => e.id).toSet().length != events.length) {
      throw const FormatException('备份包含重复日程 ID');
    }
    final roots = {
      for (final e in events.where((e) => e.recurrence != null)) e.id,
    };
    final keys = <String>{};
    for (final e in events.where((e) => e.seriesId != null)) {
      final identity = '${e.seriesId}::${e.occurrenceKey}';
      if (!roots.contains(e.seriesId) ||
          e.id != identity ||
          !keys.add(identity)) {
        throw const FormatException('重复日程缺少规则或包含重复实例');
      }
    }
    return BackupData(
      events,
      AppSettings.fromJson(j['settings'] as Map<String, dynamic>),
    );
  }
}
