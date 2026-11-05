import 'dart:math';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'node_editor.dart';
import 'theme.dart';

Widget repeatModeSelector(int value, ValueChanged<int> change) => LayoutBuilder(
  builder: (context, box) {
    const names = ['不重复', '重复日程', '重复周期'];
    if (box.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 310) {
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              label: Text(names[i]),
              selected: value == i,
              showCheckmark: false,
              onSelected: (_) => change(i),
            ),
        ],
      );
    }
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('不重复')),
        ButtonSegment(value: 1, label: Text('重复日程')),
        ButtonSegment(value: 2, label: Text('重复周期')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (v) => change(v.single),
    );
  },
);

class CycleEditor extends StatefulWidget {
  final AppController controller;
  final ScheduleEvent initial;
  final void Function(int, ScheduleEvent) onMode;
  const CycleEditor({
    super.key,
    required this.controller,
    required this.initial,
    required this.onMode,
  });
  @override
  State<CycleEditor> createState() => _CycleEditorState();
}

class _CycleEditorState extends State<CycleEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial.title),
      _notes = TextEditingController(text: widget.initial.notes),
      _start = TextEditingController(
        text: dateKey(
          widget.initial.start.subtract(
            Duration(minutes: widget.initial.recurrence?.shiftMinutes ?? 0),
          ),
        ),
      ),
      _until = TextEditingController(
        text: dateKey(
          widget.initial.recurrence?.until ??
              DateTime(
                widget.initial.start.year,
                widget.initial.start.month + 3,
                widget.initial.start.day,
              ),
        ),
      ),
      _interval = TextEditingController(
        text: '${widget.initial.recurrence?.intervalDays ?? 2}',
      ),
      _count = TextEditingController(
        text: '${widget.initial.recurrence?.cycleCount ?? 10}',
      );
  late RepeatFrequency _frequency =
      widget.initial.recurrence?.frequency ?? RepeatFrequency.daily;
  late bool _byCount = widget.initial.recurrence?.cycleCount != null,
      _weekLabels = widget.initial.recurrence?.weekLabels ?? false;
  late final List<RecurrenceNode> _nodes = _initialNodes();
  int _day = 0;
  bool _saving = false;
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
  List<RecurrenceNode> _initialNodes() {
    final e = widget.initial, r = e.recurrence;
    if (r?.nodes.isNotEmpty == true) return r!.nodes.toList();
    final times = r?.minutes ?? [e.start.hour * 60 + e.start.minute];
    return [
      for (var i = 0; i < times.length; i++)
        RecurrenceNode(
          id: r == null ? 'node-$i' : 'legacy-${times[i]}',
          minute: e.allDay ? 0 : times[i],
          durationMinutes: e.end.difference(e.start).inMinutes,
          allDay: e.allDay,
          reminderOffsets: e.reminderOffsets,
          reminderSound: e.reminderSound,
          color: e.color,
          completedColor: e.completedColor,
          holidayPolicy: r?.holidayPolicy ?? HolidayPolicy.ignore,
          weekendHolidayPriority:
              r?.weekendHolidayPriority ?? WeekendHolidayPriority.holiday,
          legacyMinute: r == null ? null : times[i],
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in [_title, _notes, _start, _until, _interval, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  String _label(int day) =>
      _frequency == RepeatFrequency.weekly && _weekLabels && day < 7
      ? '周${const ['一', '二', '三', '四', '五', '六', '日'][day]}'
      : 'Day${day + 1}';
  DateTime? _date(String v) {
    final d = DateTime.tryParse(v);
    return d != null && dateKey(d) == v && d.year >= 1901 && d.year <= 2099
        ? d
        : null;
  }

  Future<void> _pick(TextEditingController field) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date(field.text) ?? widget.controller.now,
      firstDate: DateTime(1901),
      lastDate: DateTime(2099, 12, 31),
    );
    if (d != null) setState(() => field.text = dateKey(d));
  }

  Widget _dateField(String label, TextEditingController field) => TextFormField(
    controller: field,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        onPressed: () => _pick(field),
        tooltip: '选择$label',
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
    ),
    validator: (s) => _date(s ?? '') == null ? '使用YYYY-MM-DD' : null,
  );
  ScheduleEvent _draft() {
    final first = _nodes.firstOrNull;
    final rule = RecurrenceRule(
      kind: RepeatKind.cycle,
      frequency: _frequency,
      until: _byCount
          ? DateTime(2099, 12, 31)
          : (_date(_until.text) ?? widget.initial.start),
      intervalDays: int.tryParse(_interval.text) ?? 2,
      nodes: List.unmodifiable(_nodes),
      cycleCount: _byCount ? int.tryParse(_count.text) : null,
      weekLabels: _weekLabels,
      shiftMinutes: widget.initial.recurrence?.shiftMinutes ?? 0,
    );
    final start = (_date(_start.text) ?? dayOnly(widget.initial.start)).add(
      Duration(minutes: rule.shiftMinutes),
    );
    return ScheduleEvent(
      id: widget.initial.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      start: start,
      end: start.add(Duration(minutes: first?.durationMinutes ?? 0)),
      updatedAt: DateTime.now().toUtc(),
      recurrence: rule,
      revision: widget.initial.revision + 1,
      reminderOffsets: const [],
      color: first?.color ?? widget.initial.color,
      completedColor: first?.completedColor ?? widget.initial.completedColor,
    );
  }

  Future<void> _edit(RecurrenceNode? old) async {
    final seed =
        old ??
        (_nodes.lastOrNull ?? const RecurrenceNode(id: 'seed')).copyWith(
          id: 'node-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(99999)}',
          title: '',
          notes: '',
          dayOffset: _day,
        );
    final node = await editCycleNode(
      context,
      seed,
      _days,
      monthly: _frequency == RepeatFrequency.monthly,
      weekLabels: _frequency == RepeatFrequency.weekly && _weekLabels,
    );
    if (node != null && mounted) {
      setState(() {
        final i = _nodes.indexWhere((n) => n.id == node.id);
        if (i < 0) {
          _nodes.add(node);
        } else {
          _nodes[i] = node;
        }
        _day = node.dayOffset;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveEvent(_draft());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is FormatException ? e.message.toString() : '保存失败，草稿已保留';
        });
      }
    }
  }

  Widget _nodeList() {
    final nodes = _nodes.where((n) => n.dayOffset == _day).toList()
      ..sort((a, b) => a.minute.compareTo(b.minute));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _days == 1 ? '节点' : _label(_day),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('添加节点'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              if (nodes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('这一天没有节点', textAlign: TextAlign.center),
                ),
              for (final n in nodes)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    n.title.isEmpty ? '使用组标题' : n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    n.allDay
                        ? '全天 · ${n.durationMinutes ~/ 1440}天'
                        : '${pad2(n.minute ~/ 60)}:${pad2(n.minute % 60)}${n.isPoint ? ' · 时间点' : ' → ${_label(n.dayOffset + (n.minute + n.durationMinutes) ~/ 1440)} ${pad2((n.minute + n.durationMinutes) % 1440 ~/ 60)}:${pad2((n.minute + n.durationMinutes) % 60)}'}',
                  ),
                  leading: Container(
                    width: 10,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(n.color),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  onTap: () => _edit(n),
                  trailing: IconButton(
                    tooltip: '移除节点',
                    onPressed: () => setState(() => _nodes.remove(n)),
                    icon: const Icon(Icons.close, size: 17),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '重复周期',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              repeatModeSelector(2, (m) => widget.onMode(m, _draft())),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _title,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: '组标题',
                            counterText: '',
                          ),
                          validator: (s) => hasValidGroupTitle(s ?? '', _nodes)
                              ? null
                              : '组标题为空时，每个节点都需填写标题',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<RepeatFrequency>(
                                initialValue: _frequency,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '频率',
                                ),
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
                                    value: RepeatFrequency.interval,
                                    child: Text('每N日循环'),
                                  ),
                                  DropdownMenuItem(
                                    value: RepeatFrequency.monthly,
                                    child: Text('每月'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _frequency = v;
                                      _day = 0;
                                    });
                                  }
                                },
                              ),
                            ),
                            if (_frequency == RepeatFrequency.interval) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 96,
                                child: TextFormField(
                                  controller: _interval,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '周期',
                                    suffixText: '天',
                                  ),
                                  onChanged: (_) => setState(() => _day = 0),
                                  validator: (s) =>
                                      (int.tryParse(s ?? '') ?? 0) < 1 ||
                                          (int.tryParse(s ?? '') ?? 0) > 365
                                      ? '1—365'
                                      : null,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_frequency == RepeatFrequency.weekly)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('以周一至周日记日'),
                              value: _weekLabels,
                              onChanged: (v) => setState(() => _weekLabels = v),
                            ),
                          ),
                        if (_nodes.any((n) => n.dayOffset >= _days))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '有节点超出当前周期，请恢复周期后移入有效日期',
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: (MediaQuery.sizeOf(context).height * .32)
                              .clamp(170.0, 320.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_days > 1) ...[
                                SizedBox(
                                  width: MediaQuery.sizeOf(context).width < 600
                                      ? 70
                                      : 100,
                                  child: ListView.builder(
                                    itemCount: _days,
                                    itemBuilder: (context, i) => ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                      selected: _day == i,
                                      selectedTileColor:
                                          context.appColors.selected,
                                      title: Text(_label(i)),
                                      onTap: () => setState(() => _day = i),
                                    ),
                                  ),
                                ),
                                const VerticalDivider(width: 12),
                              ],
                              Expanded(child: _nodeList()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _dateField('开始日期', _start),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('停止日期'),
                              selected: !_byCount,
                              onSelected: (_) =>
                                  setState(() => _byCount = false),
                            ),
                            ChoiceChip(
                              label: const Text('循环周期数'),
                              selected: _byCount,
                              onSelected: (_) =>
                                  setState(() => _byCount = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_byCount)
                          TextFormField(
                            controller: _count,
                            keyboardType: TextInputType.number,
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
                          _dateField('停止日期', _until),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 3,
                          maxLength: 4000,
                          decoration: const InputDecoration(
                            labelText: '全局备注',
                            counterText: '',
                          ),
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
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存周期'),
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
