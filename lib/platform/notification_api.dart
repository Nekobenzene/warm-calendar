import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';

class NotificationBackend {
  Future<void> Function()? beforeExit;
  final ValueNotifier<String?> openedEvent = ValueNotifier(null);
  String get permission => 'unsupported';
  bool get supported => false;
  bool get desktop => false;
  bool get android => false;
  bool get exactAlarms => false;
  bool get diagnosticMode => false;
  bool get supportsScheduling => false;
  bool get schedulingHealthy => supportsScheduling;
  bool hasScheduledReminder(String key) => false;
  int get scheduledCount => 0;
  Future<void> initialize() async {}
  Future<String> requestPermission() async => permission;
  Future<void> refreshPermissions() async {}
  Future<void> requestExactAlarms() async {}
  Future<void> show(
    String title,
    String body, {
    bool sound = true,
    String? eventId,
  }) async {}
  Future<void> reconcile(List<ReminderRequest> requests) async {}
  // Windows installer and system startup settings are authoritative on launch.
  Future<bool?> readLaunchAtStartup() async => null;
  Future<void> applyDesktopSettings(AppSettings settings) async {}
  Future<void> openSystemSettings() async {}
  Future<void> showWindow() async {}
  Future<void> testNotification({bool sound = true}) =>
      show('日程表', '这是一条测试提醒', sound: sound);
  Future<void> flush() async {}
  Future<void> exitForUpdate() async {}
  void dispose() {
    openedEvent.dispose();
  }
}
