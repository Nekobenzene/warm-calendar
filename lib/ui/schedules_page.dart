import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../domain/schedule_sort.dart';
import 'components.dart';
import 'event_editor.dart';
import 'theme.dart';

class SchedulesPage extends StatefulWidget {
  final AppController controller;
  final ScheduleStatus? initialStatus;
  final int filterRevision;
  const SchedulesPage({
    super.key,
    required this.controller,
    this.initialStatus,
    this.filterRevision = 0,
  });
  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<SchedulesPage> {
  final _search = TextEditingController();
  ScheduleStatus? _status;
  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
  }

  @override
  void didUpdateWidget(SchedulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRevision != widget.filterRevision) {
      _status = widget.initialStatus;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final query = _search.text.trim().toLowerCase();
    final events = sortSchedules(
      c.events.where(
        (e) =>
            (_status == null || e.statusAt(c.now) == _status) &&
            (query.isEmpty ||
                '${e.title} ${e.notes}'.toLowerCase().contains(query)),
      ),
      c.settings,
      c.now,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '搜索日程',
              hintText: '标题或备注',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () => setState(() => _search.clear()),
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
        ),
        SizedBox(height: phone ? 8 : 20),
        if (phone)
          DropdownButtonFormField<String>(
            key: ValueKey('mobile-status-filter-${widget.filterRevision}'),
            initialValue: _status?.name ?? 'all',
            decoration: const InputDecoration(labelText: '状态'),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text('全部 ${c.events.length}'),
              ),
              for (final status in ScheduleStatus.values)
                DropdownMenuItem(
                  value: status.name,
                  child: Text(
                    '${status.label} ${c.events.where((e) => e.statusAt(c.now) == status).length}',
                  ),
                ),
            ],
            onChanged: (value) => setState(
              () => _status = ScheduleStatus.values
                  .where((s) => s.name == value)
                  .firstOrNull,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text('全部 ${c.events.length}'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final status in ScheduleStatus.values)
                ChoiceChip(
                  label: Text(
                    '${status.label} ${c.events.where((e) => e.statusAt(c.now) == status).length}',
                  ),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
            ],
          ),
        SizedBox(height: phone ? 4 : 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '${events.length}项日程',
              style: const TextStyle(color: AppColors.muted),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<ScheduleSort>(
                  key: const ValueKey('schedule-sort'),
                  value: c.settings.scheduleSort,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final sort in ScheduleSort.values)
                      DropdownMenuItem(value: sort, child: Text(sort.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      runAction(
                        context,
                        () => c.updateSettings(
                          c.settings.copyWith(
                            scheduleSort: v,
                            sortDescending: v == ScheduleSort.updated,
                          ),
                        ),
                      );
                    }
                  },
                ),
                IconButton(
                  tooltip: c.settings.sortDescending
                      ? '倒序，点击改为正序'
                      : '正序，点击改为倒序',
                  onPressed: () => runAction(
                    context,
                    () => c.updateSettings(
                      c.settings.copyWith(
                        sortDescending: !c.settings.sortDescending,
                      ),
                    ),
                  ),
                  icon: Icon(
                    c.settings.sortDescending
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    size: 19,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Surface(
            child: EmptyState(
              c.events.isEmpty ? '还没有日程' : '无匹配日程',
              action: c.events.isEmpty ? '新建日程' : '清除筛选',
              onAction: c.events.isEmpty
                  ? () => openEventEditor(context, c)
                  : () => setState(() {
                      _status = null;
                      _search.clear();
                    }),
            ),
          )
        else if (c.settings.scheduleSort == ScheduleSort.start)
          ..._groups(context, events)
        else
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < events.length; i++) ...[
                  EventRow(
                    event: events[i],
                    controller: c,
                    withDate: true,
                    onEdit: () => openEventEditor(context, c, event: events[i]),
                  ),
                  if (i < events.length - 1) const Divider(),
                ],
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _groups(BuildContext context, List<ScheduleEvent> events) {
    final groups = <String, List<ScheduleEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(dateKey(e.start), () => []).add(e);
    }
    return [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            '${entry.value.first.start.year}年${entry.value.first.start.month}月${entry.value.first.start.day}日  ${widget.controller.calendar.info(entry.value.first.start).week}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                EventRow(
                  event: entry.value[i],
                  controller: widget.controller,
                  onEdit: () => openEventEditor(
                    context,
                    widget.controller,
                    event: entry.value[i],
                  ),
                ),
                if (i < entry.value.length - 1) const Divider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }
}
