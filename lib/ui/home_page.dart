import 'package:flutter/material.dart';
import '../app_controller.dart';
import 'upcoming_panel.dart';
import '../domain/models.dart';
import 'components.dart';
import 'event_editor.dart';
import 'theme.dart';
import 'motion.dart';

class HomePage extends StatelessWidget {
  final AppController controller;
  final void Function(DateTime) onCalendar;
  final void Function(ScheduleStatus) onStatus;
  const HomePage({
    super.key,
    required this.controller,
    required this.onCalendar,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = box.maxWidth / scale >= 900;
      // Short windows and enlarged text scroll instead of shrinking content.
      final bounded = wide && scale <= 1.25 && box.maxHeight >= 500;
      final board = _StatusBoard(
        controller: controller,
        onStatus: onStatus,
        wide: wide,
        bounded: bounded,
      );
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _ClockAndDate(controller: controller),
          const SizedBox(height: 16),
          UpcomingPanel(controller: controller),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '全部日程',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => onCalendar(controller.now),
                child: const Text('查看日历'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (bounded) Expanded(child: board) else board,
        ],
      );
      return bounded
          ? content
          : SingleChildScrollView(
              key: const ValueKey('home-overflow'),
              child: content,
            );
    },
  );
}

class _ClockAndDate extends StatelessWidget {
  final AppController controller;
  const _ClockAndDate({required this.controller});

