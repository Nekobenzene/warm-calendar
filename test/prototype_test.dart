import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/data/repository.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/home_summary.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'package:warm_calendar/ui/home_page.dart';
import 'package:warm_calendar/ui/components.dart';
import 'package:warm_calendar/ui/theme.dart';

class MemoryRepository implements ScheduleRepository {
  final Map<String, ScheduleEvent> rows = {};
  AppSettings settings = const AppSettings();
  bool failWrites = false;
  @override
  Future<List<ScheduleEvent>> loadEvents() async => rows.values.toList();
  @override
  Future<AppSettings> loadSettings() async => settings;
  @override
  Future<void> saveEvent(ScheduleEvent e) async {
    if (failWrites) throw StateError('disk full');
    rows[e.id] = e;
  }

  @override
  Future<void> saveEvents(List<ScheduleEvent> events) async {
    if (failWrites) throw StateError('disk full');
    for (final e in events) {
      rows[e.id] = e;
    }
  }

  @override
  Future<void> saveSettings(AppSettings s) async {
    settings = s;
  }

  @override
  Future<void> mergeBackup(BackupData b) async {
    for (final e in b.events) {
      if (rows[e.id] == null || e.updatedAt.isAfter(rows[e.id]!.updatedAt)) {
        rows[e.id] = e;
      }
    }
    settings = b.settings;
  }

  @override
  Future<void> close() async {}
}

