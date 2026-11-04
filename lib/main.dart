import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_controller.dart';
import 'data/repository.dart';
import 'domain/calendar_service.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'platform/notification_service.dart';
import 'sync/link_controller.dart';
import 'sync/link_credentials.dart';
import 'sync/sync_store.dart';
import 'sync/background_sync.dart';
import 'sync/local_relay.dart';
import 'version.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final verification = args.contains('--verification') || isLocalPreview;
  final db = CalendarDatabase(
    null,
    isLocalPreview
        ? appDatabaseName
        : verification
        ? 'warm_calendar_verification'
        : appDatabaseName,
  );
  initializeBackgroundSync().catchError((Object e) {
    debugPrint('Background sync initialization failed: $e');
  });
  runApp(
    CalendarApp(
      controller: AppController(
        repository: SqliteScheduleRepository(db),
        link: LinkController(
          prepareServer: resumeLocalRelay,
          store: SqliteSyncStore(db),
          credentials: SecureLinkCredentials(
            key: isLocalPreview
                ? appCredentialKey
                : verification
                ? 'warm-calendar-device-verification'
                : appCredentialKey,
          ),
          platform: kIsWeb
              ? 'web'
              : defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : 'desktop',
        ),
        calendar: CalendarService(),
        notifications: createNotificationService(
          startHidden: args.contains('--tray'),
          verification: verification,
        ),
      ),
    ),
  );
}

class CalendarApp extends StatefulWidget {
  final AppController controller;
  const CalendarApp({super.key, required this.controller});
  @override
  State<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> with WidgetsBindingObserver {
  int? _themeSeed;
  ThemeData? _theme;

  ThemeData get _currentTheme {
    final seed = widget.controller.settings.themeColor;
    if (_theme == null || _themeSeed != seed) {
      _themeSeed = seed;
      _theme = appTheme(seed);
    }
    return _theme!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.controller.loading) {
      _resume();
    }
  }

  Future<void> _resume() async {
    try {
      await widget.controller.notifications.refreshPermissions();
      await widget.controller.reloadSyncedEvents();
      await widget.controller.link?.poll(force: true);
    } catch (e) {
      debugPrint('Resume refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => MaterialApp(
      title: '日程表',
      debugShowCheckedModeBanner: false,
      theme: _currentTheme,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AppShell(controller: widget.controller),
    ),
  );
}
