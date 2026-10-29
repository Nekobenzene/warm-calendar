import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/reminders.dart';
import 'package:warm_calendar/platform/notification_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final pending = <int, Map<String, dynamic>>{};
  bool exact = true, allowed = true, failSchedule = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    pending.clear();
    exact = true;
    allowed = true;
    failSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'Asia/Shanghai',
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'requestNotificationsPermission':
              return allowed;
            case 'areNotificationsEnabled':
              return allowed;
            case 'canScheduleExactNotifications':
              return exact;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'pendingNotificationRequests':
              return pending.values.toList();
            case 'cancel':
              pending.remove((call.arguments as Map)['id']);
              return null;
            case 'zonedSchedule':
              if (failSchedule) {
                throw PlatformException(code: 'test_schedule_failed');
              }
              final args = Map<String, dynamic>.from(call.arguments as Map);
              pending[args['id'] as int] = {
                'id': args['id'],
                'title': args['title'],
                'body': args['body'],
                'payload': args['payload'],
              };
              return null;
            default:
              return null;
          }
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  ScheduleEvent event() {
    final start = DateTime.now().add(const Duration(hours: 1));
    return ScheduleEvent(
      id: 'android',
      title: '安卓提醒',
      start: start,
      end: start.add(const Duration(hours: 1)),
      updatedAt: start,
      reminderOffsets: const [0, 10],
    );
  }

  test('通知音量、高优先级、四种声音振动通道及旧设置兼容', () {
    final channels = <String>{};
    for (final sound in [true, false]) {
      for (final vibration in [true, false]) {
        final details = androidReminderDetails(
          sound: sound,
          vibration: vibration,
        );
        channels.add(details.channelId);
        expect(details.audioAttributesUsage, AudioAttributesUsage.notification);
        expect(details.importance, Importance.high);
        expect(details.playSound, sound);
        expect(details.enableVibration, vibration);
      }
    }
    expect(channels.length, 4);
    expect(AppSettings.fromJson({}).notificationVibration, isTrue);
    expect(
      AppSettings.fromJson(
        const AppSettings(notificationVibration: false).toJson(),
      ).notificationVibration,
      isFalse,
    );
  });
  test('排定幂等、修改振动重新排定、完成删除取消与失败可恢复', () async {
    final service = AndroidNotificationService();
    await service.initialize();
    final requests = planReminders(
      [event()],
      const AppSettings(),
      DateTime.now(),
      limit: 128,
    );
    await service.reconcile(requests);
    expect(service.scheduledCount, 2);
    expect(service.hasScheduledReminder(requests.first.key), isTrue);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').length;
    await service.reconcile(requests);
    expect(calls.where((c) => c.method == 'zonedSchedule').length, scheduled);
    final args =
        calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(
      (args['platformSpecifics'] as Map)['scheduleMode'],
      AndroidScheduleMode.exactAllowWhileIdle.name,
    );
    expect((jsonDecode(args['payload']) as Map)['eventId'], 'android');
    await service.applyDesktopSettings(
      const AppSettings(notificationVibration: false),
    );
    failSchedule = true;
    await expectLater(
      service.reconcile(requests),
      throwsA(isA<PlatformException>()),
    );
    expect(service.schedulingHealthy, isFalse);
    expect(service.hasScheduledReminder(requests.first.key), isFalse);
    failSchedule = false;
    await service.reconcile(requests);
    expect(service.schedulingHealthy, isTrue);
    await service.reconcile([]);
    expect(pending, isEmpty);
    expect(service.hasScheduledReminder(requests.first.key), isFalse);
    service.dispose();
  });
  test('未允许精确权限使用系统非精确排定，拒绝通知可检测且不伪报发送成功', () async {
    exact = false;
    allowed = false;
    final service = AndroidNotificationService(
      requestPermissionOnInitialize: false,
    );
    await service.initialize();
    expect(
      calls.any((c) => c.method == 'requestNotificationsPermission'),
      isFalse,
    );
    expect(service.permission, 'denied');
    await expectLater(service.testNotification(), throwsStateError);
    allowed = true;
    await service.reconcile(
      planReminders([event()], const AppSettings(), DateTime.now()),
    );
    final args =
        calls.lastWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(
      (args['platformSpecifics'] as Map)['scheduleMode'],
      AndroidScheduleMode.inexactAllowWhileIdle.name,
    );
    expect(service.permission, 'granted');
    service.dispose();
  });
}
