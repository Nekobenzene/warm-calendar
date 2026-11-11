import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'color_picker.dart';
import 'holiday_policy_field.dart';
import 'reminder_editor.dart';
import 'motion.dart';
import 'theme.dart';
import 'automation_fields.dart';
import '../app_controller.dart';
import 'item_context_menu.dart';

Future<RecurrenceNode?> editCycleNode(
  BuildContext context,
  RecurrenceNode initial,
  int days, {
  bool monthly = false,
  bool weekLabels = false,
  bool fixedStartDay = false,
  AppController? controller,
  ScheduleEvent? sourceEvent,
}) => showAppDialog<RecurrenceNode>(
  context: context,
  barrierDismissible: false,
  builder: (_) => NodeEditor(
    initial: initial,
    days: days,
    monthly: monthly,
    weekLabels: weekLabels,
    fixedStartDay: fixedStartDay,
    controller: controller,
    sourceEvent: sourceEvent,
  ),
);

class NodeEditor extends StatefulWidget {
  final AppController? controller;
  final ScheduleEvent? sourceEvent;
  final RecurrenceNode initial;
  final int days;
  final bool monthly, weekLabels, fixedStartDay;
  const NodeEditor({
    super.key,
    required this.initial,
    required this.days,
    this.monthly = false,
    this.weekLabels = false,
    this.fixedStartDay = false,
    this.controller,
    this.sourceEvent,
  });
  @override
  State<NodeEditor> createState() => _NodeEditorState();
}

