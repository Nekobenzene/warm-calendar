import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warm_calendar/domain/app_update.dart';
import 'package:warm_calendar/platform/update_native.dart' as native;

Map<String, dynamic> releaseJson({
  String version = 'v0.7.0',
  String target = 'windows',
  String? url,
  String? digest,
}) {
  final name =
      'warm-calendar-${version.substring(1)}-${target == 'windows' ? 'windows-x64-setup.exe' : 'android.apk'}';
  return {
    'tag_name': version,
    'draft': false,
    'prerelease': false,
    'assets': [
      {
        'name': name,
        'browser_download_url':
            url ??
            'https://github.com/Nekobenzene/warm-calendar/releases/download/$version/$name',
        'size': 100,
        'digest': digest ?? 'sha256:${'a' * 64}',
      },
    ],
  };
}

void main() {
  test('版本比较区分预览、正式及数字序号，不降级安装', () {
    expect(compareVersions('0.6.0-preview.2', '0.6.0-preview.10'), lessThan(0));
    expect(compareVersions('v0.6.0', '0.6.0-preview.10'), greaterThan(0));
    expect(compareVersions('0.6.0+6', 'v0.6.0+8'), 0);
    expect(compareVersions('0.5.0', '0.6.0-preview.1'), lessThan(0));
    expect(() => compareVersions('bad', '0.6.0'), throwsFormatException);
  });
  test('严格选择本仓库对应平台安装包及摘要', () {
    expect(
      UpdateRelease.fromJson(releaseJson(), 'windows').name,
      endsWith('setup.exe'),
    );
    expect(
      UpdateRelease.fromJson(releaseJson(target: 'android'), 'android').name,
      endsWith('.apk'),
    );
    for (final j in [
      releaseJson(url: 'https://example.com/fake.exe'),
      releaseJson(digest: ''),
      {...releaseJson(), 'prerelease': true},
      releaseJson(target: 'android'),
    ]) {
      expect(() => UpdateRelease.fromJson(j, 'windows'), throwsFormatException);
    }
  });
  test('检查、下载进度、失败重试及安装权限恢复', () async {
    var installs = 0, downloads = 0;
    final gate = Completer<void>();
    final u = AppUpdateController(
      target: 'windows',
      currentVersion: '0.6.0-preview.1',
      clientFactory: () => MockClient(
        (_) async => http.Response(jsonEncode(releaseJson()), 200),
      ),
      downloader: (r, p, c) async {
        downloads++;
        p(25);
        await gate.future;
        p(100);
        return 'verified.exe';
      },
      installer: (path) async {
        installs++;
        if (installs == 1) throw const FormatException('等待系统允许');
      },
    );
    addTearDown(u.dispose);
    await u.check();
    expect(u.hasUpdate, true);
    final work = u.downloadAndInstall();
    expect(u.downloading, true);
    expect(u.progress, .25);
    gate.complete();
    await work;
    expect(u.error, '等待系统允许');
    expect(u.downloadedPath, 'verified.exe');
    await u.downloadAndInstall();
    expect(installs, 2);
    expect(downloads, 1);
    expect(u.error, isNull);
    expect(u.progress, 1);
  });
  test('取消不执行安装，检查失败保留可重试信息且不降级', () async {
    var fail = false, installs = 0;
    final gate = Completer<void>();
    final u = AppUpdateController(
      target: 'android',
      clientFactory: () => MockClient(
        (_) async => http.Response(
          fail ? 'unavailable' : jsonEncode(releaseJson(target: 'android')),
          fail ? 503 : 200,
        ),
      ),
      downloader: (r, p, c) async {
        await gate.future;
        if (c()) throw const FormatException('取消');
        return 'x.apk';
      },
      installer: (_) async {
        installs++;
      },
    );
    addTearDown(u.dispose);
    await u.check();
    final work = u.downloadAndInstall();
    u.cancel();
    gate.complete();
    await work;
    expect(installs, 0);
    expect(u.downloading, false);
    expect(u.error, isNull);
    fail = true;
    await u.check();
    expect(u.error, isNotNull);
    expect(u.hasUpdate, true);
    final old = AppUpdateController(
      target: 'windows',
      clientFactory: () => MockClient(
        (_) async =>
            http.Response(jsonEncode(releaseJson(version: 'v0.5.0')), 200),
      ),
    );
    addTearDown(old.dispose);
    await old.check();
    expect(old.hasUpdate, false);
  });
  test('真实流下载：进度、缓存复用、摘要不符与残留清理', () async {
    final dir = await Directory.systemTemp.createTemp('warm-update-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final bytes = List<int>.generate(20000, (i) => i % 251);
    var requests = 0;
    server.listen((r) async {
      requests++;
      r.response.add(bytes.sublist(0, 10000));
      await r.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      r.response.add(bytes.sublist(10000));
      await r.response.close();
    });
    final release = UpdateRelease(
      'v0.7.0',
      'test.apk',
      Uri.parse('http://127.0.0.1:${server.port}/asset'),
      bytes.length,
      sha256.convert(bytes).toString(),
    );
    final progress = <int>[];
    final path = await native.downloadUpdate(
      release,
      progress.add,
      () => false,
      cacheDirectory: dir,
      httpClient: HttpClient(),
    );
    expect(await File(path).readAsBytes(), bytes);
    expect(progress.last, bytes.length);
    expect(progress.length, greaterThan(1));
    await native.downloadUpdate(
      release,
      progress.add,
      () => false,
      cacheDirectory: dir,
      httpClient: HttpClient(),
    );
    expect(requests, 1);
    await File(path).writeAsString('corrupt');
    final bad = UpdateRelease(
      'v0.7.0',
      'test.apk',
      release.url,
      bytes.length,
      '0' * 64,
    );
    await expectLater(
      native.downloadUpdate(
        bad,
        (_) {},
        () => false,
        cacheDirectory: dir,
        httpClient: HttpClient(),
      ),
      throwsFormatException,
    );
    expect(await File('$path.part').exists(), false);
    expect(await File(path).exists(), false);
  });
}
