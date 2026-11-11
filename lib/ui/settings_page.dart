import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'theme.dart';
import 'motion.dart';
import 'appearance.dart';
import 'holiday_settings.dart';
import 'update_panel.dart';

class SettingsPage extends StatefulWidget {
  final AppController controller;
  final VoidCallback? onManageLinks;
  const SettingsPage({super.key, required this.controller, this.onManageLinks});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  String get _deviceName {
    final c = widget.controller;
    return c.settings.deviceName.isNotEmpty
        ? c.settings.deviceName
        : (c.link?.connection?['device'] as Map?)?['name'] as String? ??
              (defaultTargetPlatform == TargetPlatform.android
                  ? '安卓手机'
                  : '我的电脑');
  }

  Future<void> _rename() async {
    final c = widget.controller;
    final field = TextEditingController(text: _deviceName);
    final form = GlobalKey<FormState>();
    final name = await showAppDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('设备名称'),
        content: SizedBox(
          width: 320,
          child: Form(
            key: form,
            child: TextFormField(
              key: const ValueKey('device-name-input'),
              controller: field,
              maxLength: 60,
              autofocus: true,
              decoration: const InputDecoration(labelText: '设备名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入设备名称' : null,
              onFieldSubmitted: (_) {
                if (form.currentState!.validate()) {
                  Navigator.pop(ctx, field.text.trim());
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, field.text.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 220));
    field.dispose();
    if (name == null || !mounted) return;
    await runAction(context, () async {
      await c.updateSettings(c.settings.copyWith(deviceName: name));
      if (mounted) showMessage(context, '设备名称已保存');
    });
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final filename = '日程备份-${dateKey(widget.controller.now)}.json';
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(widget.controller.exportBackup())),
        mimeType: 'application/json',
        name: filename,
      );
      if (kIsWeb) {
        await file.saveTo(filename);
      } else {
        final path = await getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (path == null) return;
        await file.saveTo(path.path);
      }
      if (mounted) showMessage(context, kIsWeb ? '备份下载已发起' : '备份已导出');
    } catch (_) {
      if (mounted) showMessage(context, '导出失败，请重试或检查保存位置。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JSON 备份',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('备份文件不能超过 10 MB');
      }
      final backup = BackupData.decode(await file.readAsString());
      if (!mounted) return;
      final activeCount = backup.events.where((e) => !e.deleted).length;
      final yes = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入备份'),
          content: Text(
            '备份含 $activeCount 项日程。相同日程按修改时间保留较新版本，包括删除状态。显示与提醒设置将恢复为备份值。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('合并导入'),
            ),
          ],
        ),
      );
      if (yes == true) {
        await widget.controller.importBackup(backup);
        if (mounted) showMessage(context, '备份已导入');
      }
    } on FormatException catch (e) {
      if (mounted) showMessage(context, '${e.message}。现有数据未更改。', error: true);
    } catch (_) {
      if (mounted) showMessage(context, '导入失败。请检查备份文件后重试。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _permission() async {
    final result = await widget.controller.notifications.requestPermission();
    await widget.controller.reloadSyncedEvents();
    if (mounted) {
      setState(() {});
      showMessage(
        context,
        result == 'granted'
            ? '已允许系统通知'
            : result == 'denied'
            ? widget.controller.notifications.android
                  ? '请在系统通知设置中允许通知和弹出提醒。'
                  : widget.controller.notifications.desktop
                  ? 'Windows已关闭通知，可在系统通知设置中修改。'
                  : '系统通知被拒绝。可在浏览器站点设置中修改。'
            : '未授予通知权限',
        error: result != 'granted',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final permission = c.notifications.permission;
    final permissionText = switch (permission) {
      'granted' => '已允许',
      'denied' => '已拒绝',
      'default' => '未授权',
      'unregistered' => '待首次通知确认',
      _ => '当前平台暂未接入',
    };
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('外观', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AppearanceSettings(controller: c),
            const SizedBox(height: 28),
            ...[
              Text('日历', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _switchRow(
                      '周一作为每周第一天',
                      c.settings.mondayFirst,
                      (v) =>
                          c.updateSettings(c.settings.copyWith(mondayFirst: v)),
                    ),
                    const Divider(),
                    _switchRow(
                      '24小时制',
                      c.settings.hour24,
                      (v) => c.updateSettings(c.settings.copyWith(hour24: v)),
                    ),
                    const Divider(),
                    _switchRow(
                      '日历显示农历',
                      c.settings.showLunar,
                      (v) =>
                          c.updateSettings(c.settings.copyWith(showLunar: v)),
                    ),
                    const Divider(),
                    _switchRow(
                      '拖动时吸附时间网格',
                      c.settings.snapToGrid,
                      (v) =>
                          c.updateSettings(c.settings.copyWith(snapToGrid: v)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '选中后可拖动和调整边界；手机先选择拖动。Shift＋滚轮或双指捏合缩放，关闭吸附时精确到分钟。',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            HolidayDataSettings(controller: c),
            ...[
              const SizedBox(height: 28),

              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _switchRow(
                      '启用提醒',
                      c.settings.remindersEnabled,
                      (v) => c.updateSettings(
                        c.settings.copyWith(remindersEnabled: v),
                      ),
                    ),
                    const Divider(),
                    _switchRow(
                      '系统通知',
                      c.settings.systemNotificationsEnabled,
                      (v) => c.updateSettings(
                        c.settings.copyWith(systemNotificationsEnabled: v),
                      ),
                    ),
                    const Divider(),
                    _switchRow(
                      '通知提示音',
                      c.settings.notificationSound,
                      (v) => c.updateSettings(
                        c.settings.copyWith(notificationSound: v),
                      ),
                    ),
                    if (c.notifications.android) ...[
                      const Divider(),
                      _switchRow(
                        '通知振动',
                        c.settings.notificationVibration,
                        (v) => c.updateSettings(
                          c.settings.copyWith(notificationVibration: v),
                        ),
                      ),
                    ],
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('通知权限'),
                              const SizedBox(height: 4),
                              Text(
                                permissionText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          if ((c.notifications.desktop ||
                                  c.notifications.android) &&
                              c.notifications.supported)
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => runAction(
                                      context,
                                      c.notifications.openSystemSettings,
                                    ),
                              child: const Text('系统通知设置'),
                            ),
                          if (c.notifications.supported &&
                              (!c.notifications.desktop &&
                                  (!c.notifications.android ||
                                      permission != 'granted')))
                            OutlinedButton(
                              onPressed: permission == 'granted' || _busy
                                  ? null
                                  : _permission,
                              child: Text(
                                permission == 'granted' ? '已允许通知' : '允许通知',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (c.notifications.android)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              c.notifications.exactAlarms
                                  ? '精确提醒已允许'
                                  : '未允许精确提醒，可能延迟',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            if (!c.notifications.exactAlarms)
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => runAction(context, () async {
                                        await c.notifications
                                            .requestExactAlarms();
                                        await c.reloadSyncedEvents();
                                        if (mounted) setState(() {});
                                      }),
                                child: const Text('允许精确提醒'),
                              ),
                          ],
                        ),
                      ),
                    if (c.notifications.supported)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => runAction(
                                    context,
                                    () => c.notifications.testNotification(
                                      sound: c.settings.notificationSound,
                                    ),
                                  ),
                            icon: const Icon(
                              Icons.notifications_outlined,
                              size: 18,
                            ),
                            label: const Text('发送测试提醒'),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        c.notifications.desktop
                            ? '未来30天内最近512条提醒交给Windows定时发送，已排定${c.notifications.scheduledCount}条。托盘运行时每分钟续排；彻底退出后仍会发送已排定提醒。系统勿扰和休眠可能影响显示与声音。'
                            : c.notifications.android
                            ? '提示音使用系统通知音量，横幅需在系统通知设置中允许弹出。已排定${c.notifications.scheduledCount}条，后台仍可提醒；系统强行停止应用会中断提醒。'
                            : '网页版需保持应用打开以检查提醒。通知声音由浏览器和系统控制。',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    if (c.notificationErrorDetail != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => showAppDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('通知错误详情'),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  c.notificationErrorDetail!,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('通知错误详情'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text('设备与同步', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('设备名称'),
                        const SizedBox(height: 4),
                        Text(
                          _deviceName,
                          style: const TextStyle(color: AppColors.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('rename-device'),
                    onPressed: _rename,
                    child: const Text('修改'),
                  ),
                ],
              ),
            ),
            if (widget.onManageLinks != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onManageLinks,
                  child: const Text('管理设备连接'),
                ),
              ),

            if (c.notifications.desktop) ...[
              const SizedBox(height: 28),

              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _switchRow(
                      '关闭窗口后留在托盘',
                      c.settings.closeToTray,
                      (v) =>
                          c.updateSettings(c.settings.copyWith(closeToTray: v)),
                    ),
                    const Divider(),
                    _switchRow(
                      '开机启动（托盘运行）',
                      c.settings.launchAtStartup,
                      (v) => c.updateSettings(
                        c.settings.copyWith(launchAtStartup: v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ...[
              const SizedBox(height: 28),
              Text('数据与备份', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('日程保存在此设备'),
                    const SizedBox(height: 6),
                    Text(
                      kIsWeb
                          ? '清除浏览器站点数据会删除网页版日程，请定期导出备份。'
                          : c.notifications.desktop
                          ? 'Windows卸载保留日程数据；清除应用数据会删除日程，请定期导出备份。'
                          : '卸载应用或清除应用数据会删除本机日程，请定期导出备份。',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _export,
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('导出备份'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _import,
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('导入备份'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            ...[
              const SizedBox(height: 28),
              Text('关于', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              UpdatePanel(controller: c),
              const SizedBox(height: 12),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('农历、节日与节气'),
                    const SizedBox(height: 6),
                    const Text(
                      'lunar 开源历法库',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 18),
                    const Text('中国大陆法定节假日与调休'),
                    const SizedBox(height: 6),
                    Text(
                      '已收录：${c.calendar.holidayYears.join('、')}年',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const SelectableText(
                      '来源：国务院办公厅年度放假通知 / holiday-cn 数据集',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '未收录年份仍可查看农历和节气，放假及调休不作推算。',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    String label,
    bool value,
    Future<void> Function(bool) change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Semantics(
          label: label,
          child: Switch(
            value: value,
            onChanged: _busy
                ? null
                : (v) async {
                    setState(() => _busy = true);
                    await runAction(context, () => change(v));
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ),
      ],
    ),
  );
}
