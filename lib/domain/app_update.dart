import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../version.dart';
import '../platform/update_platform.dart' as platform;

int compareVersions(String left, String right) {
  final pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );
  final a = pattern.firstMatch(left), b = pattern.firstMatch(right);
  if (a == null || b == null) throw const FormatException('版本号无效');
  for (var i = 1; i <= 3; i++) {
    final c = int.parse(a[i]!).compareTo(int.parse(b[i]!));
    if (c != 0) return c;
  }
  if (a[4] == null && b[4] != null) return 1;
  if (a[4] != null && b[4] == null) return -1;
  if (a[4] == b[4]) return 0;
  final x = a[4]!.split('.'), y = b[4]!.split('.');
  for (var i = 0; i < x.length && i < y.length; i++) {
    final n = int.tryParse(x[i]), m = int.tryParse(y[i]);
    final c = n != null && m != null
        ? n.compareTo(m)
        : n != null
        ? -1
        : m != null
        ? 1
        : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

class UpdateRelease {
  final String version, name, digest;
  final Uri url;
  final int bytes;
  const UpdateRelease(
    this.version,
    this.name,
    this.url,
    this.bytes,
    this.digest,
  );
  factory UpdateRelease.fromJson(Map<String, dynamic> j, String target) {
    final version = j['tag_name'] as String;
    compareVersions(version, appVersion);
    if (j['draft'] == true || j['prerelease'] == true) {
      throw const FormatException('该版本尚未正式发布');
    }
    final suffix = target == 'windows'
        ? 'windows-x64-setup.exe'
        : 'android.apk';
    final name =
        'warm-calendar-${version.replaceFirst(RegExp(r"^v"), "")}-$suffix';
    final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
    final asset = assets.where((a) => a['name'] == name).firstOrNull;
    if (asset == null) throw const FormatException('此版本尚未提供当前设备的安装包');
    final url = Uri.parse(asset['browser_download_url'] as String);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.path !=
            '/Nekobenzene/warm-calendar/releases/download/$version/$name' ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('安装包来源无效');
    }
    final bytes = asset['size'] as int,
        digest = asset['digest'] as String? ?? '';
    if (bytes < 1 ||
        bytes > 1024 * 1024 * 1024 ||
        !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)) {
      throw const FormatException('安装包大小或校验信息缺失');
    }
    return UpdateRelease(
      version,
      name,
      url,
      bytes,
      digest.substring(7).toLowerCase(),
    );
  }
}

class AppUpdateController extends ChangeNotifier {
  final String currentVersion, target;
  final http.Client Function() clientFactory;
  final Future<String> Function(
    UpdateRelease,
    void Function(int),
    bool Function(),
  )
  downloader;
  final Future<void> Function(String) installer;
  AppUpdateController({
    this.currentVersion = appVersion,
    String? target,
    http.Client Function()? clientFactory,
    Future<String> Function(UpdateRelease, void Function(int), bool Function())?
    downloader,
    Future<void> Function(String)? installer,
  }) : target = target ?? platform.updateTarget,
       clientFactory = clientFactory ?? platform.createUpdateClient,
       downloader = downloader ?? platform.downloadUpdate,
       installer = installer ?? platform.installUpdate;
  bool checking = false,
      downloading = false,
      installing = false,
      checked = false,
      _disposed = false,
      _cancelled = false;
  int received = 0;
  String? error, downloadedPath;
  UpdateRelease? release;
  DateTime? lastChecked;
  DateTime? lastAttempt;
  bool get supported => target == 'windows' || target == 'android';
  bool get hasUpdate =>
      release != null && compareVersions(release!.version, currentVersion) > 0;
  double? get progress =>
      release == null ? null : (received / release!.bytes).clamp(0.0, 1.0);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (checking || downloading || installing || !supported) return;
    checking = true;
    lastAttempt = DateTime.now();
    error = null;
    _notify();
    final client = clientFactory();
    try {
      final response = await client
          .get(
            Uri.parse(
              'https://api.github.com/repos/Nekobenzene/warm-calendar/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const FormatException('无法获取新版本，请检查网络后重试');
      }
      if (response.bodyBytes.length > 512000) {
        throw const FormatException('版本信息过大');
      }
      final next = UpdateRelease.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        target,
      );
      if (release?.version != next.version) downloadedPath = null;
      release = next;
      checked = true;
      lastChecked = DateTime.now();
    } catch (e) {
      error = e is FormatException ? e.message.toString() : '检查更新失败，请稍后重试';
    } finally {
      client.close();
      checking = false;
      _notify();
    }
  }

  Future<void> downloadAndInstall({
    Future<void> Function()? beforeInstall,
  }) async {
    if (!hasUpdate || downloading || installing) return;
    error = null;
    _cancelled = false;
    _notify();
    try {
      if (downloadedPath == null) {
        downloading = true;
        received = 0;
        _notify();
        downloadedPath = await downloader(release!, (count) {
          received = count;
          _notify();
        }, () => _cancelled || _disposed);
      }
      if (_cancelled || _disposed) return;
      downloading = false;
      installing = true;
      _notify();
      await beforeInstall?.call();
      await installer(downloadedPath!);
    } catch (e) {
      if (!_cancelled) {
        error = e is FormatException
            ? e.message.toString()
            : '下载或安装未完成，请检查网络、存储空间后重试';
      }
    } finally {
      downloading = false;
      installing = false;
      _notify();
    }
  }

  void cancel() {
    _cancelled = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    super.dispose();
  }
}
