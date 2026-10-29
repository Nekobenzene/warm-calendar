import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'data/repository.dart';
import 'domain/calendar_service.dart';
import 'domain/models.dart';
import 'domain/recurrence.dart';
import 'domain/reminders.dart';
import 'domain/holiday_update.dart';
import 'platform/notification_service.dart';
import 'sync/link_controller.dart';

class AppController extends ChangeNotifier {
  final ScheduleRepository repository;
  final CalendarService calendar;
  final NotificationBackend notifications;
  final LinkController? link;
  AppController({
    required this.repository,
    required this.calendar,
    NotificationBackend? notifications,
    this.link,
  }) : notifications = notifications ?? createNotificationService() {
    this.notifications.beforeExit = () => _writes;
    link?.onRemoteApplied = reloadSyncedEvents;
  }
  List<ScheduleEvent> _events = [];
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
          events,
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

  List<ScheduleEvent> get events =>
      _resolvedEvents ??= resolveEvents(_events, calendar);
  ScheduleEvent? seriesFor(ScheduleEvent event) => _events
      .where(
        (e) => e.id == event.seriesId && e.recurrence != null && !e.deleted,
      )
      .firstOrNull;
  List<ScheduleEvent> onDay(DateTime d) =>
      events.where((e) => e.occursOn(d)).toList();
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
          unawaited(refreshTime());
        });
      }
    } catch (e) {
      error = '无法读取本地数据。请重试；浏览器需允许此站点存储数据。';
      debugPrint('Initialize failed: $e');
    }
    loading = false;
    notifyListeners();
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
    if (event.recurrence != null) {
      dueReminders.removeWhere((e) => e.seriesId == event.id);
    }
  }

  Future<void> _persistEvents(List<ScheduleEvent> records) async {
    await repository.saveEvents(records);
    final ids = records.map((e) => e.id).toSet();
    final roots = records
        .where((e) => e.recurrence != null)
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

  Future<void> saveEvent(ScheduleEvent event) => _serialize(() async {
    ScheduleEvent.fromJson(event.toJson());
    if (event.recurrence != null) {
      expandSeries(event, calendar, validate: true);
    }
    if (event.seriesId != null && seriesFor(event) == null) {
      throw const FormatException('该重复日程已删除，请关闭后重试');
    }
    final old = _events.where((e) => e.id == event.id).firstOrNull;
    if (old?.recurrence != null && event.recurrence == null) {
      // Retain the old rule as a tombstone so old exceptions never resurrect.
      final single = ScheduleEvent(
        id: '${event.id}-single-${DateTime.now().microsecondsSinceEpoch}',
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
        updatedAt: event.updatedAt,
      );
      await _persistEvents([old!.copyWith(deleted: true), single]);
    } else {
      await _persistEvent(event);
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
    final current = events.where((e) => e.id == event.id).firstOrNull;
    if (current == null) throw const FormatException('日程已变更，请重试');
    final delta = newStart.difference(current.start);
    final endDelta = newEnd?.difference(current.end) ?? delta;
    if (delta == Duration.zero && endDelta == Duration.zero) return;
    final root = entireSeries ? seriesFor(current) : null;
    final records = <ScheduleEvent>[];
    if (root != null) {
      final r = root.recurrence!;
      final rule = RecurrenceRule(
        frequency: r.frequency,
        until: r.until,
        intervalDays: r.intervalDays,
        weekdays: r.weekdays,
        monthDays: r.monthDays,
        minutes: r.minutes,
        holidayPolicy: r.holidayPolicy,
        shiftMinutes: r.shiftMinutes + delta.inMinutes,
      );
      final moved = root.copyWith(
        start: root.start.add(delta),
        end: root.end.add(endDelta),
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
                end: e.end.add(endDelta),
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
    final current = events
        .where((e) => e.id == event.id && !e.deleted)
        .firstOrNull;
    if (current == null) return;
    await _persistEvent(current.copyWith(completed: !current.completed));
    await _syncNotifications();
    _checkReminders();
    _notify();
  });
  Future<void> deleteEvent(ScheduleEvent event, {bool entireSeries = false}) =>
      _serialize(() async {
        final current = entireSeries
            ? seriesFor(event)
            : events.where((e) => e.id == event.id && !e.deleted).firstOrNull;
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
    if (!settings.autoCompleteExpired) return;
    _checkReminders();
    try {
      for (final event in events.where(
        (e) => e.statusAt(now) == ScheduleStatus.overdue,
      )) {
        await _persistEvent(
          event.copyWith(completed: true),
          preserveReminder: event.isPoint,
        );
      }
    } catch (_) {
      automationError = '自动完成失败，未保存的逾期日程已保留，将自动重试。';
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
    for (final event in events) {
      final passed =
          event.reminderOffsets
              .where(
                (offset) =>
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
    notifications.dispose();
    link?.dispose();
    unawaited(_writes.then((_) => repository.close()));
    super.dispose();
  }
}
