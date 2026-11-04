import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../version.dart';

int get _relayPort => isLocalPreview ? 4281 : 4280;

bool get canStartLocalRelay => Platform.isWindows;
Future<void> resumeLocalRelay(Uri server) async {
  if (!canStartLocalRelay ||
      server.scheme != 'http' ||
      server.port != _relayPort) {
    return;
  }
  final local = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: true,
  );
  if (server.host == 'localhost' ||
      local.any((i) => i.addresses.any((a) => a.address == server.host))) {
    await startLocalRelay();
  }
}

Future<List<String>> startLocalRelay() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  Future<bool> healthy() async {
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:$_relayPort/health'),
      )).close().timeout(const Duration(seconds: 2));
      final result =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return result['service'] == 'warm-calendar-sync' &&
          result['protocol'] == 2;
    } catch (_) {
      return false;
    }
  }

  try {
    if (!await healthy()) {
      final folder = File(Platform.resolvedExecutable).parent.path;
      final node = File('$folder/sync-service/node.exe');
      final script = File('$folder/sync-service/server.mjs');
      if (!node.existsSync() || !script.existsSync()) {
        throw const FileSystemException('未找到本机同步服务，请使用完整桌面安装包');
      }
      final support = await getApplicationSupportDirectory();
      final data = Directory(
        '${support.path}/${isLocalPreview ? 'sync-service-preview' : 'sync-service'}',
      );
      await data.create(recursive: true);
      await Process.start(
        node.path,
        [script.path],
        workingDirectory: data.path,
        environment: {
          'SYNC_HOST': '0.0.0.0',
          'SYNC_PORT': '$_relayPort',
          'SYNC_DATABASE': '${data.path}/calendar.sqlite',
        },
        mode: ProcessStartMode.detached,
      );
      var ready = false;
      for (var i = 0; i < 15; i++) {
        if (await healthy()) {
          ready = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!ready) throw FileSystemException('本机同步服务未启动，请检查$_relayPort端口');
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addresses = interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where(
          (s) =>
              s.startsWith('192.168.') ||
              s.startsWith('10.') ||
              (s.startsWith('172.') &&
                  int.parse(s.split('.')[1]) >= 16 &&
                  int.parse(s.split('.')[1]) <= 31),
        )
        .toSet()
        .toList();
    return [for (final address in addresses) 'http://$address:$_relayPort'];
  } finally {
    client.close(force: true);
  }
}
