import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import 'link_api.dart';
import 'link_credentials.dart';
import 'link_models.dart';
import 'sync_store.dart';

class LinkController extends ChangeNotifier {
  final SyncStore store;
  final LinkCredentialsStore credentials;
  final LinkApi api;
  final String platform;
  final Future<void> Function(Uri server)? prepareServer;
  LinkController({
    required this.store,
    required this.credentials,
    required this.platform,
    this.prepareServer,
    LinkApi? api,
  }) : api = api ?? LinkApi();
  LinkIdentity? identity;
  Map<String, dynamic>? connection;
  Map<String, dynamic>? invitation;
  Map<String, dynamic>? waitingRequest;
  List<Map<String, dynamic>> requests = [];
  Future<void> Function()? onRemoteApplied;
  DateTime? lastSynced;
  String? error;
  bool busy = false, syncing = false, initialized = false;
  bool _disposed = false, _polling = false, _action = false;
  Timer? _timer, _debounce;
  DateTime _retryAt = DateTime(2000);
  int _failures = 0;
  String deviceName = '';
  String? _boundDevice;

  Future<Map<String, dynamic>> _installation(Uri server) async {
    final saved = await credentials.readRegistrations();
    final all = saved == null
        ? <String, dynamic>{}
        : jsonDecode(saved) as Map<String, dynamic>;
    final address = server.toString();
    if (all[address] is Map) {
      return Map<String, dynamic>.from(all[address] as Map);
    }
    final random = Random.secure();
    final value = {
      'installationId': List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'installationSecret': base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', ''),
    };
    all[address] = value;
    await credentials.writeRegistrations(jsonEncode(all));
    return value;
  }

  Future<void> _bindInstallation() async {
    if (identity == null ||
        connection?['protocol'] != 2 ||
        _boundDevice == identity!.deviceId) {
      return;
    }
    await _call(
      '/v1/registration',
      body: await _installation(identity!.server),
    );
    _boundDevice = identity!.deviceId;
  }

  Future<void> _register(Uri server, String name) async {
    final result = await api.call(
      server,
      '/v1/devices',
      body: {
        'name': name,
        'platform': platform,
        ...await _installation(server),
      },
    );
    final value = LinkIdentity(
      server,
      result['credential'] as String,
      result['deviceId'] as String,
    );
    await credentials.write(value.encode());
    identity = value;
    connection = result;
    if (result['protocol'] == 2) _boundDevice = value.deviceId;
    await store.seed();
  }

