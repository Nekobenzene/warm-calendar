import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'data/repository.dart';
import 'domain/calendar_service.dart';
import 'domain/models.dart';
import 'domain/todos.dart';
import 'domain/recurrence.dart';
import 'domain/reminders.dart';
import 'domain/holiday_update.dart';
import 'domain/app_update.dart';
import 'domain/item_clipboard.dart';
import 'platform/update_platform.dart' as update_platform;
import 'platform/notification_service.dart';
import 'sync/link_controller.dart';

class AppController extends ChangeNotifier {
  final ScheduleRepository repository;
  final CalendarService calendar;
  final NotificationBackend notifications;
  final LinkController? link;
  late final AppUpdateController updater;
  AppController({
    required this.repository,
    required this.calendar,
    NotificationBackend? notifications,
    AppUpdateController? updates,
    this.link,
  }) : notifications = notifications ?? createNotificationService() {
    this.notifications.beforeExit = () => _writes;
    link?.onRemoteApplied = reloadSyncedEvents;
    updater =
        updates ??
        AppUpdateController(
          installer: (path) async {
            await update_platform.installUpdate(path);
            if (this.notifications.desktop) {
              await this.notifications.exitForUpdate();
            }
          },
        );
  }
  List<ScheduleEvent> _events = [];
  final clipboard = ItemClipboard();
  final Map<String, ItemClipboardEntry> _pasteOrigins = {};
  void copyItem(ScheduleEvent event, {bool cut = false}) {
    clipboard.put(event, cut: cut);
    _notify();
  }

  ScheduleEvent? pasteDraft(bool isTodo, {DateTime? date}) {
    final draft = clipboard.draft(
      isTodo,
      now,
      date: date,
      todoOrder: nextTodoOrder,
    );
    if (draft != null) _pasteOrigins[draft.id] = clipboard.entry(isTodo)!;
    return draft;
  }

