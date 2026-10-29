import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/data/repository.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/platform/notification_api.dart';
import 'package:warm_calendar/platform/notification_windows.dart' as windows;
import 'package:drift/native.dart';

class StartupBackend extends NotificationBackend {
  final bool? systemValue;
  bool? applied;
  StartupBackend(this.systemValue);
  @override
  Future<bool?> readLaunchAtStartup() async => systemValue;
  @override
  Future<void> applyDesktopSettings(AppSettings settings) async {
    applied = settings.launchAtStartup;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final value in [true, false, null]) {
    test('系统安装自启动选择 $value 在初始化时保存且不会被旧设置覆盖', () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      final repository = SqliteScheduleRepository(db);
      final previous = value != true;
      await repository.saveSettings(
        AppSettings(launchAtStartup: previous, deviceName: '我的电脑'),
      );
      final backend = StartupBackend(value);
      final controller = AppController(
        repository: repository,
        calendar: CalendarService(),
        notifications: backend,
      );
      await controller.initialize(startTimer: false);
      final expected = value ?? previous;
      expect(controller.error, isNull);
      expect(controller.settings.launchAtStartup, expected);
      expect(backend.applied, expected);
      expect((await repository.loadSettings()).launchAtStartup, expected);
      expect(controller.settings.deviceName, '我的电脑');
      controller.dispose();
    });
  }

  test('Windows启动状态使用原生通道读取，与通知初始化无关', () async {
    const channel = MethodChannel('warm_calendar/windows');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
    final service = windows.NotificationService(verification: true);
    expect(await service.readLaunchAtStartup(), isTrue);
    expect(calls, ['startupEnabled']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    service.dispose();
  });
}