  bool get isMobile => platform == 'android';
  bool get linked => connection?['linked'] == true;
  bool get hasService => identity != null;
  List<Map<String, dynamic>> get devices =>
      (connection?['devices'] as List? ?? []).cast<Map<String, dynamic>>();
  String? get qrData => invitation == null || identity == null
      ? null
      : PairCode(identity!.server, invitation!['invite'] as String).encode();
  int get expiresIn => invitation == null
      ? 0
      : ((invitation!['expiresAt'] as int) -
                DateTime.now().millisecondsSinceEpoch +
                999) ~/
            1000;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({bool startPolling = true}) async {
    if (initialized) return;
    await store.initialize();
    try {
      final saved = await credentials.read();
      if (saved != null) identity = LinkIdentity.decode(saved);
    } catch (_) {
      error = '无法读取设备凭据，请检查系统凭据存储';
    }
    initialized = true;
    if (startPolling) {
      if (identity != null && prepareServer != null) {
        try {
          await prepareServer!(identity!.server);
        } catch (_) {
          error = '本机服务未能恢复，可在链接页重试启动';
        }
      }
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        _notify();
        unawaited(poll());
      });
      unawaited(poll(force: true));
    }
    _notify();
  }

  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, dynamic>? body,
  }) {
    final current = identity;
    if (current == null) throw const LinkFailure('请先连接同步服务');
    return api.call(
      current.server,
      path,
      credential: current.credential,
      body: body,
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_action) return;
    _action = busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (e) {
      error = e is FormatException ? e.message : '$e';
      rethrow;
    } finally {
      busy = _action = false;
      _notify();
    }
  }

  Future<void> connect(String address, {String? name}) => _perform(() async {
    final server = validateSyncServer(address);
    if (identity != null && identity!.server != server) {
      throw const LinkFailure('请先断开当前服务');
    }
    if (identity == null) {
      await _register(
        server,
        name ??
            (deviceName.isNotEmpty
                ? deviceName
                : isMobile
                ? '安卓手机'
                : '我的电脑'),
      );
    } else {
      connection = await _call('/v1/state');
      await _bindInstallation();
    }
    if (!isMobile) await _newInvite();
    _retryAt = DateTime(2000);
    _failures = 0;
    unawaited(poll(force: true));
  });
  Future<void> _newInvite() async {
    invitation = await _call('/v1/invites', body: {});
    requests = [];
  }

  Future<void> refreshQr() => _perform(_newInvite);
  Future<void> renameDevice(String value) => _perform(() async {
    final name = value.trim();
    if (name.isEmpty || name.length > 60) {
      throw const FormatException('设备名需为1—60个字符');
    }
    if (identity != null) {
      connection = await _call('/v1/device-name', body: {'name': name});
    }
    deviceName = name;
  });
  Future<void> requestPair(String rawCode) => _perform(() async {
    final code = PairCode.parse(rawCode);
    if (linked) throw const LinkFailure('请先断开原设备连接');
    if (identity != null && identity!.server != code.server) {
      throw const LinkFailure('二维码来自其他服务，请先断开当前服务');
    }
    if (identity == null) {
      await _register(code.server, deviceName.isNotEmpty ? deviceName : '安卓手机');
    }
    if (linked) return;
    waitingRequest = await _call(
      '/v1/pair-requests',
      body: {'invite': code.invite},
    );
    _retryAt = DateTime(2000);
    _failures = 0;
  });
  Future<void> confirmPair(String requestId, bool approve) =>
      _perform(() async {
        connection = await _call(
          '/v1/pair-requests/$requestId',
          body: {'approve': approve},
        );
        requests.removeWhere((r) => r['requestId'] == requestId);
        invitation = null;
        await _newInvite();
        unawaited(poll(force: true));
      });
  Future<void> unlink(String deviceId) => _perform(() async {
    connection = await _call('/v1/unlink', body: {'deviceId': deviceId});
    if (isMobile) {
      waitingRequest = null;
      await store.seed();
    }
  });
  Future<void> disconnectService() => _perform(() async {
    await _call('/v1/revoke', body: {});
    await credentials.clear();
    identity = null;
    _boundDevice = null;
    connection = null;
    invitation = null;
    waitingRequest = null;
    requests = [];
    await store.seed();
  });
  void localChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(poll(force: true)),
    );
  }

  Future<void> poll({bool force = false}) async {
    if (_disposed ||
        _polling ||
        _action ||
        identity == null ||
        !initialized ||
        !force && DateTime.now().isBefore(_retryAt)) {
      return;
    }
    _polling = syncing = true;
    _notify();
    try {
      connection = await _call('/v1/state');
      await _bindInstallation();
      if (connection?['protocol'] == 2 &&
          deviceName.isNotEmpty &&
          (connection?['device'] as Map?)?['name'] != deviceName) {
        connection = await _call('/v1/device-name', body: {'name': deviceName});
      }
      if (isMobile && waitingRequest != null) {
        final result = await _call(
          '/v1/pair-requests/${waitingRequest!['requestId']}',
        );
        final status = result['status'];
        if (status == 'approved') {
          connection = result;
          waitingRequest = null;
          await store.seed();
        } else if (status == 'rejected' || status == 'expired') {
          waitingRequest = null;
          throw LinkFailure(
            status == 'rejected' ? '桌面端已拒绝连接，可重新扫码' : '连接请求已过期，请重新扫码',
          );
        }
      }
      if (!isMobile) {
        requests = ((await _call('/v1/pair-requests'))['requests'] as List)
            .cast<Map<String, dynamic>>();
        if (invitation == null || expiresIn <= 0) await _newInvite();
      }
      if (!isMobile || linked) await syncNow();
      error = null;
      _failures = 0;
      _retryAt = DateTime.now().add(const Duration(seconds: 2));
    } catch (e) {
      error = '$e';
      if (e is LinkFailure && e.status == 401) {
        await credentials.clear();
        identity = null;
        connection = null;
        invitation = null;
        waitingRequest = null;
        requests = [];
        error = '设备凭据已失效，请重新连接服务';
      }
      _failures++;
      _retryAt = DateTime.now().add(
        Duration(seconds: _failures < 5 ? _failures * 2 : 30),
      );
    } finally {
      _polling = syncing = false;
      _notify();
    }
  }

  Future<void> syncNow() async {
    if (identity == null || isMobile && !linked) return;
    // Bound each pass, then continue automatically on the next poll.
    for (var page = 0; page < 20; page++) {
      final position = await store.position();
      final pending = await store.pending();
      final preferences = await store.pendingPreferences();
      final result = await _call(
        '/v1/sync',
        body: {
          'groupId': position.groupId,
          'cursor': position.cursor,
          'events': pending.map((p) => p.event.toJson()).toList(),
          'settings': ?preferences,
        },
      );
      final remote = (result['events'] as List)
          .map((e) => ScheduleEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      final changed = await store.apply(
        remote,
        pending,
        result['groupId'] as String,
        result['cursor'] as int,
      );
      final settingsChanged = await store.applyPreferences(
        result['settings'] as Map<String, dynamic>?,
        result.containsKey('settings') ? preferences : null,
      );
      connection = result;
      lastSynced = DateTime.now();
      if (changed || settingsChanged) await onRemoteApplied?.call();
      if (result['hasMore'] != true && pending.length < 100) break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
    api.close();
    super.dispose();
  }
}
