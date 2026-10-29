import 'dart:convert';
import '../domain/models.dart';

Uri validateSyncServer(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请输入完整服务地址，例如 http://192.168.1.10:4280');
  }
  final host = uri.host.toLowerCase();
  final parts = host.split('.').map(int.tryParse).toList();
  final ipv4 =
      parts.length == 4 && parts.every((p) => p != null && p >= 0 && p <= 255);
  final local =
      host == 'localhost' ||
      host == '::1' ||
      ipv4 &&
          (parts[0] == 127 ||
              parts[0] == 10 ||
              parts[0] == 192 && parts[1] == 168 ||
              parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
    throw const FormatException('公网服务需使用HTTPS；HTTP仅支持本机或局域网地址');
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
}

class PairCode {
  final Uri server;
  final String invite;
  const PairCode(this.server, this.invite);
  String encode() => Uri(
    scheme: 'warmcalendar',
    host: 'pair',
    queryParameters: {'v': '1', 'server': server.toString(), 'invite': invite},
  ).toString();
  factory PairCode.parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.scheme != 'warmcalendar' ||
        uri.host != 'pair' ||
        uri.queryParameters['v'] != '1' ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(uri.queryParameters['invite'] ?? '')) {
      throw const FormatException('这不是有效的日程表连接二维码');
    }
    return PairCode(
      validateSyncServer(uri.queryParameters['server'] ?? ''),
      uri.queryParameters['invite']!,
    );
  }
}

class LinkIdentity {
  final Uri server;
  final String credential, deviceId;
  const LinkIdentity(this.server, this.credential, this.deviceId);
  String encode() => jsonEncode({
    'server': server.toString(),
    'credential': credential,
    'deviceId': deviceId,
  });
  factory LinkIdentity.decode(String text) {
    final value = jsonDecode(text) as Map<String, dynamic>;
    return LinkIdentity(
      validateSyncServer(value['server'] as String),
      value['credential'] as String,
      value['deviceId'] as String,
    );
  }
}

class PendingChange {
  final ScheduleEvent event;
  final String payload;
  const PendingChange(this.event, this.payload);
}

class LinkFailure implements Exception {
  final String message;
  final int? status;
  const LinkFailure(this.message, [this.status]);
  @override
  String toString() => message;
}
