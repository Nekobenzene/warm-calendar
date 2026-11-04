import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../version.dart';
import 'components.dart';
import 'theme.dart';

class UpdatePanel extends StatelessWidget {
  final AppController controller;
  final bool compact;
  const UpdatePanel({
    super.key,
    required this.controller,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.updater,
    builder: (context, _) {
      final u = controller.updater;
      if (compact && !u.hasUpdate) return const SizedBox.shrink();
      final busy = u.checking || u.downloading || u.installing;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final labels = <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.hasUpdate
                          ? '新版本 ${u.release!.version}'
                          : '版本 $appVersion',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (!compact)
                      Text(
                        !u.supported
                            ? '浏览器预览不执行安装'
                            : u.checking
                            ? '正在检查更新…'
                            : u.checked && !u.hasUpdate
                            ? isLocalPreview
                                  ? '已是最新版本或更新的本地预览版'
                                  : '已是最新版本'
                            : '从 GitHub Releases 获取正式版本',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ];
              final actions = Wrap(
                spacing: 8,
                children: [
                  if (!u.hasUpdate && !compact)
                    OutlinedButton(
                      onPressed: busy || !u.supported ? null : u.check,
                      child: const Text('检查更新'),
                    ),
                  if (u.hasUpdate && !u.downloading)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => u.downloadAndInstall(
                              beforeInstall: controller.prepareForUpdate,
                            ),
                      child: Text(
                        u.installing
                            ? '正在打开安装程序…'
                            : u.downloadedPath != null
                            ? '继续安装'
                            : '下载并安装',
                      ),
                    ),
                  if (u.downloading)
                    TextButton(onPressed: u.cancel, child: const Text('取消')),
                ],
              );
              return box.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
                      430
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...labels,
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: labels.single),
                        const SizedBox(width: 8),
                        actions,
                      ],
                    );
            },
          ),
          if (u.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: u.progress),
            const SizedBox(height: 4),
            Text(
              '${((u.progress ?? 0) * 100).toStringAsFixed(1)}% · ${(u.received / 1048576).toStringAsFixed(1)} / ${(u.release!.bytes / 1048576).toStringAsFixed(1)} MB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (u.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                u.error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          if (!compact && isLocalPreview)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '本地预览使用独立数据；更新仅下载，不覆盖正式安装。',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (!compact && u.supported) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('自动检查更新'),
              value: controller.settings.autoCheckUpdates,
              onChanged: (v) => runAction(
                context,
                () => controller.updateSettings(
                  controller.settings.copyWith(autoCheckUpdates: v),
                ),
              ),
            ),
          ],
        ],
      );
      return compact
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: content,
            )
          : Surface(child: content);
    },
  );
}
