import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'notification_api.dart';

NotificationBackend createNotificationService({
  bool startHidden = false,
  bool verification = false,
}) => NotificationService();

class NotificationService extends NotificationBackend {
  NotificationService({bool startHidden = false, bool verification = false});
  @override
  bool get supported => globalContext.hasProperty('Notification'.toJS).toDart;
  @override
  String get permission =>
      supported ? web.Notification.permission : 'unsupported';
  @override
  Future<String> requestPermission() async => supported
      ? (await web.Notification.requestPermission().toDart).toDart
      : 'unsupported';
  @override
  Future<void> show(
    String title,
    String body, {
    bool sound = true,
    String? eventId,
  }) async {
    if (permission == 'granted') {
      web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          tag: eventId ?? title,
          silent: !sound,
        ),
      );
    }
  }
}