  @override
  Widget build(BuildContext context) {
    final now = controller.now;
    final info = controller.calendar.info(now);
    final nextTerm = controller.calendar.nextTerm(now);
    final offset = now.timeZoneOffset.inMinutes;
    final zone =
        'UTC${offset < 0 ? '−' : '+'}${pad2(offset.abs() ~/ 60)}:${pad2(offset.abs() % 60)}';
    final localClock = clockText(
      now,
      seconds: true,
      hour24: controller.settings.hour24,
    );
    if (MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
      return Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              children: [
                Text(
                  '${now.year}年${now.month}月${now.day}日',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  info.week,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    localClock,
                    semanticsLabel: '设备时间 $localClock',
                    style: TextStyle(
                      fontSize: controller.settings.hour24 ? 34 : 26,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(zone, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      'UTC ${clockText(now.toUtc(), seconds: true)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!sameDay(now, now.toUtc()))
                      Text(
                        dateKey(now.toUtc()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '农历${info.lunar} · ${info.yearName}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '${nextTerm.name} ${nextTerm.date.month}月${nextTerm.date.day}日',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (info.solarTerm.isNotEmpty ||
                info.festivals.isNotEmpty ||
                info.holiday != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: DayMarkers(info),
              ),
            if (!info.holidayYearKnown)
              const Text(
                '本年度法定节假日数据尚未收录',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
          ],
        ),
      );
    }
    final clock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设备时间 · $zone', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Semantics(
          label: '设备时间',
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!controller.settings.hour24)
                Text(now.hour < 12 ? '上午' : '下午'),
              Text(
                controller.settings.hour24
                    ? localClock
                    : localClock.substring(3),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            const Text(
              'UTC',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            Text(
              '${dateKey(now.toUtc())}  ${clockText(now.toUtc(), seconds: true)}',
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
    final date = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${now.year}年${now.month}月${now.day}日',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            Text(
              info.week,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('农历${info.lunar}  ·  ${info.yearName}'),
        const SizedBox(height: 6),
        Text(
          '${nextTerm.name} ${nextTerm.date.month}月${nextTerm.date.day}日',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (info.solarTerm.isNotEmpty ||
            info.festivals.isNotEmpty ||
            info.holiday != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DayMarkers(info),
          ),
        if (!info.holidayYearKnown)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '本年度法定节假日数据尚未收录',
              style: TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
      ],
    );
    return Surface(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, box) =>
            box.maxWidth / (MediaQuery.textScalerOf(context).scale(14) / 14) >=
                660
            ? Row(
                children: [
                  Expanded(flex: 5, child: clock),
                  const SizedBox(width: 32),
                  Expanded(flex: 6, child: date),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [clock, const SizedBox(height: 16), date],
              ),
      ),
    );
  }
}

class _StatusBoard extends StatelessWidget {
  final AppController controller;
  final void Function(ScheduleStatus) onStatus;
  final bool wide;
  final bool bounded;
  const _StatusBoard({
    required this.controller,
    required this.onStatus,
    required this.wide,
    required this.bounded,
  });

  @override
  Widget build(BuildContext context) {
    final groups = {
      for (final status in ScheduleStatus.values)
        status: controller
            .onDay(controller.now)
            .where((e) => e.statusAt(controller.now) == status)
            .toList(),
    };
    groups[ScheduleStatus.completed]!.sort(
      (a, b) => b.start.compareTo(a.start),
    );
    Widget lane(ScheduleStatus status, {bool showHeading = true}) =>
        _StatusLane(
          key: ValueKey(status),
          status: status,
          events: groups[status]!,
          controller: controller,
          onAll: () => onStatus(status),
          bounded: bounded,
          showHeading: showHeading,
        );
    if (wide) {
      return Row(
        crossAxisAlignment: bounded
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          for (final status in ScheduleStatus.values) ...[
            if (status != ScheduleStatus.pending) const SizedBox(width: 12),
            Expanded(child: lane(status)),
          ],
        ],
      );
    }
    return DefaultTabController(
      length: ScheduleStatus.values.length,
      child: Surface(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            TabBar(
              isScrollable: MediaQuery.textScalerOf(context).scale(1) > 1.3,
              tabAlignment: MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? TabAlignment.start
                  : TabAlignment.fill,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                for (final status in ScheduleStatus.values)
                  Tab(text: '${status.label} ${groups[status]!.length}'),
              ],
            ),
            if (bounded)
              Expanded(
                child: TabBarView(
                  children: [
                    for (final status in ScheduleStatus.values)
                      lane(status, showHeading: false),
                  ],
                ),
              )
            else
              Builder(
                builder: (context) {
                  final tabs = DefaultTabController.of(context);
                  return ListenableBuilder(
                    listenable: tabs,
                    builder: (context, _) => lane(
                      ScheduleStatus.values[tabs.index],
                      showHeading: false,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusLane extends StatefulWidget {
  final ScheduleStatus status;
  final List<ScheduleEvent> events;
  final AppController controller;
  final VoidCallback onAll;
  final bool bounded;
  final bool showHeading;
  const _StatusLane({
    super.key,
    required this.status,
    required this.events,
    required this.controller,
    required this.onAll,
    required this.bounded,
    required this.showHeading,
  });
  @override
  State<_StatusLane> createState() => _StatusLaneState();
}

class _StatusLaneState extends State<_StatusLane> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final list = events.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '暂无${widget.status.label}日程',
              style: const TextStyle(color: AppColors.muted),
            ),
          )
        : widget.bounded
        ? Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ListView.separated(
              key: ValueKey('home-list-${widget.status.name}'),
              controller: _scroll,
              primary: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: events.length,
              itemBuilder: (context, i) => _HomeEventRow(
                event: events[i],
                controller: widget.controller,
              ),
              separatorBuilder: (_, _) => const Divider(),
            ),
          )
        : Column(
            children: [
              for (final event in events.take(4))
                _HomeEventRow(event: event, controller: widget.controller),
            ],
          );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.bounded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.showHeading) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  widget.status.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: widget.status == ScheduleStatus.overdue
                        ? AppColors.warning
                        : widget.status == ScheduleStatus.ongoing
                        ? context.appColors.accent
                        : AppColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${events.length}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
        if (widget.bounded) Expanded(child: list) else list,
        const Divider(),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onAll,
            child: Text(
              '查看全部${widget.status.label}日程',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
    return widget.showHeading
        ? Surface(padding: EdgeInsets.zero, child: content)
        : content;
  }
}

class _HomeEventRow extends StatefulWidget {
  final ScheduleEvent event;
  final AppController controller;
  const _HomeEventRow({required this.event, required this.controller});
  @override
  State<_HomeEventRow> createState() => _HomeEventRowState();
}

class _HomeEventRowState extends State<_HomeEventRow> {
  bool _hovered = false;
  ScheduleEvent get event => widget.event;
  AppController get controller => widget.controller;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: AppMotion.hover(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _hovered
            ? context.appColors.selected.withValues(alpha: .5)
            : context.appColors.selected.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: event.completed ? AppColors.muted : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    eventTimeText(event, controller.settings, withDate: true),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color:
                          event.statusAt(controller.now) ==
                              ScheduleStatus.overdue
                          ? AppColors.warning
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            EventOptionsButton(
              event: event,
              controller: controller,
              onEdit: () => openEventEditor(context, controller, event: event),
            ),
          ],
        ),
      ),
    ),
  );
}
