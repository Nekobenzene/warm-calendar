import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_windows/flutter_local_notifications_windows.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
import 'notification_api.dart';

/// COM activation is supplied by the maintained Windows notification plugin.
/// Queue operations use a small MethodChannel so HRESULT failures reach Dart.
class NotificationService extends NotificationBackend
    with WindowListener, TrayListener {
  NotificationService({this.startHidden = false, this.verification = false});
  static const _channel = MethodChannel('warm_calendar/windows');
  final bool startHidden;
  final bool verification;
  FlutterLocalNotificationsWindows? _plugin;
  bool _ready = false, _trayReady = false, _closeToTray = true;
  bool? _startup;
  String _permission = 'unsupported';
  final Map<int, String> _fingerprints = {};
  final Map<String, DateTime> _scheduledKeys = {};
  final Map<int, String> _keysById = {};
  bool _schedulingHealthy = false;
  Future<void> _queue = Future.value();
  int _scheduledCount = 0;
  @override
  bool get desktop => Platform.isWindows;
  @override
  bool get diagnosticMode => verification;
  @override
  bool get supported => desktop && _ready;
  @override
  bool get supportsScheduling => supported;
  @override
  bool get schedulingHealthy => _schedulingHealthy;
  @override
  bool hasScheduledReminder(String key) => _scheduledKeys.containsKey(key);
  @override
  String get permission => _permission;
  @override
  int get scheduledCount => _scheduledCount;

  @override
  Future<void> initialize() async {
    if (!desktop || _ready) return;
    try {
      await _channel.invokeMethod<void>('registerActivation');
    } on MissingPluginException {
      return;
    }
    _plugin = FlutterLocalNotificationsWindows();
    final ready = await _plugin!.initialize(
      settings: WindowsInitializationSettings(
        appName: verification ? '日程表验证' : '日程表',
        appUserModelId: verification
            ? 'WarmCalendar.Planner.Verification'
            : 'WarmCalendar.Planner.Desktop',
        guid: verification
            ? '96e55b26-0749-4543-ae4e-4c8535468811'
            : '96e55b26-0749-4543-ae4e-4c8535468810',
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        unawaited(showWindow());
        if (id != null && id.isNotEmpty) {
          openedEvent.value = null;
          openedEvent.value = id;
        }
      },
    );
    if (!ready) throw StateError('Windows通知初始化失败');
    _ready = true;
    await requestPermission();
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(760, 580));
    windowManager.addListener(this);
    try {
      await trayManager.setIcon('assets/icons/app_icon.ico');
      await trayManager.setToolTip('日程表');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开日程表'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '退出（保留已排定提醒）'),
          ],
        ),
      );
      trayManager.addListener(this);
      _trayReady = true;
      await windowManager.setPreventClose(true);
      if (startHidden) await windowManager.hide();
    } catch (_) {
      // Never hide a window or intercept Close if the tray is unavailable.
      await windowManager.setPreventClose(false);
      await showWindow();
      rethrow;
    }
    final launch = await _plugin!.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) openedEvent.value = payload;
  }

  @override
  Future<String> requestPermission() async {
    if (!_ready) return _permission;
    _permission =
        await _channel.invokeMethod<String>('permission') ?? 'unsupported';
    return _permission;
  }

  @override
  Future<void> openSystemSettings() =>
      _channel.invokeMethod<void>('openSettings');
  @override
  Future<bool?> readLaunchAtStartup() async {
    if (!desktop) return null;
    try {
      return await _channel.invokeMethod<bool>('startupEnabled');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> applyDesktopSettings(AppSettings settings) async {
    if (!_ready) return;
    _closeToTray = settings.closeToTray;
    if (_startup != settings.launchAtStartup) {
      await _channel.invokeMethod<void>('startup', settings.launchAtStartup);
      _startup = settings.launchAtStartup;
    }
  }

  String _xml(String title, String body, bool sound, String? eventId) {
    const escape = HtmlEscape(HtmlEscapeMode.element);
    final payload = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(eventId ?? '');
    return '<toast launch="$payload">'
        '<visual><binding template="ToastGeneric"><text>${escape.convert(title)}</text><text>${escape.convert(body)}</text></binding></visual>'
        '${sound ? '<audio src="ms-winsoundevent:Notification.Reminder"/>' : '<audio silent="true"/>'}</toast>';
  }

  @override
  Future<void> show(
    String title,
    String body, {
    bool sound = true,
    String? eventId,
  }) async {
    if (!_ready) return;
    await _channel.invokeMethod<void>('show', {
      'id': '2147483647',
      'xml': _xml(title, body, sound, eventId),
    });
  }

  @override
  Future<void> reconcile(List<ReminderRequest> requests) {
    final operation = _queue.then((_) async {
      if (!_ready) return;
      _scheduledKeys.removeWhere(
        (_, expiry) => !expiry.isAfter(DateTime.now()),
      );
      await requestPermission();
      final pending = (await _channel.invokeListMethod<int>('pending') ?? [])
          .toSet();
      final wanted = {for (final r in requests) r.id: r};
      for (final id in pending.toList()) {
        if (!wanted.containsKey(id) ||
            _fingerprints[id] != wanted[id]!.fingerprint) {
          await _channel.invokeMethod<void>('cancel', '$id');
          _scheduledKeys.remove(_keysById.remove(id));
          _fingerprints.remove(id);
          pending.remove(id);
        }
      }
      for (final request in requests) {
        if (pending.contains(request.id)) continue;
        if (!request.at.isAfter(DateTime.now())) continue;
        await _channel.invokeMethod<void>('schedule', {
          'id': '${request.id}',
          'at': request.at.millisecondsSinceEpoch,
          'xml': _xml(
            request.event.title,
            request.body,
            request.sound,
            request.event.id,
          ),
          'expires': request.expires.millisecondsSinceEpoch,
        });
        _fingerprints[request.id] = request.fingerprint;
        // Keep delivery knowledge after Windows removes a fired task from pending.
        _scheduledKeys[request.key] = request.expires;
        _keysById[request.id] = request.key;
      }
      final actual = (await _channel.invokeListMethod<int>('pending') ?? [])
          .toSet();
      _scheduledCount = actual.length;
      _fingerprints.removeWhere((id, _) => !actual.contains(id));
      for (final request in requests) {
        if (request.at.isAfter(DateTime.now()) &&
            !actual.contains(request.id)) {
          _scheduledKeys.remove(request.key);
        }
      }
      if (requests.any(
        (r) => r.at.isAfter(DateTime.now()) && !actual.contains(r.id),
      )) {
        throw StateError('Windows未保留全部提醒');
      }
      _schedulingHealthy = true;
    });
    final tracked = operation.catchError((Object error, StackTrace stack) {
      _schedulingHealthy = false;
      Error.throwWithStackTrace(error, stack);
    });
    _queue = tracked.catchError((Object _) {});
    return tracked;
  }

  @override
  Future<void> flush() => _queue;
  @override
  Future<void> showWindow() async {
    if (!desktop) return;
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    if (_closeToTray && _trayReady) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_exit());
    }
  }

  Future<void> _exit() async {
    await beforeExit?.call();
    await flush();
    if (_trayReady) await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(showWindow());
    if (menuItem.key == 'exit') unawaited(_exit());
  }

  @override
  void dispose() {
    if (desktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }
}
