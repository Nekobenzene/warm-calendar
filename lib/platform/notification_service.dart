export 'notification_stub.dart'
    if (dart.library.io) 'notification_native.dart'
    if (dart.library.js_interop) 'notification_web.dart';
export 'notification_api.dart';
