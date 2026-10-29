import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
import '../domain/reminders.dart';
import 'notification_api.dart';

// Android 8+ channel sound/vibration are immutable after creation. Keep each
// combination separate, and respect any changes the user makes in Android.
AndroidNotificationDetails androidReminderDetails({
  required bool sound,
  required bool vibration,
  int? timeoutAfter,
}) => AndroidNotificationDetails(
  'calendar_reminder_s${sound ? 1 : 0}_v${vibration ? 1 : 0}_1',
  '日程提醒 · ${sound ? '声音' : '静音'} · ${vibration ? '振动' : '无振动'}',
  channelDescription: '日程开始前及开始时的提醒',
  icon: 'ic_stat_calendar',
  importance: Importance.high,
  priority: Priority.high,
  category: AndroidNotificationCategory.reminder,
  audioAttributesUsage: AudioAttributesUsage.notification,
  playSound: sound,
  enableVibration: vibration,
  visibility: NotificationVisibility.private,
  timeoutAfter: timeoutAfter,
);

class AndroidNotificationService extends NotificationBackend {
  AndroidNotificationService({
    this.requestPermissionOnInitialize = true,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  final bool requestPermissionOnInitialize;
  static const _settingsChannel = MethodChannel('warm_calendar/android');
  bool _ready = false, _healthy = false, _exact = false;
  String _permission = 'default';
  AppSettings _settings = const AppSettings();
  Future<void> _queue = Future.value();
  final Map<String, DateTime> _scheduled = {};
  int _count = 0;
  AndroidFlutterLocalNotificationsPlugin get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  @override
  bool get android => true;
  @override
  bool get supported => _ready;
  @override
  bool get supportsScheduling => _ready;
  @override
  bool get schedulingHealthy => _healthy;
  @override
  bool get exactAlarms => _exact;
  @override
  String get permission => _permission;
  @override
  int get scheduledCount => _count;
  @override
  bool hasScheduledReminder(String key) => _scheduled.containsKey(key);

  void _opened(String? payload) {
    if (payload == null || payload.isEmpty) return;
    var id = payload;
    try {
      id = (jsonDecode(payload) as Map<String, dynamic>)['eventId'] as String;
    } catch (_) {}
    openedEvent.value = null;
    openedEvent.value = id;
  }

  @override
  Future<void> initialize() async {
    if (_ready) return;
    zones.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    final ready = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_calendar'),
      ),
      onDidReceiveNotificationResponse: (response) => _opened(response.payload),
    );
    if (ready != true) throw StateError('安卓通知初始化失败');
    _ready = true;
    if (requestPermissionOnInitialize) {
      await requestPermission();
    } else {
      await refreshPermissions();
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _opened(launch?.notificationResponse?.payload);
    }
  }

  @override
  Future<void> refreshPermissions() async {
    if (!_ready) return;
    _permission = await _android.areNotificationsEnabled() == true
        ? 'granted'
        : 'denied';
    _exact = await _android.canScheduleExactNotifications() == true;
  }

  @override
  Future<String> requestPermission() async {
    await _android.requestNotificationsPermission();
    await refreshPermissions();
    return permission;
  }

  @override
  Future<void> requestExactAlarms() async {
    await _android.requestExactAlarmsPermission();
    await refreshPermissions();
  }

  @override
  Future<void> openSystemSettings() =>
      _settingsChannel.invokeMethod<void>('openNotificationSettings');
  @override
  Future<void> applyDesktopSettings(AppSettings settings) async {
    _settings = settings;
  }

  NotificationDetails _details(bool sound, {int? timeoutAfter}) =>
      NotificationDetails(
        android: androidReminderDetails(
          sound: sound,
          vibration: _settings.notificationVibration,
          timeoutAfter: timeoutAfter,
        ),
      );

  @override
  Future<void> show(
    String title,
    String body, {
    bool sound = true,
    String? eventId,
  }) async {
    if (!_ready) return;
    await refreshPermissions();
    if (permission != 'granted') throw StateError('请先允许系统通知');
    await _plugin.show(
      id: 2147483647,
      title: title,
      body: body,
      notificationDetails: _details(sound),
      payload: eventId,
    );
  }

  @override
  Future<void> reconcile(List<ReminderRequest> requests) {
    final operation = _queue.then((_) async {
      if (!_ready) return;
      await refreshPermissions();
      _scheduled.removeWhere((_, expiry) => !expiry.isAfter(DateTime.now()));
      final pending = {
        for (final item in await _plugin.pendingNotificationRequests())
          item.id: item,
      };
      final wanted = {for (final request in requests) request.id: request};
      String fingerprint(ReminderRequest r) =>
          '${r.fingerprint}:${_settings.notificationVibration}:$_exact';
      for (final item in pending.values.toList()) {
        String? old;
        String? key;
        try {
          final data = jsonDecode(item.payload ?? '') as Map<String, dynamic>;
          old = data['fingerprint'] as String?;
          key = data['key'] as String?;
        } catch (_) {}
        if (!wanted.containsKey(item.id) ||
            old != fingerprint(wanted[item.id]!)) {
          await _plugin.cancel(id: item.id);
          pending.remove(item.id);
          if (key != null) _scheduled.remove(key);
        }
      }
      for (final request in requests) {
        if (!request.at.isAfter(DateTime.now())) continue;
        if (!pending.containsKey(request.id)) {
          await _plugin.zonedSchedule(
            id: request.id,
            title: request.event.title,
            body: request.body,
            scheduledDate: tz.TZDateTime.from(request.at, tz.local),
            notificationDetails: _details(
              request.sound,
              timeoutAfter: request.expires
                  .difference(request.at)
                  .inMilliseconds,
            ),
            androidScheduleMode: _exact
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            payload: jsonEncode({
              'eventId': request.event.id,
              'key': request.key,
              'fingerprint': fingerprint(request),
            }),
          );
        }
        _scheduled[request.key] = request.expires;
      }
      final actual = (await _plugin.pendingNotificationRequests())
          .map((r) => r.id)
          .toSet();
      _count = actual.length;
      if (requests.any(
        (r) => r.at.isAfter(DateTime.now()) && !actual.contains(r.id),
      )) {
        throw StateError('安卓未保留全部提醒');
      }
      _healthy = true;
    });
    final tracked = operation.catchError((Object error, StackTrace stack) {
      _healthy = false;
      Error.throwWithStackTrace(error, stack);
    });
    _queue = tracked.catchError((Object _) {});
    return tracked;
  }

  @override
  Future<void> flush() => _queue;
}
