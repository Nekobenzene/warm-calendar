import 'dart:math';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../domain/todos.dart';
import 'color_picker.dart';
import 'components.dart';
import 'motion.dart';
import 'reminder_editor.dart';
import 'holiday_policy_field.dart';
import 'theme.dart';

Future<void> openTodoEditor(
  BuildContext context,
  AppController controller, {
  ScheduleEvent? task,
}) async {
  var editing = task;
  if (task?.seriesId != null) {
    final group = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑重复待办'),
        content: const Text('单独处理过的待办会保留本次修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('仅编辑本次'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('编辑重复组'),
          ),
        ],
      ),
    );
    if (group == null || !context.mounted) return;
    if (group) editing = controller.seriesFor(task!);
    if (editing == null) return;
  }
  if (!context.mounted) return;
  await showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TodoEditor(controller: controller, task: editing),
  );
}

class TodoEditor extends StatefulWidget {
  final AppController controller;
  final ScheduleEvent? task;
  final bool nodeMode;
  final TodoRepeatNode? repeatNode;
  final String groupTitle;
  final int periodDays;
  const TodoEditor({
    super.key,
    required this.controller,
    this.task,
    this.nodeMode = false,
    this.repeatNode,
    this.groupTitle = '',
    this.periodDays = 1,
  });
  @override
  State<TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<TodoEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.repeatNode?.item.title ?? widget.task?.title ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.repeatNode?.item.notes ?? widget.task?.notes ?? '',
  );
  late final _interval = TextEditingController(
    text: '${widget.task?.todoRepeat?.intervalDays ?? 1}',
  );
  late final _day = TextEditingController(
    text: '${(widget.repeatNode?.deadlineMinutes ?? 0) ~/ 1440 + 1}',
  );
  final _dayField = GlobalKey<FormFieldState<String>>();
  late TimeOfDay _nodeTime = TimeOfDay(
    hour: (widget.repeatNode?.deadlineMinutes ?? 0) % 1440 ~/ 60,
    minute: (widget.repeatNode?.deadlineMinutes ?? 0) % 60,
  );
  late bool _repeat = widget.task?.todoRepeat != null;
  late bool _removeAfterCycle = widget.repeatNode?.removeAfterCycle ?? true;
  late bool _dated = widget.nodeMode
      ? widget.repeatNode?.deadlineMinutes != null
      : (widget.task?.hasDeadline ?? false);
  late DateTime _deadline =
      widget.task?.deadline ??
      widget.controller.now.add(const Duration(days: 1));
  late DateTime _cycleStart = dayOnly(
    widget.task?.start ?? widget.controller.now,
  );
  late RepeatFrequency _frequency =
      widget.task?.todoRepeat?.frequency ?? RepeatFrequency.daily;
  late HolidayPolicy _policy =
      widget.task?.todoRepeat?.holidayPolicy ?? HolidayPolicy.ignore;
  late WeekendHolidayPriority _priority =
      widget.task?.todoRepeat?.weekendHolidayPriority ??
      WeekendHolidayPriority.holiday;
  late int _color =
      widget.repeatNode?.item.color ?? widget.task?.color ?? 0xffe4ead9;
  late int _completedColor =
      widget.repeatNode?.item.completedColor ??
      widget.task?.completedColor ??
      0xffe2e3df;
  late List<int> _reminders =
      (widget.repeatNode?.item.reminderOffsets ??
              widget.task?.reminderOffsets ??
              const <int>[])
          .toList();
  late bool _sound =
      widget.repeatNode?.item.reminderSound ??
      widget.task?.reminderSound ??
      true;
  late final List<TodoRepeatNode> _nodes = [...?widget.task?.todoRepeat?.nodes];
  bool _saving = false;
  String? _error;
  bool get _instance => widget.task?.seriesId != null;
  int get _days => switch (_frequency) {
    RepeatFrequency.daily => 1,
    RepeatFrequency.weekly => 7,
    RepeatFrequency.monthly => 31,
    RepeatFrequency.interval => int.tryParse(_interval.text) ?? 1,
  };
  int get _nodePeriodDays {
    if (_frequency != RepeatFrequency.monthly) return _days;
    final root = ScheduleEvent(
      id: 'draft',
      title: '',
      start: _cycleStart,
      end: _cycleStart,
      updatedAt: widget.controller.now,
      todoRepeat: TodoRepeatRule(frequency: _frequency, nodes: _nodes),
    );
    final cycle = todoCycleAt(
      root,
      widget.controller.now.isBefore(_cycleStart)
          ? _cycleStart
          : widget.controller.now,
    )!;
    return DateTime.utc(cycle.end.year, cycle.end.month, cycle.end.day)
        .difference(
          DateTime.utc(cycle.start.year, cycle.start.month, cycle.start.day),
        )
        .inDays;
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(999999)}';
  @override
  void dispose() {
    for (final c in [_title, _notes, _interval, _day]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRepeat(bool value) {
    setState(() {
      if (value && _nodes.isEmpty) {
        _nodes.add(
          TodoRepeatNode(
            item: RecurrenceNode(
              id: _id('item'),
              title: '',
              notes: '',
              minute: 0,
              durationMinutes: 0,
              color: _color,
              completedColor: _completedColor,
              reminderOffsets: _reminders,
              reminderSound: _sound,
            ),
          ),
        );
      }
      if (!value && _title.text.trim().isEmpty && _nodes.isNotEmpty) {
        _title.text = _nodes.first.item.title;
      }
      _repeat = value;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (widget.nodeMode) {
      final item = RecurrenceNode(
        id: widget.repeatNode?.item.id ?? _id('item'),
        title: _title.text.trim(),
        notes: _notes.text.trim(),
        minute: 0,
        durationMinutes: 0,
        color: _color,
        completedColor: _completedColor,
        reminderOffsets: List.of(_reminders),
        reminderSound: _sound,
      );
      Navigator.pop(
        context,
        TodoRepeatNode(
          item: item,
          removeAfterCycle: _removeAfterCycle,
          deadlineMinutes: _dated
              ? (int.parse(_day.text) - 1) * 1440 +
                    _nodeTime.hour * 60 +
                    _nodeTime.minute
              : null,
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_repeat &&
          _nodes.any(
            (n) =>
                n.deadlineMinutes != null &&
                n.deadlineMinutes! >= _nodePeriodDays * 1440,
          )) {
        throw FormatException('待办截止时间不能超出当前循环周期（$_nodePeriodDays天）');
      }
      final now = DateTime.now().toUtc(), old = widget.task;
      final anchor = _repeat
          ? _cycleStart
          : (_dated ? _deadline : old?.start ?? widget.controller.now);
      final task = ScheduleEvent(
        id: old?.id ?? _id('todo'),
        isTodo: true,
        hasDeadline: !_repeat && _dated,
        taskCreatedAt: old?.taskCreatedAt ?? now,
        todoOrder: old?.todoOrder ?? widget.controller.nextTodoOrder,
        title: _title.text.trim(),
        notes: _notes.text.trim(),
        start: anchor,
        end: anchor,
        updatedAt: now,
        color: _color,
        completedColor: _completedColor,
        completed: old?.completed ?? false,
        revision: (old?.revision ?? 0) + 1,
        reminderOffsets: !_repeat && _dated ? _reminders : const [],
        reminderSound: _sound,
        seriesId: old?.seriesId,
        occurrenceKey: old?.occurrenceKey,
        nodeId: old?.nodeId,
        todoCycleStart: old?.todoCycleStart,
        todoRepeat: _repeat
            ? TodoRepeatRule(
                frequency: _frequency,
                intervalDays: int.tryParse(_interval.text) ?? 1,
                holidayPolicy: _policy,
                weekendHolidayPriority: _priority,
                nodes: List.of(_nodes),
              )
            : null,
      );
      await widget.controller.saveEvent(task);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, old == null ? '待办已创建' : '待办已保存');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = e is FormatException ? e.message.toString() : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({bool cycle = false}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: cycle ? _cycleStart : _deadline,
      firstDate: DateTime(1901),
      lastDate: DateTime(2099, 12, 31),
    );
    if (date != null && mounted) {
      setState(() {
        if (cycle) {
          _cycleStart = date;
        } else {
          _deadline = DateTime(
            date.year,
            date.month,
            date.day,
            _deadline.hour,
            _deadline.minute,
          );
        }
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: widget.nodeMode
          ? _nodeTime
          : TimeOfDay.fromDateTime(_deadline),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null && mounted) {
      setState(() {
        if (widget.nodeMode) {
          _nodeTime = time;
          return;
        }
        _deadline = DateTime(
          _deadline.year,
          _deadline.month,
          _deadline.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Widget _colorButton(bool done) => OutlinedButton(
    onPressed: _saving
        ? null
        : () async {
            final value = await pickEventColor(
              context,
              title: done ? '已完成颜色' : '未完成颜色',
              initial: done ? _completedColor : _color,
            );
            if (value != null && mounted) {
              setState(() {
                if (done) {
                  _completedColor = value;
                } else {
                  _color = value;
                }
              });
            }
          },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(done ? '已完成颜色' : '未完成颜色'),
        const SizedBox(width: 8),
        ColorPreview(color: done ? _completedColor : _color, size: 16),
      ],
    ),
  );
  Widget _reminderButton() => OutlinedButton.icon(
    onPressed: _saving
        ? null
        : () async {
            final result = await editReminders(
              context,
              _reminders,
              _sound,
              deadline: true,
            );
            if (result != null && mounted) {
              setState(() {
                _reminders = result.offsets;
                _sound = result.sound;
              });
            }
          },
    icon: const Icon(Icons.notifications_none, size: 18),
    label: Text(_reminders.isEmpty ? '截止提醒' : '提醒 ${_reminders.length} 次'),
  );
  Future<void> _editNode(TodoRepeatNode? node) async {
    if (_days < 1 || _days > 365) {
      setState(() => _error = '周期需为1—365天');
      return;
    }
    final last = _nodes.lastOrNull;
    final seed =
        node ??
        TodoRepeatNode(
          item:
              (last?.item ??
                      RecurrenceNode(
                        id: 'seed',
                        minute: 0,
                        durationMinutes: 0,
                        color: _color,
                        completedColor: _completedColor,
                        reminderOffsets: _reminders,
                        reminderSound: _sound,
                      ))
                  .copyWith(id: _id('item'), title: '', notes: ''),
          deadlineMinutes: last?.deadlineMinutes,
          removeAfterCycle: last?.removeAfterCycle ?? true,
        );
    final result = await showAppDialog<TodoRepeatNode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TodoEditor(
        controller: widget.controller,
        nodeMode: true,
        repeatNode: seed,
        groupTitle: _title.text.trim(),
        periodDays: _nodePeriodDays,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final index = _nodes.indexWhere((n) => n.item.id == result.item.id);
        if (index < 0) {
          _nodes.add(result);
        } else {
          _nodes[index] = result;
        }
        _error = null;
      });
    }
  }

  Widget _number(
    TextEditingController c,
    String label,
    int max, {
    int min = 0,
  }) => SizedBox(
    width: 92,
    child: TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (s) {
        final n = int.tryParse(s ?? '');
        return n == null || n < min || n > max ? '$min—$max' : null;
      },
    ),
  );
  Widget _singleFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.nodeMode)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('周期结束后自动移除'),
          subtitle: const Text('关闭后保留旧周期待办，下一周期仍会生成新待办'),
          value: _removeAfterCycle,
          onChanged: _saving
              ? null
              : (value) => setState(() => _removeAfterCycle = value),
        ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(widget.nodeMode ? '自定义周期内截止时间' : '设置截止时间'),
        subtitle: widget.nodeMode && !_dated
            ? const Text('默认在每个循环周期结束时截止')
            : null,
        value: _dated,
        onChanged: _saving ? null : (v) => setState(() => _dated = v!),
      ),
      if (_dated && widget.nodeMode)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 158,
              child: TextFormField(
                key: _dayField,
                controller: _day,
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: '周期第几天',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  suffixIcon: PopupMenuButton<int>(
                    tooltip: '选择天数',
                    initialValue: int.tryParse(_day.text),
                    onSelected: (day) {
                      _day.text = '$day';
                      _dayField.currentState?.validate();
                    },
                    itemBuilder: (_) => [
                      for (var day = 1; day <= widget.periodDays; day++)
                        PopupMenuItem(value: day, child: Text('第 $day 天')),
                    ],
                    icon: const Icon(Icons.arrow_drop_down),
                  ),
                ),
                validator: (value) {
                  final day = int.tryParse(value ?? '');
                  return day == null || day < 1 || day > widget.periodDays
                      ? '输入1—${widget.periodDays}天'
                      : null;
                },
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('node-deadline-time'),
              style: OutlinedButton.styleFrom(
                fixedSize: const Size.fromHeight(48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _saving ? null : _pickTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(
                '截止 ${pad2(_nodeTime.hour)}:${pad2(_nodeTime.minute)}',
              ),
            ),
          ],
        ),
      if (_dated && !widget.nodeMode)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _saving ? null : () => _pickDate(),
              child: Text(dateKey(_deadline)),
            ),
            OutlinedButton(
              onPressed: _saving ? null : _pickTime,
              child: Text(clockText(_deadline)),
            ),
          ],
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _colorButton(false),
          _colorButton(true),
          if (_dated || widget.nodeMode) _reminderButton(),
        ],
      ),
    ],
  );
  Widget _repeatFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 156,
            child: DropdownButtonFormField<RepeatFrequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: '循环周期'),
              items: [
                for (final f in RepeatFrequency.values)
                  DropdownMenuItem(
                    value: f,
                    child: Text(switch (f) {
                      RepeatFrequency.daily => '每日',
                      RepeatFrequency.weekly => '每周',
                      RepeatFrequency.monthly => '每月',
                      RepeatFrequency.interval => '自定义天数',
                    }),
                  ),
              ],
              onChanged: (f) => setState(() => _frequency = f!),
            ),
          ),
          if (_frequency == RepeatFrequency.interval)
            _number(_interval, '天数', 365, min: 1),
          OutlinedButton(
            onPressed: () => _pickDate(cycle: true),
            child: Text('起始 ${dateKey(_cycleStart)}'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      HolidayPolicyField(
        policy: _policy,
        priority: _priority,
        onChanged: (p, w) => setState(() {
          _policy = p;
          _priority = w;
        }),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Expanded(
            child: Text('组内待办', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: _nodes.length >= 96 ? null : () => _editNode(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加待办'),
          ),
        ],
      ),
      SizedBox(
        height: min(260, _nodes.length * 76.0),
        child: ReorderableListView.builder(
          primary: false,
          physics: const ClampingScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _nodes.length,
          onReorderItem: (old, next) => setState(() {
            _nodes.insert(next, _nodes.removeAt(old));
          }),
          itemBuilder: (context, i) {
            final node = _nodes[i], offset = node.deadlineMinutes;
            return ReorderableDelayedDragStartListener(
              key: ValueKey(node.item.id),
              index: i,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.drag_indicator,
                  color: context.appColors.input,
                  size: 20,
                ),
                title: Text(
                  node.item.title.isEmpty
                      ? (_title.text.trim().isEmpty
                            ? '待办 ${i + 1}（待填写标题）'
                            : _title.text.trim())
                      : node.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  offset == null
                      ? '周期结束时截止'
                      : 'Day${offset ~/ 1440 + 1} ${pad2(offset % 1440 ~/ 60)}:${pad2(offset % 60)} 截止',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '编辑组内待办',
                      onPressed: () => _editNode(node),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                    IconButton(
                      tooltip: '移除组内待办',
                      onPressed: () => setState(() => _nodes.removeAt(i)),
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
                onTap: () => _editNode(node),
              ),
            );
          },
        ),
      ),
      if (_frequency == RepeatFrequency.monthly)
        const Text(
          '超过当月周期长度的截止时间按周期结束计算。',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.nodeMode
          ? '组内待办'
          : widget.task == null
          ? '新增待办'
          : '编辑待办',
    ),
    content: SizedBox(
      width: _repeat ? 600 : 500,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.nodeMode && !_instance) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('不重复')),
                    ButtonSegment(value: true, label: Text('重复')),
                  ],
                  selected: {_repeat},
                  showSelectedIcon: false,
                  onSelectionChanged: _saving
                      ? null
                      : (s) => _setRepeat(s.single),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: _repeat
                      ? '组标题（可留空）'
                      : widget.nodeMode
                      ? '标题'
                      : '名称',
                ),
                maxLength: widget.task?.nodeId == null ? 120 : 241,
                validator: (v) {
                  if (_repeat) {
                    return hasValidGroupTitle(
                          v ?? '',
                          _nodes.map((n) => n.item).toList(),
                        )
                        ? null
                        : '组标题为空时，每项待办都需填写标题';
                  }
                  return (v ?? '').trim().isEmpty &&
                          (!widget.nodeMode || widget.groupTitle.isEmpty)
                      ? '请填写名称或组标题'
                      : null;
                },
              ),
              if (_repeat) ...[_repeatFields(), const SizedBox(height: 10)],
              TextFormField(
                controller: _notes,
                decoration: InputDecoration(
                  labelText: _repeat ? '组备注（可留空）' : '备注',
                ),
                minLines: 2,
                maxLines: 5,
                maxLength: widget.task?.nodeId == null ? 4000 : 8001,
              ),
              if (!_repeat) _singleFields(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );
}