class _NodeEditorState extends State<NodeEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial.title),
      _notes = TextEditingController(text: widget.initial.notes),
      _start = TextEditingController(
        text:
            '${pad2(widget.initial.minute ~/ 60)}:${pad2(widget.initial.minute % 60)}',
      ),
      _end = TextEditingController(
        text:
            '${pad2((widget.initial.minute + widget.initial.durationMinutes) % 1440 ~/ 60)}:${pad2((widget.initial.minute + widget.initial.durationMinutes) % 60)}',
      );
  late int _day = widget.initial.dayOffset,
      _endDay =
          widget.initial.dayOffset +
          (widget.initial.minute + widget.initial.durationMinutes) ~/ 1440 -
          (widget.initial.allDay ? 1 : 0);
  late bool _point = widget.initial.isPoint,
      _allDay = widget.initial.allDay,
      _sound = widget.initial.reminderSound;
  late List<int> _reminders = widget.initial.reminderOffsets.toList();
  late int _color = widget.initial.color, _done = widget.initial.completedColor;
  late HolidayPolicy _holiday = widget.initial.holidayPolicy;
  late ItemAutomation _automation = widget.initial.automation;
  late WeekendHolidayPriority _priority = widget.initial.weekendHolidayPriority;
  String? _error;
  String? _pasteId;
  void _paste(ScheduleEvent draft) {
    setState(() {
      if (_pasteId != null) widget.controller?.discardPaste(_pasteId!);
      _pasteId = draft.id;
      _title.text = draft.title;
      _notes.text = draft.notes;
      _start.text = clockText(draft.start);
      _end.text = clockText(draft.end);
      _allDay = draft.allDay;
      _point = draft.isPoint;
      _endDay =
          _day +
          draft.end.difference(dayOnly(draft.start)).inMinutes ~/ 1440 -
          (_allDay ? 1 : 0);
      _color = draft.color;
      _done = draft.completedColor;
      _reminders = draft.reminderOffsets.toList();
      _sound = draft.reminderSound;
      _automation = draft.automation.copyWith(deleteExpired: false);
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _notes, _start, _end]) {
      c.dispose();
    }
    super.dispose();
  }

  int _minute(String value) {
    final t = value.split(':');
    return int.parse(t[0]) * 60 + int.parse(t[1]);
  }

  String _dayLabel(int i) => widget.weekLabels && i < 7
      ? '周${const ['一', '二', '三', '四', '五', '六', '日'][i]}'
      : 'Day${i + 1}';
  Widget _dateSelect(bool end) => DropdownButtonFormField<int>(
    key: ValueKey('node-${end ? 'end' : 'start'}-${end ? _endDay : _day}'),
    initialValue: end ? _endDay : _day,
    isExpanded: true,
    decoration: InputDecoration(labelText: end ? '结束日' : '所属日'),
    items: [
      for (
        var i = 0;
        i <
            (end
                ? widget.days * 2 + 1
                : widget.fixedStartDay
                ? 1
                : widget.days);
        i++
      )
        DropdownMenuItem(value: i, child: Text(_dayLabel(i))),
    ],
    onChanged: (v) {
      if (v != null) {
        setState(() {
          if (end) {
            _endDay = v;
          } else {
            _endDay += v - _day;
            _day = v;
          }
        });
      }
    },
  );
  Widget _time(String label, TextEditingController field) => TextFormField(
    controller: field,
    readOnly: true,
    onTap: () async {
      final value = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: _minute(field.text) ~/ 60,
          minute: _minute(field.text) % 60,
        ),
        initialEntryMode: TimePickerEntryMode.dial,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (value != null && mounted) {
        setState(
          () => field.text = '${pad2(value.hour)}:${pad2(value.minute)}',
        );
      }
    },
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.schedule, size: 18),
    ),
    validator: (v) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
        ? null
        : '使用HH:mm',
  );
  Future<void> _colorPick(bool done) async {
    final value = await pickEventColor(
      context,
      title: done ? '已完成颜色' : '未完成颜色',
      initial: done ? _done : _color,
    );
    if (value != null && mounted) {
      setState(() {
        if (done) {
          _done = value;
        } else {
          _color = value;
        }
      });
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final minute = _allDay ? 0 : _minute(_start.text);
    final duration = _point && !_allDay
        ? 0
        : (_endDay - _day) * 1440 +
              (_allDay ? 1440 : _minute(_end.text)) -
              minute;
    final node = RecurrenceNode(
      pasteDraftId: _pasteId ?? widget.initial.pasteDraftId,
      automation: _automation,
      id: widget.initial.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      dayOffset: _day,
      minute: minute,
      durationMinutes: duration,
      allDay: _allDay,
      reminderOffsets: List.unmodifiable(_reminders),
      reminderSound: _sound,
      color: _color,
      completedColor: _done,
      holidayPolicy: _holiday,
      weekendHolidayPriority: _priority,
      legacyMinute: widget.initial.legacyMinute,
    );
    try {
      node.validate(widget.days, monthly: widget.monthly);
      Navigator.pop(context, node);
    } on FormatException catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => widget.controller == null
      ? _dialog(context)
      : ItemContextMenu(
          controller: widget.controller!,
          event: widget.sourceEvent,
          isTodo: false,
          onPaste: _paste,
          child: _dialog(context),
        );
  Widget _dialog(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('编辑节点', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
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
                          labelText: '节点标题（可留空）',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('全天'),
                            selected: _allDay,
                            onSelected: (v) => setState(() {
                              _allDay = v;
                              if (v) _point = false;
                            }),
                          ),
                          if (!_allDay)
                            FilterChip(
                              label: const Text('仅时间点'),
                              selected: _point,
                              onSelected: (v) => setState(() => _point = v),
                            ),
                          OutlinedButton(
                            onPressed: () => _colorPick(false),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('未完成颜色'),
                                const SizedBox(width: 6),
                                ColorPreview(color: _color, size: 16),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => _colorPick(true),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('已完成颜色'),
                                const SizedBox(width: 6),
                                ColorPreview(color: _done, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: widget.fixedStartDay
                                ? InputDecorator(
                                    key: const ValueKey('node-fixed-start-day'),
                                    decoration: const InputDecoration(
                                      labelText: '所属日',
                                    ),
                                    child: Text(
                                      _dayLabel(_day),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  )
                                : _dateSelect(false),
                          ),
                          if (!_allDay) ...[
                            const SizedBox(width: 10),
                            Expanded(child: _time('开始时间', _start)),
                          ],
                        ],
                      ),
                      if (!_point || _allDay) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _dateSelect(true)),
                            if (!_allDay) ...[
                              const SizedBox(width: 10),
                              Expanded(child: _time('结束时间', _end)),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final v = await editReminders(
                            context,
                            _reminders,
                            _sound,
                          );
                          if (v != null && mounted) {
                            setState(() {
                              _reminders = v.offsets;
                              _sound = v.sound;
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.notifications_outlined,
                          size: 18,
                        ),
                        label: Text(
                          '提醒 · ${_reminders.length}条${_sound ? ' · 声音' : ' · 静音'}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      HolidayPolicyField(
                        policy: _holiday,
                        priority: _priority,
                        onChanged: (p, w) => setState(() {
                          _holiday = p;
                          _priority = w;
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notes,
                        minLines: 2,
                        maxLines: 3,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          labelText: '节点备注',
                          counterText: '',
                        ),
                      ),
                      AutomationFields(
                        value: _automation,
                        onChanged: (v) => setState(() => _automation = v),
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
                FilledButton(onPressed: _save, child: const Text('保存节点')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
