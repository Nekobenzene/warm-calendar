import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/calendar_service.dart';
import '../domain/recurrence.dart';
import 'node_editor.dart';
import 'motion.dart';
import 'theme.dart';
import '../app_controller.dart';
import '../domain/item_clipboard.dart';
import 'item_context_menu.dart';

Future<RecurrenceRule?> editRepeatRule(
  BuildContext context, {
  required RecurrenceRule initial,
  required CalendarService calendar,
  required DateTime start,
  required DateTime end,
  required bool allDay,
  ScheduleEvent? template,
  AppController? controller,
}) => showAppDialog<RecurrenceRule>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RepeatEditor(
    initial: initial,
    calendar: calendar,
    start: start,
    end: end,
    allDay: allDay,
    template: template,
    controller: controller,
  ),
);

class _RepeatEditor extends StatefulWidget {
  final AppController? controller;
  final RecurrenceRule initial;
  final CalendarService calendar;
  final DateTime start, end;
  final bool allDay;
  final ScheduleEvent? template;
  const _RepeatEditor({
    required this.initial,
    required this.calendar,
    required this.start,
    required this.end,
    required this.allDay,
    this.template,
    this.controller,
  });
  @override
  State<_RepeatEditor> createState() => _RepeatEditorState();
}

class _RepeatEditorState extends State<_RepeatEditor> {
  Widget _clipboard(Widget child, {RecurrenceNode? node}) =>
      widget.controller == null
      ? child
      : ItemContextMenu(
          controller: widget.controller!,
          isTodo: false,
          event: node == null
              ? null
              : widget.controller?.events
                    .where(
                      (e) =>
                          e.seriesId == widget.template?.id &&
                          e.nodeId == node.id,
                    )
                    .firstOrNull,
          onPaste: (draft) => setState(() {
            if (_nodes.length < 24) {
              _nodes.add(
                clipboardNode(
                  draft,
                  periodDays: _frequency == RepeatFrequency.monthly
                      ? 28
                      : _days,
                ),
              );
            }
          }),
          child: child,
        );
  final _form = GlobalKey<FormState>();
  late RepeatFrequency _frequency = widget.initial.frequency;
  late final _until = TextEditingController(
        text: dateKey(widget.initial.until),
      ),
      _interval = TextEditingController(text: '${widget.initial.intervalDays}'),
      _count = TextEditingController(
        text: '${widget.initial.cycleCount ?? 10}',
      ),
      _month = TextEditingController(
        text:
            (widget.initial.monthDays.isEmpty
                    ? [widget.start.day]
                    : widget.initial.monthDays)
                .join('、'),
      );
  late bool _byCount = widget.initial.cycleCount != null;
  late final Set<int> _week =
      (widget.initial.weekdays.isEmpty
              ? [widget.start.weekday]
              : widget.initial.weekdays)
          .toSet();
  late final List<RecurrenceNode> _nodes = widget.initial.nodes.isNotEmpty
      ? widget.initial.nodes.toList()
      : [
          for (final m in widget.initial.minutes)
            RecurrenceNode(
              automation: widget.template?.automation ?? const ItemAutomation(),
              id: 'legacy-$m',
              minute: widget.allDay ? 0 : m,
              durationMinutes: widget.end.difference(widget.start).inMinutes,
              allDay: widget.allDay,
              legacyMinute: m,
              color: widget.template?.color ?? 0xFFE4EAD9,
              completedColor: widget.template?.completedColor ?? 0xFFE2E3DF,
              reminderOffsets: widget.template?.reminderOffsets ?? const [10],
              reminderSound: widget.template?.reminderSound ?? true,
              holidayPolicy: widget.initial.holidayPolicy,
              weekendHolidayPriority: widget.initial.weekendHolidayPriority,
            ),
        ];
  String? _error;
  int get _days => switch (_frequency) {
    RepeatFrequency.daily => 1,
    RepeatFrequency.weekly => 7,
    RepeatFrequency.monthly => 31,
    RepeatFrequency.interval => (int.tryParse(_interval.text) ?? 1).clamp(
      1,
      365,
    ),
  };
  @override
  void dispose() {
    for (final c in [_until, _interval, _count, _month]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _date(String v) {
    final d = DateTime.tryParse(v);
    return d != null && dateKey(d) == v && d.year >= 1901 && d.year <= 2099
        ? d
        : null;
  }

  Future<void> _edit(RecurrenceNode? old) async {
    final seed =
        old ??
        (_nodes.lastOrNull ?? const RecurrenceNode(id: 'seed')).copyWith(
          id: 'node-${DateTime.now().microsecondsSinceEpoch}',
          title: '',
          notes: '',
          dayOffset: 0,
        );
    final n = await editCycleNode(
      context,
      seed,
      _days,
      controller: widget.controller,
      sourceEvent: widget.controller?.events
          .where(
            (e) => e.seriesId == widget.template?.id && e.nodeId == seed.id,
          )
          .firstOrNull,
      monthly: _frequency == RepeatFrequency.monthly,
      fixedStartDay: true,
    );
    if (n != null && mounted) {
      setState(() {
        final i = _nodes.indexWhere((v) => v.id == n.id);
        if (i < 0) {
          _nodes.add(n);
        } else {
          _nodes[i] = n;
        }
      });
    }
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final rule = RecurrenceRule(
      frequency: _frequency,
      until: _byCount ? DateTime(2099, 12, 31) : _date(_until.text)!,
      cycleCount: _byCount ? int.parse(_count.text) : null,
      intervalDays: int.tryParse(_interval.text) ?? 2,
      weekdays: _week.toList()..sort(),
      monthDays: _month.text
          .split(RegExp(r'[,，、\s]+'))
          .where((s) => s.isNotEmpty)
          .map((s) => int.tryParse(s) ?? 0)
          .toList(),
      minutes: widget.allDay
          ? const [0]
          : [widget.start.hour * 60 + widget.start.minute],
      nodes: List.unmodifiable(_nodes),
      shiftMinutes: widget.initial.shiftMinutes,
      holidayPolicy: widget.initial.holidayPolicy,
      weekendHolidayPriority: widget.initial.weekendHolidayPriority,
    );
    try {
      expandSeries(
        ScheduleEvent(
          id: 'preview',
          title: '重复预览',
          start: widget.start.add(Duration(minutes: rule.shiftMinutes)),
          end: widget.end.add(Duration(minutes: rule.shiftMinutes)),
          allDay: widget.allDay,
          updatedAt: DateTime.now(),
          recurrence: rule,
        ),
        widget.calendar,
        validate: true,
      );
      Navigator.pop(context, rule);
    } on FormatException catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => _clipboard(_dialog(context));
  Widget _dialog(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('重复日程设置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<RepeatFrequency>(
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: '频率'),
                        items: const [
                          DropdownMenuItem(
                            value: RepeatFrequency.daily,
                            child: Text('每日'),
                          ),
                          DropdownMenuItem(
                            value: RepeatFrequency.weekly,
                            child: Text('每周'),
                          ),
                          DropdownMenuItem(
                            value: RepeatFrequency.monthly,
                            child: Text('每月'),
                          ),
                          DropdownMenuItem(
                            value: RepeatFrequency.interval,
                            child: Text('每N日'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _frequency = v!),
                      ),
                      if (_frequency == RepeatFrequency.weekly)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (var i = 1; i <= 7; i++)
                                FilterChip(
                                  label: Text(
                                    '周${const ['一', '二', '三', '四', '五', '六', '日'][i - 1]}',
                                  ),
                                  selected: _week.contains(i),
                                  onSelected: (v) => setState(
                                    () => v ? _week.add(i) : _week.remove(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (_frequency == RepeatFrequency.monthly)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextFormField(
                            controller: _month,
                            decoration: const InputDecoration(
                              labelText: '每月日期',
                              hintText: '1、15、28',
                            ),
                            validator: (s) {
                              final values = (s ?? '')
                                  .split(RegExp(r'[,，、\s]+'))
                                  .where((s) => s.isNotEmpty)
                                  .map(int.tryParse)
                                  .toList();
                              return values.isEmpty ||
                                      values.toSet().length != values.length ||
                                      values.any(
                                        (v) => v == null || v < 1 || v > 31,
                                      )
                                  ? '填写1—31，不存在的日期跳过'
                                  : null;
                            },
                          ),
                        ),
                      if (_frequency == RepeatFrequency.interval)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextFormField(
                            controller: _interval,
                            decoration: const InputDecoration(
                              labelText: '重复周期',
                              suffixText: '天',
                            ),
                            validator: (s) =>
                                (int.tryParse(s ?? '') ?? 0) < 1 ||
                                    (int.tryParse(s ?? '') ?? 0) > 365
                                ? '填写1—365'
                                : null,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Expanded(child: Text('日程节点')),
                          TextButton.icon(
                            onPressed: _nodes.length >= 24
                                ? null
                                : () => _edit(null),
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('添加节点'),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 180,
                        child: ListView(
                          children: [
                            for (var i = 0; i < _nodes.length; i++)
                              _clipboard(
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  title: Text(
                                    _nodes[i].title.isEmpty
                                        ? '节点 ${i + 1} · 使用组标题'
                                        : _nodes[i].title,
                                  ),
                                  subtitle: Text(
                                    '${pad2(_nodes[i].minute ~/ 60)}:${pad2(_nodes[i].minute % 60)} · ${_nodes[i].isPoint ? '时间点' : '${_nodes[i].durationMinutes}分钟'}',
                                  ),
                                  onTap: () => _edit(_nodes[i]),
                                  trailing: IconButton(
                                    tooltip: '移除节点',
                                    onPressed: () =>
                                        setState(() => _nodes.removeAt(i)),
                                    icon: const Icon(Icons.close, size: 17),
                                  ),
                                ),
                                node: _nodes[i],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('停止日期'),
                            selected: !_byCount,
                            onSelected: (_) => setState(() => _byCount = false),
                          ),
                          ChoiceChip(
                            label: const Text('循环周期数'),
                            selected: _byCount,
                            onSelected: (_) => setState(() => _byCount = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_byCount)
                        TextFormField(
                          controller: _count,
                          decoration: const InputDecoration(
                            labelText: '循环周期数',
                            suffixText: '轮',
                          ),
                          validator: (s) =>
                              (int.tryParse(s ?? '') ?? 0) < 1 ||
                                  (int.tryParse(s ?? '') ?? 0) > 10000
                              ? '填写1—10000'
                              : null,
                        )
                      else
                        TextFormField(
                          controller: _until,
                          decoration: InputDecoration(
                            labelText: '停止日期',
                            suffixIcon: IconButton(
                              tooltip: '选择停止日期',
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _date(_until.text) ?? widget.start,
                                  firstDate: DateTime(1901),
                                  lastDate: DateTime(2099, 12, 31),
                                );
                                if (d != null) {
                                  setState(() => _until.text = dateKey(d));
                                }
                              },
                            ),
                          ),
                          validator: (s) =>
                              _date(s ?? '') == null ? '使用YYYY-MM-DD' : null,
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _apply, child: const Text('应用重复规则')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
