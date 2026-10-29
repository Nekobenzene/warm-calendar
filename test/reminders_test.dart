import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/reminders.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/recurrence.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/platform/notification_api.dart';
import 'package:warm_calendar/ui/reminder_editor.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;

ScheduleEvent sample({
  String id = 'e',
  List<int> offsets = const [60, 10, 0],
  DateTime? start,
  bool sound = true,
}) => ScheduleEvent(
  id: id,
  title: '多次提醒',
  start: start ?? DateTime(2026, 10, 29, 15),
  end: (start ?? DateTime(2026, 10, 29, 15)).add(const Duration(hours: 1)),
  updatedAt: DateTime(2026),
  reminderOffsets: offsets,
  reminderSound: sound,
);

class FakeNotifications extends NotificationBackend {
  @override
  bool get supportsScheduling => true;
  @override
  String get permission => 'granted';
  List<ReminderRequest> planned = [];
  int immediate = 0;
  bool fail = false;
  final List<bool> sounds = [];
  @override
  bool get schedulingHealthy => !fail;
  @override
  bool hasScheduledReminder(String key) => planned.any((r) => r.key == key);
  @override
  Future<void> reconcile(List<ReminderRequest> requests) async {
    if (fail) throw StateError('queue unavailable');
    planned = requests;
  }

  @override
  Future<void> show(
    String title,
    String body, {
    bool sound = true,
    String? eventId,
  }) async {
    immediate++;
    sounds.add(sound);
  }
}

