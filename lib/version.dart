const appVersion = '0.7.4';
final isLocalPreview = appVersion.contains('-preview');
String get appDatabaseName =>
    isLocalPreview ? 'warm_calendar_preview' : 'warm_calendar';
String get appCredentialKey =>
    isLocalPreview ? 'warm-calendar-device-preview' : 'warm-calendar-device';