ScheduleEvent fixture({bool allDay = false}) => ScheduleEvent(
  id: 'test-1',
  title: '日程核验',
  start: DateTime(2026, 10, 28, allDay ? 0 : 9),
  end: DateTime(2026, 10, allDay ? 29 : 28, allDay ? 0 : 10),
  updatedAt: DateTime.utc(2026, 10, 28),
  allDay: allDay,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('下一项排除已完成、已删除、已开始，倒计时跨日且不出现负值', () {
    final now = DateTime(2026, 10, 28, 9);
    ScheduleEvent event(String id, DateTime start) => ScheduleEvent(
      id: id,
      title: id,
      start: start,
      end: start.add(const Duration(hours: 1)),
      updatedAt: now,
      reminderMinutes: null,
    );
    final future = event('未来', now.add(const Duration(days: 2)));
    final next = event('下一项', now.add(const Duration(minutes: 30)));
    final rows = [
      future,
      event('已开始', now),
      event('过期', now.subtract(const Duration(days: 1))),
      event(
        '已完成',
        now.add(const Duration(minutes: 1)),
      ).copyWith(completed: true),
      event('已删除', now.add(const Duration(minutes: 2))).copyWith(deleted: true),
      next,
    ];
    expect(nextScheduledEvent(rows, now)?.id, next.id);
    expect(nextScheduledEvent(rows, future.start), isNull);
    expect(
      countdownText(
        now.add(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
        now,
      ),
      '2天 03:04:05',
    );
    expect(
      countdownText(now.add(const Duration(milliseconds: 1)), now),
      '00:00:01',
    );
    expect(countdownText(now, now), '00:00:00');
    expect(
      countdownText(now.subtract(const Duration(seconds: 1)), now),
      '00:00:00',
    );
  });
  test('日程状态、全天排他结束和 UTC 备份往返', () {
    final e = fixture();
    expect(e.statusAt(DateTime(2026, 10, 28, 8)), ScheduleStatus.pending);
    expect(e.statusAt(DateTime(2026, 10, 28, 9, 30)), ScheduleStatus.ongoing);
    expect(
      e.copyWith(completed: true).statusAt(DateTime(2026, 10, 28, 9, 30)),
      ScheduleStatus.completed,
    );
    expect(e.statusAt(DateTime(2026, 10, 28, 10)), ScheduleStatus.overdue);
    expect(e.statusAt(DateTime(2026, 10, 28, 11)), ScheduleStatus.overdue);
    final allDay = fixture(allDay: true);
    expect(allDay.occursOn(DateTime(2026, 10, 28)), isTrue);
    expect(allDay.occursOn(DateTime(2026, 10, 29)), isFalse);
    final backup = BackupData.decode(
      BackupData(
        [e, allDay.copyWith(deleted: true)],
        const AppSettings(),
      ).encode().replaceFirst('"id": "test-1"', '"id": "test-2"'),
    );
    expect(backup.events[0].start, e.start);
    expect(backup.events[1].allDay, isTrue);
    expect(backup.events[1].start, allDay.start);
    expect(() => BackupData.decode('{"events": []}'), throwsFormatException);
  });
  test('农历、节气和法定调休从不同数据源计算', () async {
    final calendar = CalendarService();
    await calendar.load();
    expect(calendar.info(DateTime(2026, 2, 17)).lunar, '正月初一');
    expect(calendar.info(DateTime(2026, 11, 7)).solarTerm, '立冬');
    expect(calendar.info(DateTime(2026, 10, 1)).holiday!.isOffDay, isTrue);
    expect(calendar.info(DateTime(2026, 1, 4)).holiday!.isOffDay, isFalse);
    expect(calendar.info(DateTime(2027, 1, 1)).holidayYearKnown, isFalse);
  });
  test('写入失败不改变列表，完成和软删除可持久化', () async {
    final repo = MemoryRepository();
    final c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    await c.saveEvent(fixture());
    expect(c.events, hasLength(1));
    repo.failWrites = true;
    await expectLater(c.deleteEvent(c.events.first), throwsStateError);
    expect(c.events, hasLength(1));
    repo.failWrites = false;
    await c.toggleCompleted(c.events.first);
    expect(c.events.first.completed, isTrue);
    await c.deleteEvent(c.events.first);
    expect(c.events, isEmpty);
    expect(repo.rows.values.first.deleted, isTrue);
    c.dispose();
  });
  test('SQLite 重新打开保留日程、设置和删除记录，备份合并保留新版本', () async {
    final file = File(
      '${Directory.systemTemp.path}/warm-calendar-test-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    var repo = SqliteScheduleRepository(CalendarDatabase(NativeDatabase(file)));
    addTearDown(() async {
      await repo.close();
      if (await file.exists()) await file.delete();
    });
    final event = fixture().copyWith(completed: true);
    await repo.saveEvent(event);
    await repo.saveSettings(
      const AppSettings(
        hour24: false,
        snapToGrid: false,
        autoCompleteExpired: true,
      ),
    );
    await repo.close();
    repo = SqliteScheduleRepository(CalendarDatabase(NativeDatabase(file)));
    expect((await repo.loadEvents()).single.completed, isTrue);
    expect((await repo.loadSettings()).hour24, isFalse);
    expect((await repo.loadSettings()).snapToGrid, false);
    expect((await repo.loadSettings()).autoCompleteExpired, isTrue);
    await repo.mergeBackup(BackupData([fixture()], const AppSettings()));
    expect((await repo.loadEvents()).single.completed, isTrue);
    await repo.saveEvent(event.copyWith(deleted: true));
    expect((await repo.loadEvents()).single.deleted, isTrue);
    expect(
      await repo.db.customSelect('SELECT * FROM outbox').get(),
      hasLength(1),
    );
  });
  test('自动完成默认关闭，开启、到期、启动补处理及写入失败重试', () async {
    final repo = MemoryRepository();
    var c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    final now = DateTime.now();
    c.now = now;
    final expired = ScheduleEvent(
      id: 'expired',
      title: '逾期',
      start: now.subtract(const Duration(hours: 2)),
      end: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
      reminderMinutes: null,
    );
    final future = ScheduleEvent(
      id: 'future',
      title: '稍后',
      start: now.add(const Duration(minutes: 1)),
      end: now.add(const Duration(minutes: 2)),
      updatedAt: now,
      reminderMinutes: null,
    );
    await c.saveEvent(expired);
    await c.saveEvent(future);
    expect(c.events.first.statusAt(now), ScheduleStatus.overdue);
    expect(repo.rows['expired']!.completed, isFalse);
    repo.failWrites = true;
    await c.updateSettings(c.settings.copyWith(autoCompleteExpired: true));
    expect(c.automationError, isNotNull);
    expect(repo.rows['expired']!.completed, isFalse);
    repo.failWrites = false;
    await c.refreshTime(at: now);
    expect(c.automationError, isNull);
    expect(repo.rows['expired']!.completed, isTrue);
    expect(repo.rows['expired']!.revision, expired.revision + 1);
    expect(repo.rows['future']!.completed, isFalse);
    await c.refreshTime(at: future.end);
    expect(repo.rows['future']!.completed, isTrue);
    c.dispose();
    repo.rows['catchup'] = ScheduleEvent(
      id: 'catchup',
      title: '关闭时已过期',
      start: now.subtract(const Duration(days: 1)),
      end: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
      reminderMinutes: null,
    );
    c = AppController(repository: repo, calendar: CalendarService());
    await c.initialize(startTimer: false);
    expect(repo.rows['catchup']!.completed, isTrue);
    await c.updateSettings(c.settings.copyWith(autoCompleteExpired: false));
    await c.toggleCompleted(c.events.firstWhere((e) => e.id == 'expired'));
    await c.refreshTime();
    expect(repo.rows['expired']!.completed, isFalse);
    expect(AppSettings.fromJson({}).autoCompleteExpired, isFalse);
    expect(AppSettings.fromJson({}).snapToGrid, true);
    c.dispose();
  });
  testWidgets('选项菜单、取消删除、确认后右下提示及恢复未完成', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryRepository();
    final now = DateTime.now();
    final event = ScheduleEvent(
      id: 'menu-event',
      title: '菜单核验事项',
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 2)),
      updatedAt: now,
      reminderMinutes: null,
      completed: true,
    );
    repo.rows[event.id] = event;
    final c = AppController(repository: repo, calendar: CalendarService());
    await tester.runAsync(() => c.initialize(startTimer: false));
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        home: AppShell(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final options = find.byKey(ValueKey('event-options-${event.id}'));
    await tester.tap(find.text(event.title));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(options));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('选项'), findsOneWidget);
    final hoverRect = tester.getRect(options);
    await c.refreshTime(at: now.add(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(options), hoverRect);
    expect(find.text('选项'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '标题'), findsOneWidget);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    await tester.tap(find.text('标为未完成'));
    await tester.pumpAndSettle();
    expect(c.events.single.completed, isFalse);
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除日程'), findsOneWidget);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.events, hasLength(1));
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(c.events, isEmpty);
    expect(repo.rows[event.id]!.deleted, isTrue);
    expect(find.text('日程已删除'), findsOneWidget);
    final toastPosition = tester.getCenter(find.text('日程已删除'));
    expect(toastPosition.dx, greaterThan(1000));
    expect(toastPosition.dy, greaterThan(650));
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text('日程已删除'), findsNothing);
    showMessage(tester.element(find.byType(AppShell)), '自动消失核验');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('自动消失核验'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('自动消失核验'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final size in [
    const Size(1366, 768),
    const Size(1280, 720),
    const Size(390, 844),
  ]) {
    testWidgets(
      '有数据的首页在 ${size.width.toInt()}×${size.height.toInt()} 布局、列表和跳转可用',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime(2026, 10, 1, 12);
        ScheduleEvent event(
          String id,
          DateTime start, {
          bool completed = false,
        }) => ScheduleEvent(
          id: id,
          title: id,
          start: start,
          end: start.add(const Duration(hours: 1)),
          updatedAt: now,
          completed: completed,
          reminderMinutes: null,
        );
        final repo = MemoryRepository();
        final ongoing = event(
          '进行中的事项',
          now.subtract(const Duration(minutes: 30)),
        );
        final completed = event(
          '已完成的事项',
          now.subtract(const Duration(hours: 2)),
          completed: true,
        );
        final overdue = event('过期仍未完成', now.subtract(const Duration(hours: 3)));
        final next = event(
          '下一项很长的中文日程标题用于核验换行后开始时间与剩余时间依然可见',
          now.add(const Duration(minutes: 30)),
        );
        for (final e in [
          ongoing,
          completed,
          overdue,
          next,
          for (var i = 1; i <= 14; i++)
            event('后续事项$i', now.add(Duration(minutes: (i + 1) * 30))),
        ]) {
          repo.rows[e.id] = e;
        }
        final c = AppController(repository: repo, calendar: CalendarService());
        await tester.runAsync(() => c.initialize(startTimer: false));
        c.now = now;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            home: AppShell(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('00:30:00'), findsOneWidget);
        expect(
          tester.getBottomRight(find.byType(HomePage)).dy,
          lessThanOrEqualTo(size.height),
        );
        if (size.width >= 900) {
          expect(find.text('过期仍未完成'), findsOneWidget);
          expect(find.byKey(const ValueKey('home-overflow')), findsNothing);
          expect(find.text('进行中的事项'), findsOneWidget);
          expect(find.text('已完成的事项'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('upcoming-rows-control')),
            findsNothing,
          );
          final clockPosition = tester.getTopLeft(find.text('UTC'));
          await tester.drag(
            find.byKey(const ValueKey('home-list-pending')),
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          expect(find.text('后续事项14'), findsOneWidget);
          expect(tester.getTopLeft(find.text('UTC')), clockPosition);
        } else {
          await tester.ensureVisible(find.text('逾期 1'));
          await tester.tap(find.text('逾期 1'));
          await tester.pumpAndSettle();
          expect(find.text('过期仍未完成'), findsOneWidget);
          await tester.ensureVisible(find.text('进行中 1'));
          await tester.tap(find.text('进行中 1'));
          await tester.pumpAndSettle();
          expect(find.text('进行中的事项'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('查看全部进行中日程'));
        await tester.tap(find.text('查看全部进行中日程'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('进行中的事项'), findsOneWidget);
        expect(find.text('已完成的事项'), findsNothing);
        await tester.tap(find.text('首页').first);
        await tester.pumpAndSettle();
        if (size.width >= 900) {
          expect(find.byKey(const ValueKey('home-overflow')), findsNothing);
          await tester.ensureVisible(
            find.byKey(ValueKey('event-options-${ongoing.id}')),
          );
          await tester.tap(find.byKey(ValueKey('event-options-${ongoing.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('标为已完成'));
          await tester.pumpAndSettle();
          expect(
            c.events.singleWhere((e) => e.id == ongoing.id).completed,
            isTrue,
          );
          expect(find.text('暂无进行中日程'), findsOneWidget);
          await tester.tap(find.text(next.title).first);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(TextFormField, '标题'), findsOneWidget);
          await tester.ensureVisible(find.text('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        c.dispose();
      },
    );
  }
  for (final scenario in [
    (const Size(1366, 768), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(1366, 768), 2.0),
  ]) {
    final size = scenario.$1;
    testWidgets('四页和表单在 ${size.width.toInt()} 宽度、${scenario.$2}倍文字可用', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = AppController(
        repository: MemoryRepository(),
        calendar: CalendarService(),
      );
      await tester.runAsync(() => c.initialize(startTimer: false));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          home: AppShell(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'^UTC(?: |$)')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('upcoming-viewport'))).height,
        lessThanOrEqualTo(32 * scenario.$2),
      );
      expect(tester.takeException(), isNull);
      for (final name in ['日历', '日程', '设置', '首页']) {
        await tester.tap(find.text(name).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text(size.width < 600 ? '新建' : '新建日程').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存日程'));
      await tester.tap(find.text('保存日程'));
      await tester.pumpAndSettle();
      expect(find.text('请输入日程标题'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '很长的中文日程标题用于验证窄屏换行与完整编辑内容',
      );
      await tester.ensureVisible(find.text('保存日程'));
      await tester.tap(find.text('保存日程'));
      await tester.pumpAndSettle();
      expect(c.events, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
    });
  }
}