void main() {
  test('旧单次提醒迁移、多提醒备份及重复实例保留', () async {
    final old = sample().toJson()
      ..remove('reminderOffsets')
      ..['reminderMinutes'] = 15;
    expect(ScheduleEvent.fromJson(old).reminderOffsets, [15]);
    old['reminderMinutes'] = null;
    expect(ScheduleEvent.fromJson(old).reminderOffsets, isEmpty);
    final event = sample(offsets: [2880, 90, 0], sound: false);
    final restored = BackupData.decode(
      BackupData([event], const AppSettings()).encode(),
    ).events.single;
    expect(restored.reminderOffsets, [2880, 90, 0]);
    expect(restored.reminderSound, false);
    expect(restored.copyWith(completed: true).reminderOffsets, [2880, 90, 0]);
    final calendar = CalendarService();
    await calendar.load();
    final template = ScheduleEvent(
      id: 'series',
      title: '重复',
      start: event.start,
      end: event.end,
      updatedAt: event.updatedAt,
      reminderOffsets: event.reminderOffsets,
      reminderSound: false,
      recurrence: RecurrenceRule(
        frequency: RepeatFrequency.daily,
        until: DateTime(2026, 10, 31),
        minutes: [900],
      ),
    );
    expect(
      expandSeries(
        template,
        calendar,
      ).every((e) => e.reminderOffsets.length == 3 && !e.reminderSound),
      true,
    );
  });
  test('提醒数据拒绝重复、负值、超量和非法类型', () {
    for (final offsets in [
      [1, 1],
      [-1],
      [525601],
      List.generate(13, (i) => i),
    ]) {
      expect(
        () => ScheduleEvent.fromJson(sample(offsets: offsets).toJson()),
        throwsFormatException,
      );
    }
    expect(reminderLabel(1535), '提前1天1小时35分钟');
  });
  test('排队只取未来30天最近512条，稳定ID、静音及总开关', () {
    final now = DateTime(2026, 10, 29, 14, 30);
    final list = planReminders(
      [sample(sound: false)],
      const AppSettings(),
      now,
    );
    expect(list.map((e) => e.offset), [10, 0]);
    expect(list.every((e) => !e.sound), true);
    expect(
      list.map((e) => e.id),
      planReminders(
        [sample(sound: false)],
        const AppSettings(),
        now,
      ).map((e) => e.id),
    );
    expect(
      planReminders(
        [sample()],
        const AppSettings(remindersEnabled: false),
        now,
      ),
      isEmpty,
    );
    expect(
      planReminders(
        [sample()],
        const AppSettings(systemNotificationsEnabled: false),
        now,
      ),
      isEmpty,
    );
    final many = [
      for (var i = 0; i < 600; i++)
        sample(
          id: '$i',
          offsets: [0],
          start: now.add(Duration(minutes: i + 1)),
        ),
    ];
    final queue = planReminders(many, const AppSettings(), now);
    expect(queue.length, 512);
    expect(queue.map((e) => e.id).toSet().length, 512);
    expect(
      planReminders(
        [
          sample(start: now.add(const Duration(days: 31)), offsets: [0]),
        ],
        const AppSettings(),
        now,
      ),
      isEmpty,
    );
  });
  test('每个提前量分别触发，系统排队时不再即时重复发送，完成删除撤销', () async {
    final notifications = FakeNotifications();
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
      notifications: notifications,
    );
    await c.initialize(startTimer: false);
    c.now = DateTime(2026, 10, 29, 13);
    final event = sample();
    await c.saveEvent(event);
    expect(notifications.planned.length, 3);
    await c.refreshTime(at: DateTime(2026, 10, 29, 14));
    expect(c.dueReminders.single.id, 'e');
    c.dismissReminder(event);
    await c.refreshTime(at: DateTime(2026, 10, 29, 14, 49));
    expect(c.dueReminders, isEmpty);
    await c.refreshTime(at: DateTime(2026, 10, 29, 14, 50));
    expect(c.dueReminders.length, 1);
    expect(notifications.immediate, 0);
    await c.toggleCompleted(event);
    expect(notifications.planned, isEmpty);
    await c.toggleCompleted(event);
    expect(notifications.planned.length, 1);
    await c.deleteEvent(event);
    expect(notifications.planned, isEmpty);
    c.dispose();
  });
  test('排定失败仍保存日程并在一分钟后重试', () async {
    final notifications = FakeNotifications();
    final repo = MemoryRepository();
    final c = AppController(
      repository: repo,
      calendar: CalendarService(),
      notifications: notifications,
    );
    await c.initialize(startTimer: false);
    c.now = DateTime(2026, 10, 29, 13);
    notifications.fail = true;
    await c.saveEvent(sample());
    expect(repo.rows.containsKey('e'), true);
    expect(c.notificationError, contains('系统定时提醒暂不可用'));
    notifications.fail = false;
    await c.refreshTime(at: DateTime(2026, 10, 29, 13, 1));
    expect(notifications.planned.length, 3);
    expect(c.notificationError, isNull);
    c.dispose();
  });
  test('排定失败时到点改发即时通知，遵循声音设置且不重复发送', () async {
    final backend = FakeNotifications()..fail = true;
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
      notifications: backend,
    );
    await c.initialize(startTimer: false);
    c.now = DateTime(2026, 10, 29, 13);
    await c.saveEvent(sample());
    await c.refreshTime(at: DateTime(2026, 10, 29, 14));
    expect(backend.immediate, 1);
    expect(backend.sounds, [true]);
    await c.refreshTime(at: DateTime(2026, 10, 29, 14, 0, 1));
    expect(backend.immediate, 1);
    await c.updateSettings(c.settings.copyWith(notificationSound: false));
    await c.refreshTime(at: DateTime(2026, 10, 29, 14, 50));
    expect(backend.sounds, [true, false]);
    expect(c.notificationErrorDetail, contains('queue unavailable'));
    c.dispose();
  });
  test('部分排队成功后失败，不重复发送已排定的提醒', () async {
    final backend = FakeNotifications();
    final c = AppController(
      repository: MemoryRepository(),
      calendar: CalendarService(),
      notifications: backend,
    );
    await c.initialize(startTimer: false);
    c.now = DateTime(2026, 10, 29, 13);
    await c.saveEvent(sample());
    backend.fail = true;
    await c.refreshTime(at: DateTime(2026, 10, 29, 14));
    expect(backend.immediate, 0);
    expect(c.dueReminders.length, 1);
    c.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('多选预设、自定义提前量、清空取消和提示音，文字$scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      ReminderSelection? result;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editReminders(context, [10], true);
              },
              child: const Text('设置提醒'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '开始时'));
      await tester.pump();
      final amount = find.byKey(const ValueKey('custom-reminder-amount'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '90');
      final add = find.text(scale == 1 ? '添加提醒' : '添加提醒');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      expect(find.widgetWithText(InputChip, '提前1小时30分钟'), findsOneWidget);
      await tester.ensureVisible(find.text('提示音'));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('应用提醒'));
      await tester.pumpAndSettle();
      expect(result!.offsets, [90, 10, 0]);
      expect(result!.sound, false);
      expect(tester.takeException(), isNull);
      result = null;
      await tester.tap(find.text('设置提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空提醒'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  }
}
