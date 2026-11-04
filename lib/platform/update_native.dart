import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/app_update.dart';
import '../version.dart';

String get updateTarget => Platform.isWindows
    ? 'windows'
    : Platform.isAndroid
    ? 'android'
    : 'unsupported';

// Honor the user's existing proxy without changing any system setting.
HttpClient _newHttpClient() {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  var proxy =
      Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['https_proxy'];
  if (proxy == null && Platform.isWindows) {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    try {
      final enabled = Process.runSync('reg.exe', [
        'query',
        key,
        '/v',
        'ProxyEnable',
      ]);
      if (RegExp(r'REG_DWORD\s+0x1\b').hasMatch('${enabled.stdout}')) {
        final value = Process.runSync('reg.exe', [
          'query',
          key,
          '/v',
          'ProxyServer',
        ]);
        proxy = RegExp(
          r'REG_SZ\s+([^\r\n]+)',
        ).firstMatch('${value.stdout}')?.group(1)?.trim();
        if (proxy?.contains('=') == true) {
          proxy = proxy!
              .split(';')
              .where((p) => p.startsWith('https='))
              .firstOrNull
              ?.substring(6);
        }
      }
    } catch (_) {
      /* Direct connection remains available. */
    }
  }
  final uri = proxy == null
      ? null
      : Uri.tryParse(proxy.contains('://') ? proxy : 'http://$proxy');
  if (uri != null &&
      uri.host.isNotEmpty &&
      uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https')) {
    client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
  }
  return client;
}

http.Client createUpdateClient() => IOClient(_newHttpClient());

Future<String> downloadUpdate(
  UpdateRelease release,
  void Function(int) progress,
  bool Function() cancelled, {
  Directory? cacheDirectory,
  HttpClient? httpClient,
}) async {
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(release.name)) {
    throw const FormatException('安装包文件名无效');
  }
  final directory =
      cacheDirectory ??
      Directory('${(await getTemporaryDirectory()).path}/updates');
  await directory.create(recursive: true);
  final file = File('${directory.path}/${release.name}.part'),
      destination = File('${directory.path}/${release.name}');
  if (await destination.exists()) {
    if (await destination.length() == release.bytes &&
        (await sha256.bind(destination.openRead()).first).toString() ==
            release.digest) {
      progress(release.bytes);
      return destination.path;
    }
    await destination.delete();
  }
  if (cancelled()) throw const FormatException('下载已取消');
  final client = httpClient ?? _newHttpClient();
  final cancellation = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (cancelled()) client.close(force: true);
  });
  final output = file.openWrite();
  try {
    final response = await (await client.getUrl(
      release.url,
    )).close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const FormatException('下载失败，请检查网络后重试');
    }
    var size = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 25))) {
      if (cancelled()) throw const FormatException('下载已取消');
      size += chunk.length;
      if (size > release.bytes) throw const FormatException('下载大小不符');
      output.add(chunk);
      progress(size);
    }
    await output.flush();
    await output.close();
    if (size != release.bytes) throw const FormatException('下载不完整，请重试');
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != release.digest) {
      throw const FormatException('安装包校验失败，请重新下载');
    }
    if (cancelled()) throw const FormatException('下载已取消');
    await file.rename(destination.path);
    return destination.path;
  } finally {
    cancellation.cancel();
    await output.close();
    client.close(force: true);
    if (await file.exists()) await file.delete();
  }
}

Future<void> installUpdate(String path) async {
  if (isLocalPreview) {
    throw const FormatException('安装包已下载；请在正式安装版中执行升级。本地预览保持独立。');
  }
  if (Platform.isWindows) {
    await Process.start(path, [
      '/SILENT',
      '/UPDATE=1',
      '/NORESTART',
      '/DIR=${File(Platform.resolvedExecutable).parent.path}',
    ], mode: ProcessStartMode.detached);
  } else if (Platform.isAndroid) {
    final result = await const MethodChannel(
      'warm_calendar/android',
    ).invokeMethod<bool>('installApk', {'path': path});
    if (result != true) throw const FormatException('请允许日程表安装应用，再点“继续安装”');
  }
}
