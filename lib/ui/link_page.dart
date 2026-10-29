import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../sync/link_controller.dart';
import '../sync/link_models.dart';
import '../sync/local_relay.dart';
import '../domain/models.dart';
import 'components.dart';
import 'motion.dart';
import 'theme.dart';

class LinkPage extends StatefulWidget {
  final LinkController? controller;
  const LinkPage({super.key, required this.controller});
  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  final _address = TextEditingController();
  List<String> _localAddresses = [];
  bool _starting = false;
  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is FormatException ? e.message : '$e',
          error: true,
        );
      }
    }
  }

  Future<void> _localService() async {
    setState(() => _starting = true);
    try {
      final values = await startLocalRelay();
      if (!mounted) return;
      if (widget.controller!.hasService) {
        await widget.controller!.poll(force: true);
        return;
      }
      setState(() {
        _localAddresses = values;
        if (values.isNotEmpty) _address.text = values.first;
      });
      if (values.isEmpty) {
        showMessage(context, '服务已启动，请连接局域网后再选择本机地址', error: true);
        return;
      }
      if (values.length > 1) {
        final selected = await showAppDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('选择手机可访问的本机地址'),
            children: [
              for (final value in values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, value),
                  child: Text(value),
                ),
            ],
          ),
        );
        if (selected == null || !mounted) return;
        _address.text = selected;
      }
      await widget.controller!.connect(_address.text);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _scan({bool manual = false}) async {
    final raw = manual
        ? await showAppDialog<String>(
            context: context,
            builder: (_) => const _PastePairCode(),
          )
        : await showAppDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _ScanPairCode(),
          );
    if (raw == null || !mounted) return;
    await _act(() async {
      final code = PairCode.parse(raw);
      final approve = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('连接此电脑'),
          content: Text('服务：${code.server}\n\n桌面端确认后，两端日程将合并并自动同步。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('请求连接'),
            ),
          ],
        ),
      );
      if (approve == true) await widget.controller!.requestPair(raw);
    });
  }

  Future<void> _unlink(Map<String, dynamic> device) async {
    final c = widget.controller!;
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开设备'),
        content: Text('断开与“${device['name']}”的同步连接？两端已有日程保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开连接'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _act(
        () => c.unlink(
          c.isMobile ? c.identity!.deviceId : device['id'] as String,
        ),
      );
    }
  }

  Future<void> _changeService() async {
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开当前服务'),
        content: const Text('保留本机日程，移除本机服务凭据。更换服务前需先断开其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开服务'),
          ),
        ],
      ),
    );
    if (yes == true) await _act(widget.controller!.disconnectService);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c == null) return const Text('当前验证环境未启用设备连接');
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!c.isMobile || c.hasService)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('同步服务'),
                          const Spacer(),
                          if (c.hasService)
                            TextButton(
                              onPressed: c.busy || c.linked
                                  ? null
                                  : _changeService,
                              child: const Text('更换服务'),
                            ),
                        ],
                      ),
                      if (!c.hasService) ...[
                        const SizedBox(height: 12),
                        if (canStartLocalRelay && !c.isMobile) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _starting || c.busy
                                  ? null
                                  : _localService,
                              icon: const Icon(Icons.router_outlined, size: 18),
                              label: Text(_starting ? '启动中…' : '启动本机服务'),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _address,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: '服务地址',
                            hintText: 'http://192.168.1.10:4280',
                          ),
                        ),
                        if (_localAddresses.length > 1) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final value in _localAddresses)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _address.text = value),
                                  child: Text(value),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: c.busy
                                ? null
                                : () => _act(() => c.connect(_address.text)),
                            child: Text(c.busy ? '连接中…' : '连接服务'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本机服务适合同一局域网；跨网络同步需配置公网HTTPS服务。',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ] else ...[
                        SelectableText(
                          c.identity!.server.toString(),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (canStartLocalRelay && !c.isMobile)
                              TextButton.icon(
                                onPressed: _starting || c.busy
                                    ? null
                                    : _localService,
                                icon: const Icon(
                                  Icons.router_outlined,
                                  size: 17,
                                ),
                                label: Text(_starting ? '启动中…' : '启动本机服务'),
                              ),
                            Text(
                              c.error != null
                                  ? '等待重连'
                                  : c.syncing
                                  ? '正在同步…'
                                  : c.linked
                                  ? '自动同步已开启'
                                  : '等待连接设备',
                            ),
                            if (c.lastSynced != null)
                              Text(
                                '最近同步 ${clockText(c.lastSynced!)}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            TextButton.icon(
                              onPressed: c.syncing || c.busy
                                  ? null
                                  : () => c.poll(force: true),
                              icon: const Icon(Icons.sync, size: 17),
                              label: const Text('立即同步'),
                            ),
                          ],
                        ),
                      ],
                      if (c.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            c.error!,
                            style: const TextStyle(color: AppColors.warning),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              if (c.isMobile)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!c.linked) ...[
                        FilledButton.icon(
                          onPressed: c.busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner, size: 20),
                          label: const Text('扫码连接电脑'),
                        ),
                        TextButton(
                          onPressed: c.busy ? null : () => _scan(manual: true),
                          child: const Text('输入连接码'),
                        ),
                      ],
                      if (c.waitingRequest != null) ...[
                        const SizedBox(height: 12),
                        const Text('请在电脑上确认连接'),
                        const SizedBox(height: 8),
                        Text(
                          '校验码 ${c.waitingRequest!['code']}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                      if (c.linked) const Text('已连接电脑，日程变更将自动同步'),
                    ],
                  ),
                )
              else if (c.hasService)
                Surface(
                  child: Column(
                    children: [
                      Text(
                        '手机扫码连接',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (c.qrData != null && c.expiresIn > 0)
                        Semantics(
                          label: '日程表设备连接二维码',
                          child: QrImageView(
                            data: c.qrData!,
                            version: QrVersions.auto,
                            size: 232,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 232,
                          height: 232,
                          child: Center(child: Text('二维码暂不可用')),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            c.expiresIn > 0 ? '${c.expiresIn}秒后自动刷新' : '等待刷新',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: c.busy ? null : () => _act(c.refreshQr),
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('刷新二维码'),
                          ),
                          TextButton(
                            onPressed: c.qrData == null
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: c.qrData!),
                                    );
                                    if (context.mounted) {
                                      showMessage(context, '连接码已复制');
                                    }
                                  },
                            child: const Text('复制连接码'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              for (final request in c.requests) ...[
                const SizedBox(height: 16),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${request['name']} 请求连接'),
                      const SizedBox(height: 8),
                      Text('校验码 ${request['code']}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: c.busy
                                ? null
                                : () => _act(
                                    () => c.confirmPair(
                                      request['requestId'] as String,
                                      true,
                                    ),
                                  ),
                            child: const Text('允许连接'),
                          ),
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => _act(
                                    () => c.confirmPair(
                                      request['requestId'] as String,
                                      false,
                                    ),
                                  ),
                            child: const Text('拒绝'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (c.hasService) ...[
                const SizedBox(height: 24),
                Text('已连接设备', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!c.linked)
                        const Text(
                          '暂无已连接设备',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      for (final device in c.devices.where(
                        (d) => d['id'] != c.identity!.deviceId,
                      ))
                        Row(
                          children: [
                            Icon(
                              device['owner'] == true
                                  ? Icons.computer
                                  : Icons.smartphone,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(device['name'] as String)),
                            TextButton(
                              onPressed: c.busy ? null : () => _unlink(device),
                              child: const Text('断开'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanPairCode extends StatefulWidget {
  const _ScanPairCode();
  @override
  State<_ScanPairCode> createState() => _ScanPairCodeState();
}

class _ScanPairCodeState extends State<_ScanPairCode> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _found = false;
  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('扫描电脑上的二维码'),
    content: SizedBox(
      width: 340,
      height: 300,
      child: MobileScanner(
        controller: _scanner,
        onDetect: (capture) {
          final value = capture.barcodes
              .map((b) => b.rawValue)
              .whereType<String>()
              .firstOrNull;
          if (value != null && !_found) {
            _found = true;
            Navigator.pop(context, value);
          }
        },
        errorBuilder: (context, error) =>
            const Center(child: Text('无法使用相机，请检查相机权限或输入连接码')),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}

class _PastePairCode extends StatefulWidget {
  const _PastePairCode();
  @override
  State<_PastePairCode> createState() => _PastePairCodeState();
}

class _PastePairCodeState extends State<_PastePairCode> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('输入连接码'),
    content: TextField(
      controller: _text,
      minLines: 3,
      maxLines: 5,
      decoration: const InputDecoration(labelText: '电脑端复制的连接码'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('继续'),
      ),
    ],
  );
}
