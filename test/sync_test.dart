import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:warm_calendar/data/repository.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/sync/link_api.dart';
import 'package:warm_calendar/sync/link_controller.dart';
import 'package:warm_calendar/sync/link_credentials.dart';
import 'package:warm_calendar/sync/link_models.dart';
import 'package:warm_calendar/sync/sync_store.dart';
import 'package:warm_calendar/ui/link_page.dart';
import 'recurrence_test.dart' show testApp;
import 'repeating_todos_test.dart' as repeat_fixture;
import 'package:warm_calendar/domain/todos.dart';
import 'package:warm_calendar/domain/calendar_service.dart';

// Widget bindings replace the global HTTP transport. These two clients exercise
// the real loopback service without changing that override for other tests.
class IntegrationHttpOverrides extends HttpOverrides {}

LinkApi integrationApi() => LinkApi(
  client: IOClient(IntegrationHttpOverrides().createHttpClient(null)),
);

class MemoryCredentials extends LinkCredentialsStore {
  String? value;
  String? registrations;
  @override
  Future<String?> readRegistrations() async => registrations;
  @override
  Future<void> writeRegistrations(String value) async {
    registrations = value;
  }

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String input) async {
    value = input;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

ScheduleEvent example({String id = 'local', bool completed = false}) =>
    ScheduleEvent(
      id: id,
      title: '同步日程',
      start: DateTime(2026, 10, 29, 20),
      end: DateTime(2026, 10, 29, 21),
      updatedAt: DateTime(2026, 10, 29),
      reminderOffsets: [60, 10, 0],
      reminderSound: false,
      completed: completed,
      color: 0x80e4ead9,
      completedColor: 0x80556677,
    );

void main() {
  test('连接码仅包含短期凭据，解析与服务地址限制', () {
    final input = PairCode(Uri.parse('http://192.168.1.4:4280'), 'a' * 43);
    final output = PairCode.parse(input.encode());
    expect(output.server, input.server);
    expect(output.invite, input.invite);
    for (final address in [
      'http://example.com',
      'file:///tmp/test',
      'http://999.1.1.1',
      'https://a.com/?token=bad',
      'https://user:pass@a.com',
    ]) {
      expect(() => validateSyncServer(address), throwsFormatException);
    }
    expect(validateSyncServer('https://example.com').scheme, 'https');
    expect(() => PairCode.parse('https://example.com'), throwsFormatException);
  });
  test('上传期间新编辑保留，远端写入不产生回传循环，游标与应用原子保存', () async {
    final db = CalendarDatabase(NativeDatabase.memory());
    final repo = SqliteScheduleRepository(db), store = SqliteSyncStore(db);
    await store.initialize();
    final first = example();
    await repo.saveEvent(first);
    final snapshot = await store.pending();
    final edit = ScheduleEvent.fromJson({
      ...first.toJson(),
      'title': '上传期间修改',
      'revision': first.revision + 1,
    });
    await repo.saveEvent(edit);
    await store.apply([first], snapshot, 'group', 1);
    expect((await repo.loadEvents()).single.title, '上传期间修改');
    expect((await store.pending()).length, 1);
    final current = await store.pending();
    await store.apply([edit], current, 'group', 2);
    expect(await store.pending(), isEmpty);
    await store.apply([edit.copyWith(completed: true)], [], 'group', 3);
    expect((await repo.loadEvents()).single.completed, true);
    expect(await store.pending(), isEmpty);
    expect((await store.position()).cursor, 3);
    await store.seed();
    expect((await store.position()).cursor, 0);
    expect((await store.pending()).length, 1);
    await db.close();
  });
  test('两个真实HTTP客户端完成配对确认、双向同步、删除与断开', () async {
    final server = await Process.start('node', [
      '--input-type=module',
      '-e',
      "import {createSyncServer} from './sync-server/server.mjs'; const app=createSyncServer(); app.server.listen(0,'127.0.0.1',()=>console.log('PORT:'+app.server.address().port));",
    ], workingDirectory: Directory.current.path);
    server.stderr.drain<void>();
    final portLine = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line.startsWith('PORT:'));
    final base = 'http://127.0.0.1:${portLine.substring(5)}';
    final aDb = CalendarDatabase(NativeDatabase.memory()),
        bDb = CalendarDatabase(NativeDatabase.memory());
    final aRepo = SqliteScheduleRepository(aDb),
        bRepo = SqliteScheduleRepository(bDb);
    final desktop = LinkController(
      store: SqliteSyncStore(aDb),
      credentials: MemoryCredentials(),
      platform: 'desktop',
      api: integrationApi(),
    );
    final mobile = LinkController(
      store: SqliteSyncStore(bDb),
      credentials: MemoryCredentials(),
      platform: 'android',
      api: integrationApi(),
    );
    try {
      await aRepo.saveEvent(example());
      await bRepo.saveEvent(example(id: 'phone-local'));
      await desktop.initialize(startPolling: false);
      await mobile.initialize(startPolling: false);
      await desktop.connect(base);
      await mobile.requestPair(desktop.qrData!);
      await mobile.poll(force: true);
      expect(mobile.linked, false);
      expect((await bRepo.loadEvents()).length, 1);
      await desktop.poll(force: true);
      expect(desktop.requests.length, 1);
      expect(desktop.requests.single['code'], mobile.waitingRequest!['code']);
      await desktop.confirmPair(
        desktop.requests.single['requestId'] as String,
        true,
      );
      await mobile.poll(force: true);
      await desktop.poll(force: true);
      expect(mobile.linked, true);
      expect(desktop.linked, true);
      await aRepo.saveSettings(
        const AppSettings(
          autoCompleteExpired: true,
          autoCompleteTodos: true,
          calendarLocked: true,
          deviceName: '工作电脑',
        ),
      );
      desktop.deviceName = '工作电脑';
      await desktop.poll(force: true);
      await mobile.poll(force: true);
      expect((await bRepo.loadSettings()).autoCompleteExpired, true);
      expect((await bRepo.loadSettings()).autoCompleteTodos, true);
      expect((await bRepo.loadSettings()).calendarLocked, false);
      expect((await bRepo.loadSettings()).deviceName, isEmpty);
      await bRepo.saveSettings(
        (await bRepo.loadSettings()).copyWith(
          autoCompleteExpired: false,
          autoCompleteTodos: false,
        ),
      );
      await mobile.poll(force: true);
      await desktop.poll(force: true);
      expect((await aRepo.loadSettings()).autoCompleteExpired, false);
      expect((await aRepo.loadSettings()).autoCompleteTodos, false);
      expect((await aRepo.loadSettings()).calendarLocked, true);
      expect(
        desktop.devices.firstWhere(
          (d) => d['id'] == desktop.identity!.deviceId,
        )['name'],
        '工作电脑',
      );
      expect((await bRepo.loadEvents()).length, 2);
      expect((await aRepo.loadEvents()).length, 2);
      final received = (await bRepo.loadEvents()).firstWhere(
        (e) => e.id == 'local',
      );
      expect(received.reminderOffsets, [60, 10, 0]);
      expect(received.color, 0x80e4ead9);
      await bRepo.saveEvent(received.copyWith(completed: true));
      await mobile.poll(force: true);
      await desktop.poll(force: true);
      expect(
        (await aRepo.loadEvents()).firstWhere((e) => e.id == 'local').completed,
        true,
      );
      await aRepo.saveEvent(
        (await aRepo.loadEvents())
            .firstWhere((e) => e.id == 'local')
            .copyWith(deleted: true),
      );
      await desktop.poll(force: true);
      await mobile.poll(force: true);
      expect(
        (await bRepo.loadEvents()).firstWhere((e) => e.id == 'local').deleted,
        true,
      );
      final todo = ScheduleEvent(
        id: 'synced-todo',
        title: '整理资料',
        notes: '待办备注',
        isTodo: true,
        hasDeadline: true,
        taskCreatedAt: DateTime.utc(2026, 11, 4),
        todoOrder: 2,
        start: DateTime(2026, 11, 8, 10),
        end: DateTime(2026, 11, 8, 10),
        reminderOffsets: const [],
        updatedAt: DateTime.now().toUtc(),
        color: 0x80e4ead9,
      );
      await aRepo.saveEvent(todo);
      await desktop.poll(force: true);
      await mobile.poll(force: true);
      final receivedTodo = (await bRepo.loadEvents()).firstWhere(
        (e) => e.id == todo.id,
      );
      expect(receivedTodo.toJson(), todo.toJson());
      await bRepo.saveEvent(
        receivedTodo.copyWith(completed: true, todoOrder: 0),
      );
      await mobile.poll(force: true);
      await desktop.poll(force: true);
      final updatedTodo = (await aRepo.loadEvents()).firstWhere(
        (e) => e.id == todo.id,
      );
      expect(updatedTodo.completed, true);
      expect(updatedTodo.todoOrder, 0);
      expect(updatedTodo.createdAt, todo.createdAt);
      await desktop.unlink(mobile.identity!.deviceId);
      await mobile.poll(force: true);
      expect(mobile.linked, false);
      expect((await bRepo.loadEvents()).length, 3);
      final originalId = mobile.identity!.deviceId;
      await desktop.refreshQr();
      await mobile.requestPair(desktop.qrData!);
      await desktop.poll(force: true);
      await desktop.confirmPair(
        desktop.requests.single['requestId'] as String,
        true,
      );
      await mobile.poll(force: true);
      expect(mobile.identity!.deviceId, originalId);
      expect(mobile.devices.length, 2);
      final repeatGroup = repeat_fixture.group(
        title: '',
        nodes: [
          repeat_fixture.node('node', title: '每轮整理', removeAfterCycle: false),
        ],
      );
      await aRepo.saveEvent(repeatGroup);
      await desktop.poll(force: true);
      await mobile.poll(force: true);
      final receivedGroup = (await bRepo.loadEvents()).firstWhere(
        (e) => e.id == repeatGroup.id,
      );
      expect(receivedGroup.toJson(), repeatGroup.toJson());
      expect(receivedGroup.todoRepeat!.nodes.single.removeAfterCycle, false);
      final currentRepeat = resolveTodos(
        [receivedGroup],
        CalendarService(),
        DateTime(2026, 11, 5),
      ).single;
      await bRepo.saveEvent(
        currentRepeat.copyWith(completed: true, todoOrder: 0),
      );
      await mobile.poll(force: true);
      await desktop.poll(force: true);
      final resolvedRepeat = resolveTodos(
        await aRepo.loadEvents(),
        CalendarService(),
        DateTime(2026, 11, 5),
      ).firstWhere((e) => e.id == currentRepeat.id);
      expect(resolvedRepeat.completed, true);
      expect(resolvedRepeat.reminderOffsets, [10]);
      final nextCycle = resolveTodos(
        await aRepo.loadEvents(),
        CalendarService(),
        DateTime(2026, 11, 6),
      ).where((e) => e.seriesId == repeatGroup.id).toList();
      expect(nextCycle, hasLength(2));
      expect(
        nextCycle.singleWhere((e) => e.id == currentRepeat.id).completed,
        true,
      );
      // Loss of the active token still has a stable installation proof.
      await mobile.credentials.clear();
      mobile.identity = null;
      mobile.connection = null;
      await mobile.connect(base);
      await mobile.poll(force: true);
      expect(mobile.identity!.deviceId, originalId);
      expect(mobile.linked, true);
      expect(mobile.devices.length, 2);
    } finally {
      desktop.dispose();
      mobile.dispose();
      await aDb.close();
      await bDb.close();
      server.kill();
      await server.exitCode;
    }
  });
  test('共享设置上传期间的新修改不被旧响应覆盖，普通设置不排队', () async {
    final db = CalendarDatabase(NativeDatabase.memory());
    final repo = SqliteScheduleRepository(db), store = SqliteSyncStore(db);
    await store.initialize();
    expect(await store.pendingPreferences(), isNull);
    await repo.saveSettings(
      const AppSettings(
        autoCompleteExpired: true,
        calendarLocked: true,
        deviceName: '手机',
      ),
    );
    final sent = await store.pendingPreferences();
    await repo.saveSettings(
      (await repo.loadSettings()).copyWith(autoCompleteExpired: false),
    );
    await store.applyPreferences({'autoCompleteExpired': true}, sent);
    expect((await repo.loadSettings()).autoCompleteExpired, false);
    expect(await store.pendingPreferences(), isNotNull);
    final newest = await store.pendingPreferences();
    await store.applyPreferences({'autoCompleteExpired': false}, newest);
    expect(await store.pendingPreferences(), isNull);
    await store.applyPreferences({'autoCompleteExpired': true}, null);
    final settings = await repo.loadSettings();
    expect(settings.autoCompleteExpired, true);
    expect(settings.calendarLocked, true);
    expect(settings.deviceName, '手机');
    await repo.saveSettings(settings.copyWith(notificationSound: false));
    expect(await store.pendingPreferences(), isNull);
    await db.close();
  });
  for (final width in [1280.0, 390.0]) {
    testWidgets('链接页空状态和手机操作在宽度$width可访问', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = CalendarDatabase(NativeDatabase.memory());
      final link = LinkController(
        store: SqliteSyncStore(db),
        credentials: MemoryCredentials(),
        platform: 'android',
        api: LinkApi(),
      );
      await tester.pumpWidget(
        testApp(SingleChildScrollView(child: LinkPage(controller: link))),
      );
      expect(find.text('扫码连接电脑'), findsOneWidget);
      expect(find.text('输入连接码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      link.dispose();
      await db.close();
    });
  }
}
