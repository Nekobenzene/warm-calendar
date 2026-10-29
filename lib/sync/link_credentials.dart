import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class LinkCredentialsStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
  Future<String?> readRegistrations() async => null;
  Future<void> writeRegistrations(String value) async {}
}

class SecureLinkCredentials extends LinkCredentialsStore {
  final String key;
  final FlutterSecureStorage storage;
  SecureLinkCredentials({
    this.key = 'warm-calendar-device',
    this.storage = const FlutterSecureStorage(),
  });
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
  @override
  Future<String?> readRegistrations() =>
      storage.read(key: '$key-installations');
  @override
  Future<void> writeRegistrations(String value) =>
      storage.write(key: '$key-installations', value: value);
}
