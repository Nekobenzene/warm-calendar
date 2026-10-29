import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'theme.dart';

class HolidayDataSettings extends StatelessWidget {
  final AppController controller;
  const HolidayDataSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, years = c.calendar.holidayYears.toList()..sort();
    final checked = c.settings.holidayCheckedAt == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(c.settings.holidayCheckedAt);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('自动更新法定假期与调休')),
              Switch(
                value: c.settings.autoUpdateHolidays,
                onChanged: (v) => runAction(
                  context,
                  () => c.updateSettings(
                    c.settings.copyWith(autoUpdateHolidays: v),
                  ),
                ),
              ),
            ],
          ),
          const Text(
            '联网时每天检查；已下载数据可离线查看。农历、节日和节气可计算至2099年。',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Text('已收录假期：${years.join('、')}年'),
          const SizedBox(height: 4),
          const Text(
            '未来年份的法定放假和调休按公告更新，未公布时不推算。',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (checked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '上次检查：${dateKey(checked)} ${clockText(checked)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (c.holidayUpdateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.holidayUpdateError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: c.holidayRefreshing
                  ? null
                  : () async {
                      await c.refreshHolidayData();
                      if (context.mounted) {
                        showMessage(
                          context,
                          c.holidayUpdateError ?? '已更新已公布的假期数据',
                          error: c.holidayUpdateError != null,
                        );
                      }
                    },
              child: Text(c.holidayRefreshing ? '正在更新…' : '立即更新'),
            ),
          ),
        ],
      ),
    );
  }
}
