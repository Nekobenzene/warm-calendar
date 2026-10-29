import 'notification_api.dart';

NotificationBackend createNotificationService({
  bool startHidden = false,
  bool verification = false,
}) => NotificationService();

class NotificationService extends NotificationBackend {
  NotificationService({bool startHidden = false, bool verification = false});
}
