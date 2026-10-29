import 'dart:io';
import 'notification_api.dart';
import 'notification_android.dart';
import 'notification_windows.dart' as windows;

NotificationBackend createNotificationService({
  bool startHidden = false,
  bool verification = false,
}) => Platform.isAndroid
    ? AndroidNotificationService()
    : windows.NotificationService(
        startHidden: startHidden,
        verification: verification,
      );
