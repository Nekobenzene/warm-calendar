import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import '../data/repository.dart';
import '../domain/calendar_service.dart';
import '../domain/recurrence.dart';
import '../domain/reminders.dart';
import '../platform/notification_android.dart';
import 'link_controller.dart';
import 'link_credentials.dart';
import 'sync_store.dart';
import '../version.dart';

@pragma('vm:entry-point')
void calendarSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final db = CalendarDatabase(null, appDatabaseName);
    final notifications = AndroidNotificationService(
      requestPermissionOnInitialize: false,
    );
    final link = LinkController(
      store: SqliteSyncStore(db),
      credentials: SecureLinkCredentials(key: appCredentialKey),
      platform: 'android',
    );
    try {
      await link.initialize(startPolling: false);
      await link.poll(force: true);
      final repository = SqliteScheduleRepository(db);
      final calendar = CalendarService();
      await calendar.load();
      final settings = await repository.loadSettings();
      for (final cached in settings.holidayCache.values) {
        calendar.loadHolidayJson(jsonDecode(cached) as Map<String, dynamic>);
      }
      await notifications.initialize();
      await notifications.applyDesktopSettings(settings);
      await notifications.reconcile(
        planReminders(
          resolveEvents(
            (await repository.loadEvents()).where((e) => !e.isTodo).toList(),
            calendar,
          ),
          settings,
          DateTime.now(),
          limit: 128,
        ),
      );
      return link.error == null;
    } finally {
      await notifications.flush();
      notifications.dispose();
      link.dispose();
      await db.close();
    }
  });
}

Future<void> initializeBackgroundSync() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(calendarSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    'warm-calendar-sync',
    'calendar-sync',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