  void discardPaste(String id) => _pasteOrigins.remove(id);
  List<ScheduleEvent>? _resolvedEvents;
  AppSettings settings = const AppSettings();
  DateTime now = DateTime.now();
  bool loading = true;
  String? error;
  String? notificationError;
  String? notificationErrorDetail;
  String? automationError;
  bool holidayRefreshing = false;
  String? holidayUpdateError;
  DateTime? _holidayAttempt;
  final List<ScheduleEvent> dueReminders = [];
  final Set<String> _delivered = {};
  Timer? _timer;
  Future<void> _writes = Future.value();
  bool _refreshing = false;
  bool _disposed = false;
  DateTime? _lastNotificationSync;
  String? _notificationInitializationError;
  String? get notificationEventId => notifications.openedEvent.value;
  Future<void> _syncNotifications() async {
    if (!notifications.supportsScheduling) return;
    _lastNotificationSync = now;
    try {
      await notifications.reconcile(
        planReminders(
          [...events, ...todoReminderEvents(_events, calendar, now)],
          settings,
          now,
          limit: notifications.android ? 128 : 512,
        ),
      );
      notificationErrorDetail = null;
      notificationError = notifications.permission == 'denied'
          ? '系统已关闭日程表通知，可在设置中允许。'
          : _notificationInitializationError;
    } catch (e) {
      notificationError = '系统定时提醒暂不可用，运行期间改用即时通知；一分钟后重试。';
      notificationErrorDetail = '$e';
      if (notifications.diagnosticMode) {
        notificationError = '$notificationError\n$e';
      }
      debugPrint('Notification scheduling failed: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // Serialize user edits and automatic completion to prevent stale writes.
  Future<void> _serialize(Future<void> Function() action) {
    final operation = _writes.then((_) => action());
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  List<ScheduleEvent> get events => _resolvedEvents ??= resolveEvents(
    _events.where((e) => !e.isTodo).toList(),
    calendar,
  );
  List<ScheduleEvent> get todos =>
      orderedTodos(resolveTodos(_events, calendar, now), settings);
  List<ScheduleEvent> get todoGroups => _events
      .where((e) => e.isTodo && e.todoRepeat != null && !e.deleted)
      .toList();
  int get nextTodoOrder => _events
      .where((e) => e.isTodo)
      .fold<int>(
        0,
        (value, e) => value > e.todoOrder + (e.todoRepeat?.nodes.length ?? 1)
            ? value
            : e.todoOrder + (e.todoRepeat?.nodes.length ?? 1),
      );
  List<ScheduleEvent> get allItems => [...events, ...todos];
  List<ScheduleEvent> get calendarEvents => [
    ...events,
    ...todos.where((e) => e.hasDeadline),
  ];
  ScheduleEvent? seriesFor(ScheduleEvent event) => _events
      .where(
        (e) =>
            e.id == event.seriesId &&
            (e.recurrence != null || e.todoRepeat != null) &&
            !e.deleted,
      )
      .firstOrNull;
  List<ScheduleEvent> onDay(DateTime d) =>
      calendarEvents.where((e) => e.occursOn(d)).toList();

  Future<void> changeTodos(
    Set<String> ids, {
    bool? completed,
    bool delete = false,
  }) => _serialize(() async {
    final records = todos
        .where((e) => ids.contains(e.id))
        .map(
          (e) =>
              e.copyWith(completed: completed, deleted: delete ? true : null),
        )
        .toList();
    if (records.isEmpty) return;
    await _persistEvents(records);
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });

  Future<void> reorderTodos(List<String> visibleOrder) => _serialize(() async {
    final all = orderedTodos(
      resolveTodos(_events, calendar, now),
      settings.copyWith(
        todoSort: TodoSort.importance,
        todoSortDescending: false,
      ),
    );
    final ids = visibleOrder.toSet();
    if (ids.length != visibleOrder.length ||
        ids.any((id) => !all.any((e) => e.id == id && !e.completed))) {
      throw const FormatException('待办已变更，请重试');
    }
    final byId = {for (final e in all) e.id: e};
    final replacements = visibleOrder.iterator;
    final reordered = [
      for (final e in all)
        if (ids.contains(e.id)) (replacements..moveNext()).current else e.id,
    ];
    final changes = <ScheduleEvent>[];
    for (var i = 0; i < reordered.length; i++) {
      final e = byId[reordered[i]]!;
      if (e.todoOrder != i) changes.add(e.copyWith(todoOrder: i));
    }
    if (changes.isNotEmpty) await _persistEvents(changes);
    _notify();
  });
  Future<void> initialize({bool startTimer = true}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await calendar.load();
      _events = await repository.loadEvents();
      _resolvedEvents = null;
      settings = await repository.loadSettings();
      for (final data in settings.holidayCache.values) {
        try {
          calendar.loadHolidayJson(jsonDecode(data) as Map<String, dynamic>);
        } catch (_) {
          /* Keep the bundled year when a cache entry is invalid. */
        }
      }
      link?.deviceName = settings.deviceName;
      now = DateTime.now();
      try {
        final startup = await notifications.readLaunchAtStartup();
        if (startup != null && startup != settings.launchAtStartup) {
          settings = settings.copyWith(launchAtStartup: startup);
          await repository.saveSettings(settings);
        }
        await notifications.initialize();
        await notifications.applyDesktopSettings(settings);
      } catch (e) {
        notificationErrorDetail = '$e';
        _notificationInitializationError = notificationError =
            '系统提醒初始化失败，应用内提醒仍可使用。';
        debugPrint('Notification initialization failed: $e');
      }
      await _completeExpired();
      await _syncNotifications();
      _checkReminders();
      await link?.initialize(startPolling: startTimer);
      if (startTimer) {
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (settings.autoCheckUpdates &&
              (updater.lastAttempt == null ||
                  DateTime.now().difference(updater.lastAttempt!) >
                      const Duration(hours: 6))) {
            unawaited(updater.check());
          }
          unawaited(refreshTime());
        });
      }
    } catch (e) {
      error = '无法读取本地数据。请重试；浏览器需允许此站点存储数据。';
      debugPrint('Initialize failed: $e');
    }
    loading = false;
    notifyListeners();
    if (startTimer && settings.autoCheckUpdates) unawaited(updater.check());
    if (startTimer &&
        settings.autoUpdateHolidays &&
        DateTime.now().millisecondsSinceEpoch - settings.holidayCheckedAt >
            const Duration(days: 1).inMilliseconds) {
      unawaited(refreshHolidayData());
    }
  }

  Future<void> refreshHolidayData() async {
    if (holidayRefreshing || _disposed) return;
    holidayRefreshing = true;
    holidayUpdateError = null;
    _holidayAttempt = DateTime.now();
    _notify();
    try {
      final year = DateTime.now().year;
      final rows = await fetchHolidayData({year - 1, year, year + 1});
      if (_disposed) return;
      await _serialize(() async {
        final cache = Map<String, String>.from(settings.holidayCache);
        for (final row in rows.entries) {
          cache[row.key.toString()] = jsonEncode(row.value);
        }
        final next = settings.copyWith(
          holidayCache: cache,
          holidayCheckedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await repository.saveSettings(next);
        settings = next;
        for (final row in rows.values) {
          calendar.loadHolidayJson(row);
        }
        _resolvedEvents = null;
        await _syncNotifications();
      });
    } catch (e) {
      holidayUpdateError = e is FormatException
          ? e.message.toString()
          : '假期更新失败，继续使用已保存的数据。';
    } finally {
      holidayRefreshing = false;
      _notify();
    }
  }

  Future<void> _persistEvent(
    ScheduleEvent event, {
    bool preserveReminder = false,
  }) async {
    await repository.saveEvent(event);
    _events.removeWhere((e) => e.id == event.id);
    _events.add(event);
    _resolvedEvents = null;
    link?.localChanged();
    if (!preserveReminder) dueReminders.removeWhere((e) => e.id == event.id);
    if (event.recurrence != null || event.todoRepeat != null) {
      dueReminders.removeWhere((e) => e.seriesId == event.id);
    }
  }

  Future<void> _persistEvents(List<ScheduleEvent> records) async {
    await repository.saveEvents(records);
    final ids = records.map((e) => e.id).toSet();
    final roots = records
        .where((e) => e.recurrence != null || e.todoRepeat != null)
        .map((e) => e.id)
        .toSet();
    _events.removeWhere((e) => ids.contains(e.id));
    _events.addAll(records);
    _resolvedEvents = null;
    link?.localChanged();
    dueReminders.removeWhere(
      (e) => ids.contains(e.id) || roots.contains(e.seriesId),
    );
  }

  Future<void> saveEvent(
    ScheduleEvent event, {
    Set<String> clipboardDraftIds = const {},
  }) => _serialize(() async {
    final pasteIds = {
      event.id,
      ...clipboardDraftIds,
      ...?event.recurrence?.nodes
          .map((n) => n.pasteDraftId)
          .whereType<String>(),
      ...?event.todoRepeat?.nodes
          .map((n) => n.item.pasteDraftId)
          .whereType<String>(),
    };
    final cuts = <String, ScheduleEvent>{};
    for (final id in pasteIds) {
      final paste = _pasteOrigins[id];
      if (paste?.cut != true) continue;
      final source = allItems.where((e) => e.id == paste!.item.id).firstOrNull;
      if (source == null ||
          source.id == event.id ||
          jsonEncode(source.toJson()) != jsonEncode(paste!.item.toJson())) {
        throw const FormatException('剪切来源已变更，请重新剪切');
      }
      cuts[source.id] = source;
    }
    ScheduleEvent.fromJson(event.toJson());
    if (event.todoRepeat != null) {
      resolveTodos(
        [event],
        calendar,
        now.isBefore(event.start) ? event.start : now,
        validate: true,
      );
    }
    if (event.recurrence != null) {
      expandSeries(event, calendar, validate: true);
    }
    if (event.seriesId != null && seriesFor(event) == null) {
      throw const FormatException('该重复日程已删除，请关闭后重试');
    }
    final old = _events.where((e) => e.id == event.id).firstOrNull;
    if ((old?.recurrence != null || old?.todoRepeat != null) &&
        event.recurrence == null &&
        event.todoRepeat == null) {
      // Retain the old rule as a tombstone so old exceptions never resurrect.
      final single = ScheduleEvent(
        id: '${event.id}-single-${DateTime.now().microsecondsSinceEpoch}',
        automation: event.automation,
        isTodo: event.isTodo,
        hasDeadline: event.hasDeadline,
        taskCreatedAt: event.taskCreatedAt,
        todoOrder: event.todoOrder,
        title: event.title,
        notes: event.notes,
        start: event.start,
        end: event.end,
        allDay: event.allDay,
        completed: event.completed,
        reminderMinutes: event.reminderMinutes,
        reminderOffsets: event.reminderOffsets,
        reminderSound: event.reminderSound,
        color: event.color,
        completedColor: event.completedColor,
        nodeId: event.nodeId,
        updatedAt: event.updatedAt,
      );
      await _persistEvents([
        old!.copyWith(deleted: true),
        single,
        ...cuts.values.map((e) => e.copyWith(deleted: true)),
      ]);
    } else if (cuts.isNotEmpty) {
      await _persistEvents([
        event,
        ...cuts.values.map((e) => e.copyWith(deleted: true)),
      ]);
    } else {
      await _persistEvent(event);
    }
    final copied = clipboard.entry(event.isTodo);
    if (copied != null && cuts.containsKey(copied.item.id)) {
      clipboard.put(copied.item);
    }
    for (final id in pasteIds) {
      _pasteOrigins.remove(id);
    }
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });

  Future<void> moveEvent(
    ScheduleEvent event,
    DateTime newStart, {
    bool entireSeries = false,
    DateTime? newEnd,
  }) => _serialize(() async {
    final current = calendarEvents.where((e) => e.id == event.id).firstOrNull;
    if (current == null) throw const FormatException('日程已变更，请重试');
    final delta = newStart.difference(current.start);
    final endDelta = newEnd?.difference(current.end) ?? delta;
    if (delta == Duration.zero && endDelta == Duration.zero) return;
    final root = entireSeries ? seriesFor(current) : null;
    final records = <ScheduleEvent>[];
    if (root?.todoRepeat != null) {
      final rule = root!.todoRepeat!;
      final cycle = todoCycleAt(root, now)!;
      if (newStart.isBefore(cycle.start) || newStart.isAfter(cycle.end)) {
        throw const FormatException('修改所有周期时，截止时间必须位于当前周期内；跨周期请仅修改本次');
      }
      final offset =
          DateTime.utc(
                newStart.year,
                newStart.month,
                newStart.day,
                newStart.hour,
                newStart.minute,
              )
              .difference(
                DateTime.utc(
                  cycle.start.year,
                  cycle.start.month,
                  cycle.start.day,
                ),
              )
              .inMinutes;
      final moved = root.copyWith(
        todoRepeat: TodoRepeatRule(
          frequency: rule.frequency,
          intervalDays: rule.intervalDays,
          holidayPolicy: rule.holidayPolicy,
          weekendHolidayPriority: rule.weekendHolidayPriority,
          nodes: [
            for (final n in rule.nodes)
              n.item.id == current.nodeId
                  ? TodoRepeatNode(
                      item: n.item,
                      removeAfterCycle: n.removeAfterCycle,
                      deadlineMinutes: newStart == cycle.end ? null : offset,
                    )
                  : n,
          ],
        ),
      );
      ScheduleEvent.fromJson(moved.toJson());
      records.add(moved);
      if (_events.any((e) => e.id == current.id)) {
        records.add(current.copyWith(start: newStart, end: newStart));
      }
    } else if (root != null) {
      final r = root.recurrence!;
      final rule = r.copyWith(
        shiftMinutes: r.shiftMinutes + delta.inMinutes,
        nodes: r.nodes.isNotEmpty
            ? [
                for (final node in r.nodes)
                  node.id == current.nodeId
                      ? node.copyWith(
                          durationMinutes:
                              node.durationMinutes +
                              endDelta.inMinutes -
                              delta.inMinutes,
                        )
                      : node,
              ]
            : null,
      );
      final moved = root.copyWith(
        start: root.start.add(delta),
        end: root.end.add(
          r.nodes.isNotEmpty && r.nodes.first.id != current.nodeId
              ? delta
              : endDelta,
        ),
        recurrence: rule,
      );
      expandSeries(moved, calendar, validate: true);
      records.add(moved);
      records.addAll(
        _events
            .where((e) => e.seriesId == root.id)
            .map(
              (e) => e.copyWith(
                start: e.start.add(delta),
                end: e.end.add(
                  r.nodes.isNotEmpty && e.nodeId != current.nodeId
                      ? delta
                      : endDelta,
                ),
              ),
            ),
      );
    } else {
      records.add(
        current.copyWith(start: newStart, end: current.end.add(endDelta)),
      );
    }
    for (final e in records) {
      ScheduleEvent.fromJson(e.toJson());
    }
    await _persistEvents(records);
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });

  Future<void> toggleCompleted(ScheduleEvent event) => _serialize(() async {
    final current = allItems
        .where((e) => e.id == event.id && !e.deleted)
        .firstOrNull;
    if (current == null) return;
    final completing = !current.completed;
    await _persistEvent(
      current.copyWith(
        completed: completing,
        deleted: completing && current.automation.deleteCompleted,
      ),
    );
    await _syncNotifications();
    _checkReminders();
    _notify();
  });
  Future<void> deleteEvent(ScheduleEvent event, {bool entireSeries = false}) =>
      _serialize(() async {
        final current = entireSeries
            ? (event.todoRepeat != null
                  ? _events
                        .where((e) => e.id == event.id && !e.deleted)
                        .firstOrNull
                  : seriesFor(event))
            : allItems.where((e) => e.id == event.id && !e.deleted).firstOrNull;
        if (current == null) return;
        await _persistEvent(current.copyWith(deleted: true));
        await _syncNotifications();
        _notify();
      });
  Future<void> updateSettings(AppSettings value) => _serialize(() async {
    await notifications.applyDesktopSettings(value);
    try {
      await repository.saveSettings(value);
    } catch (_) {
      await notifications.applyDesktopSettings(settings);
      rethrow;
    }
    settings = value;
    link?.deviceName = value.deviceName;
    link?.localChanged();
    if (!value.remindersEnabled) dueReminders.clear();
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });

  Future<void> refreshTime({DateTime? at}) async {
    now = at ?? DateTime.now();
    if (_timer != null &&
        settings.autoUpdateHolidays &&
        !holidayRefreshing &&
        DateTime.now().millisecondsSinceEpoch - settings.holidayCheckedAt >
            const Duration(days: 1).inMilliseconds &&
        (_holidayAttempt == null ||
            DateTime.now().difference(_holidayAttempt!) >
                const Duration(days: 1))) {
      unawaited(refreshHolidayData());
    }
    _notify();
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      await _serialize(() async {
        await _completeExpired();
        if (_lastNotificationSync == null ||
            now.difference(_lastNotificationSync!).abs() >=
                const Duration(minutes: 1)) {
          await _syncNotifications();
        }
        _checkReminders();
      });
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> _completeExpired() async {
    automationError = null;
    if (settings.autoCompleteExpired || settings.autoCompleteTodos) {
      final migrated = <ScheduleEvent>[];
      for (final e in _events.where(
        (e) =>
            !e.deleted &&
            (e.isTodo
                ? settings.autoCompleteTodos
                : settings.autoCompleteExpired),
      )) {
        final json = e.toJson();
        json['automation'] = e.automation
            .copyWith(completeExpired: true)
            .toJson();
        final repeat = json[e.isTodo ? 'todoRepeat' : 'recurrence'] as Map?;
        final nodes = repeat?['nodes'] as List?;
        for (final raw in nodes ?? []) {
          final item = e.isTodo ? (raw as Map)['item'] as Map : raw as Map;
          item['automation'] = ItemAutomation.fromJson(
            Map<String, dynamic>.from(item['automation'] as Map? ?? {}),
          ).copyWith(completeExpired: true).toJson();
        }
        migrated.add(ScheduleEvent.fromJson(json));
      }
      if (migrated.isNotEmpty) await _persistEvents(migrated);
      settings = settings.copyWith(
        autoCompleteExpired: false,
        autoCompleteTodos: false,
      );
      await repository.saveSettings(settings);
    }
    _checkReminders();
    try {
      for (final event in allItems.toList()) {
        final rule = event.automation;
        final overdue = event.statusAt(now) == ScheduleStatus.overdue;
        final complete = !event.completed && overdue && rule.completeExpired;
        final delete =
            (event.completed || complete) && rule.deleteCompleted ||
            overdue &&
                rule.deleteExpired &&
                event.seriesId == null &&
                event.recurrence == null &&
                event.todoRepeat == null;
        if (!complete && !delete) continue;
        await _persistEvent(
          event.copyWith(
            completed: complete ? true : null,
            deleted: delete ? true : null,
          ),
          preserveReminder: event.isPoint,
        );
      }
    } catch (_) {
      automationError = '自动处理失败，未保存的事项已保留，将自动重试。';
    }
  }

  String exportBackup() => BackupData(_events, settings).encode();
  Future<void> reloadSyncedEvents() => _serialize(() async {
    if (_disposed) return;
    settings = await repository.loadSettings();
    await notifications.applyDesktopSettings(settings);
    _events = await repository.loadEvents();
    _resolvedEvents = null;
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });
  Future<void> importBackup(BackupData backup) => _serialize(() async {
    for (final e in backup.events.where(
      (e) => e.recurrence != null && !e.deleted,
    )) {
      // Unknown holiday years stay unresolved rather than becoming workdays.
      expandSeries(e, calendar);
    }
    await repository.mergeBackup(
      BackupData(
        backup.events,
        backup.settings.copyWith(launchAtStartup: settings.launchAtStartup),
      ),
    );
    _events = await repository.loadEvents();
    _resolvedEvents = null;
    link?.localChanged();
    settings = await repository.loadSettings();
    await notifications.applyDesktopSettings(settings);
    dueReminders.clear();
    await _completeExpired();
    await _syncNotifications();
    _checkReminders();
    _notify();
  });

  void _checkReminders() {
    dueReminders.removeWhere(
      (e) =>
          !(e.isPoint ? e.start.add(const Duration(minutes: 1)) : e.end)
              .isAfter(now) ||
          e.completed ||
          e.deleted,
    );
    if (!settings.remindersEnabled) return;
    final reminderItems = {
      for (final e in [
        ...allItems,
        ...resolveTodos(
          _events,
          calendar,
          now.subtract(const Duration(minutes: 1)),
          includeSingles: false,
        ),
      ])
        e.id: e,
    };
    for (final event in reminderItems.values.where(
      (e) => !e.isTodo || e.hasDeadline,
    )) {
      final passed =
          event.reminderOffsets
              .where(
                (offset) =>
                    (event.todoCycleStart == null ||
                        !event.start
                            .subtract(Duration(minutes: offset))
                            .isBefore(event.todoCycleStart!)) &&
                    !event.start
                        .subtract(Duration(minutes: offset))
                        .isAfter(now) &&
                    !_delivered.contains(reminderKey(event, offset)),
              )
              .toList()
            ..sort();
      if (!event.completed &&
          passed.isNotEmpty &&
          (event.isPoint
                  ? event.start.add(const Duration(minutes: 1))
                  : event.end)
              .isAfter(now)) {
        for (final offset in passed) {
          _delivered.add(reminderKey(event, offset));
        }
        dueReminders.removeWhere((e) => e.id == event.id);
        dueReminders.add(event);
        if (settings.systemNotificationsEnabled &&
            (!notifications.supportsScheduling ||
                (!notifications.schedulingHealthy &&
                    !notifications.hasScheduledReminder(
                      reminderKey(event, passed.first),
                    )))) {
          unawaited(
            notifications
                .show(
                  event.title,
                  reminderBody(event, now),
                  eventId: event.id,
                  sound: settings.notificationSound && event.reminderSound,
                )
                .catchError((Object _) {
                  notificationError = '系统通知发送失败，应用内提醒仍可用。';
                  _notify();
                }),
          );
        }
      }
    }
  }

  void dismissReminder(ScheduleEvent event) {
    dueReminders.removeWhere((e) => e.id == event.id);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    updater.dispose();
    notifications.dispose();
    link?.dispose();
    unawaited(_writes.then((_) => repository.close()));
    super.dispose();
  }

  Future<void> prepareForUpdate() async {
    await _writes;
    await notifications.flush();
  }
}
