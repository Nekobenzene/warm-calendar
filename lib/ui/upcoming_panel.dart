import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/home_summary.dart';
import '../domain/models.dart';
import 'components.dart';
import 'event_editor.dart';
import 'theme.dart';

class UpcomingPanel extends StatelessWidget {
  final AppController controller;
  final VoidCallback? onSchedules;
  const UpcomingPanel({super.key, required this.controller, this.onSchedules});
  @override
  Widget build(BuildContext context) {
    final next = nextScheduledEvent(controller.events, controller.now);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Surface(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '下一项日程',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => openEventEditor(context, controller),
                          child: const Text('新增日程'),
                        ),
                        TextButton(
                          onPressed: onSchedules,
                          child: const Text('查看日程'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (next == null)
                  const SizedBox(
                    key: ValueKey('upcoming-viewport'),
                    height: 24,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '没有待开始的日程',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                else
                  _UpcomingRow(
                    key: const ValueKey('upcoming-viewport'),
                    event: next,
                    controller: controller,
                    wide: box.maxWidth / scale >= 600,
                    first: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  final ScheduleEvent event;
  final AppController controller;
  final bool wide;
  final bool first;
  const _UpcomingRow({
    super.key,
    required this.event,
    required this.controller,
    required this.wide,
    required this.first,
  });
  @override
  Widget build(BuildContext context) {
    final details = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '开始 ${event.start.year}年${event.start.month}月${event.start.day}日 ${clockText(event.start, hour24: controller.settings.hour24)}${event.allDay ? ' · 全天' : ''}',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
            height: 1.3,
          ),
        ),
      ],
    );
    final countdown = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '距开始',
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.3),
        ),
        const SizedBox(height: 4),
        Text(
          countdownText(event.start, controller.now),
          key: first ? const ValueKey('next-countdown') : null,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: context.appColors.accent,
            fontFeatures: [FontFeature.tabularFigures()],
            height: 1.2,
          ),
        ),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight:
            (wide ? 64.0 : 88.0) *
            (MediaQuery.textScalerOf(context).scale(14) / 14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openEventEditor(context, controller, event: event),
          hoverColor: context.appColors.selected.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: wide
                ? Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 24),
                      SizedBox(width: 172, child: countdown),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      details,
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '距开始',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          Text(
                            countdownText(event.start, controller.now),
                            key: first
                                ? const ValueKey('next-countdown')
                                : null,
                            style: TextStyle(
                              fontSize: 18,
                              color: context.appColors.accent,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
