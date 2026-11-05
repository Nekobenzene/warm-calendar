import 'dart:math';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'color_picker.dart';
import 'repeat_editor.dart';
import 'reminder_editor.dart';
import '../domain/reminders.dart';
import 'cycle_editor.dart';
import 'holiday_policy_field.dart';

class EventEditor extends StatefulWidget {
  final AppController controller;
  final ScheduleEvent? event;
  final DateTime? initialDate;
  final bool exactTime;
  const EventEditor({
    super.key,
    required this.controller,
    this.event,
    this.initialDate,
    this.exactTime = false,
  });
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title,
      _notes,
      _startDate,
      _endDate,
      _startTime,
      _endTime;
  late bool _allDay, _completed, _point;
  late int _color, _doneColor, _ruleMinute;
  late List<int> _reminders;
  late bool _reminderSound;
  RecurrenceRule? _rule;
  late int _mode;
  ScheduleEvent? _cycleDraft;
  bool _saving = false;
  String? _error;
  Duration get _shift =>
      Duration(minutes: widget.event?.recurrence?.shiftMinutes ?? 0);
  @override
  void initState() {
    super.initState();
    final now = widget.controller.now,
        requested = widget.initialDate ?? widget.controller.now;
    final initial = widget.exactTime
        ? requested
        : sameDay(now, requested)
        ? DateTime(
            now.year,
            now.month,
            now.day,
            now.hour,
            (now.minute ~/ 30 + 1) * 30,
          )
        : DateTime(requested.year, requested.month, requested.day, 9);
    final e = widget.event,
        start = widget.event?.start.subtract(_shift) ?? initial;
    final end = e == null
        ? start.add(const Duration(hours: 1))
        : e.end
              .subtract(_shift)
              .subtract(e.allDay ? const Duration(days: 1) : Duration.zero);
    _title = TextEditingController(text: e?.title ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _startDate = TextEditingController(text: dateKey(start));
    _endDate = TextEditingController(text: dateKey(end));
    _startTime = TextEditingController(text: clockText(start));
    _endTime = TextEditingController(text: clockText(end));
    _allDay = e?.allDay ?? false;
    _point = e?.isPoint ?? false;
    _completed = e?.completed ?? false;
    _color = e?.color ?? 0xFFE4EAD9;
    _doneColor = e?.completedColor ?? 0xFFE2E3DF;
    _reminders = e == null ? [10] : e.reminderOffsets.toList();
    _reminderSound = e?.reminderSound ?? true;
    _rule = e?.recurrence;
    _mode = _rule == null
        ? 0
        : _rule!.kind == RepeatKind.cycle
        ? 2
        : 1;
    if (_mode == 2) _cycleDraft = e;
    if (_rule?.nodes.isNotEmpty == true && _mode == 1) {
      _applyFirstNode(_rule!.nodes.first, start);
    }
    _ruleMinute = start.hour * 60 + start.minute;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _notes,
      _startDate,
      _endDate,
      _startTime,
      _endTime,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _parseDate(String text) {
    final d = DateTime.tryParse(text);
    return d != null && dateKey(d) == text && d.year >= 1901 && d.year <= 2099
        ? d
        : null;
  }

  DateTime _combine(TextEditingController date, TextEditingController time) {
    final d = _parseDate(date.text) ?? dayOnly(widget.controller.now);
    if (_allDay) return d;
    final parts = time.text.split(':');
    return DateTime(
      d.year,
      d.month,
      d.day,
      int.tryParse(parts.first) ?? 9,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  Future<void> _pickDate(TextEditingController field) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _parseDate(field.text) ?? widget.controller.now,
      firstDate: DateTime(1901),
      lastDate: DateTime(2099, 12, 31),
    );
    if (date != null) setState(() => field.text = dateKey(date));
  }

  Future<void> _pickTime(TextEditingController field) async {
    final t = field.text.split(':');
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (int.tryParse(t.first) ?? 9).clamp(0, 23),
        minute: (t.length > 1 ? int.tryParse(t[1]) ?? 0 : 0).clamp(0, 59),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null) {
      setState(() => field.text = '${pad2(time.hour)}:${pad2(time.minute)}');
    }
  }

  Widget _dateField(String label, TextEditingController c) => TextFormField(
    controller: c,
    validator: (v) =>
        _parseDate(v ?? '') == null ? '使用YYYY-MM-DD（1901—2099）' : null,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: '选择$label',
        onPressed: () => _pickDate(c),
        icon: const Icon(Icons.calendar_today_outlined, size: 17),
      ),
    ),
  );
  Widget _timeField(String label, TextEditingController c) => TextFormField(
    controller: c,
    validator: (v) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
        ? null
        : '使用24小时HH:mm',
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: '选择$label',
        onPressed: () => _pickTime(c),
        icon: const Icon(Icons.schedule_outlined, size: 18),
      ),
    ),
  );
  Future<void> _chooseColor(bool done) async {
    final color = await pickEventColor(
      context,
      title: done ? '已完成颜色' : '未完成颜色',
      initial: done ? _doneColor : _color,
    );
    if (color != null && mounted) {
      setState(() {
        if (done) {
          _doneColor = color;
        } else {
          _color = color;
        }
      });
    }
  }

  Widget _colorButton(bool done) => OutlinedButton(
    onPressed: _saving ? null : () => _chooseColor(done),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 36),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            done ? '已完成颜色' : '未完成颜色',
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        ColorPreview(color: done ? _doneColor : _color, size: 18),
      ],
    ),
  );
  RecurrenceRule _draftRule(RepeatFrequency frequency, DateTime start) {
    final old = _rule;
    final minute = start.hour * 60 + start.minute;
    return RecurrenceRule(
      frequency: frequency,
      until: old?.until ?? DateTime(start.year, start.month + 3, start.day),
      intervalDays: old?.intervalDays ?? 2,
      weekdays: old?.weekdays ?? [start.weekday],
      monthDays: old?.monthDays ?? [start.day],
      minutes: _allDay
          ? [0]
          : old == null
          ? [minute]
          : [for (final m in old.minutes) m == _ruleMinute ? minute : m],
      holidayPolicy: old?.holidayPolicy ?? HolidayPolicy.ignore,
      shiftMinutes: _shift.inMinutes,
      cycleCount: old?.cycleCount,
      weekendHolidayPriority:
          old?.weekendHolidayPriority ?? WeekendHolidayPriority.holiday,
      nodes: old == null || old.nodes.isEmpty
          ? const []
          : [
              for (var i = 0; i < old.nodes.length; i++)
                i != 0
                    ? old.nodes[i]
                    : RecurrenceNode(
                        id: old.nodes[i].id,
                        title: old.nodes[i].title,
                        notes: old.nodes[i].notes,
                        minute: _allDay ? 0 : minute,
                        durationMinutes: (_point && !_allDay)
                            ? 0
                            : _combine(_endDate, _endTime)
                                  .add(
                                    _allDay
                                        ? const Duration(days: 1)
                                        : Duration.zero,
                                  )
                                  .difference(start)
                                  .inMinutes,
                        allDay: _allDay,
                        color: _color,
                        completedColor: _doneColor,
                        reminderOffsets: _reminders,
                        reminderSound: _reminderSound,
                        holidayPolicy: old.nodes[i].holidayPolicy,
                        weekendHolidayPriority:
                            old.nodes[i].weekendHolidayPriority,
                        legacyMinute: old.nodes[i].legacyMinute,
                      ),
            ],
    );
  }

  Future<void> _configureRepeat(RepeatFrequency? frequency) async {
    if (frequency == null) {
      setState(() {
        _rule = null;
        _mode = 0;
      });
      return;
    }
    final start = _combine(_startDate, _startTime);
    var end = _point && !_allDay
        ? start
        : _combine(
            _endDate,
            _endTime,
          ).add(_allDay ? const Duration(days: 1) : Duration.zero);
    if (end.isBefore(start) || (_allDay && end == start)) {
      end = start.add(
        _allDay ? const Duration(days: 1) : const Duration(hours: 1),
      );
    }
    final result = await editRepeatRule(
      context,
      initial: _draftRule(frequency, start),
      calendar: widget.controller.calendar,
      start: start,
      end: end,
      allDay: _allDay,
      template: ScheduleEvent(
        id: 'draft',
        title: _title.text.trim(),
        start: start,
        end: end,
        updatedAt: widget.controller.now,
        allDay: _allDay,
        color: _color,
        completedColor: _doneColor,
        reminderOffsets: _reminders,
        reminderSound: _reminderSound,
      ),
    );
    if (mounted) {
      setState(() {
        if (result != null) {
          _rule = result;
          _mode = 1;
          if (result.nodes.isNotEmpty) {
            _applyFirstNode(result.nodes.first, start);
          }
          _ruleMinute =
              result.nodes.firstOrNull?.minute ??
              start.hour * 60 + start.minute;
        }
      });
    }
  }

  void _applyFirstNode(RecurrenceNode node, DateTime day) {
    final start = DateTime(
      day.year,
      day.month,
      day.day + node.dayOffset,
      0,
      node.minute,
    );
    final end = start
        .add(Duration(minutes: node.durationMinutes))
        .subtract(node.allDay ? const Duration(days: 1) : Duration.zero);
    _startDate.text = dateKey(start);
    _endDate.text = dateKey(end);
    _startTime.text = clockText(start);
    _endTime.text = clockText(end);
    _point = node.isPoint;
    _allDay = node.allDay;
    _color = node.color;
    _doneColor = node.completedColor;
    _reminders = node.reminderOffsets.toList();
    _reminderSound = node.reminderSound;
  }

  void _setMode(int mode, [ScheduleEvent? cycle]) {
    if (mode == _mode) return;
    setState(() {
      if (cycle != null) {
        _cycleDraft = cycle;
        _title.text = cycle.title;
        _notes.text = cycle.notes;
        if (cycle.recurrence!.nodes.isNotEmpty) {
          _applyFirstNode(
            cycle.recurrence!.nodes.first,
            cycle.start.subtract(_shift),
          );
        }
        _rule = null;
      }
      if (mode == 2) {
        final start = _combine(_startDate, _startTime);
        final previous = _cycleDraft?.recurrence;
        final formRule = _draftRule(
          _rule?.frequency ?? RepeatFrequency.daily,
          start,
        );
        final draftRule = previous == null
            ? _rule
            : previous.copyWith(
                nodes: [
                  if (previous.nodes.isNotEmpty)
                    RecurrenceNode(
                      id: previous.nodes.first.id,
                      title: previous.nodes.first.title,
                      notes: previous.nodes.first.notes,
                      dayOffset: previous.nodes.first.dayOffset,
                      minute: _allDay ? 0 : start.hour * 60 + start.minute,
                      durationMinutes: (_point && !_allDay)
                          ? 0
                          : _combine(_endDate, _endTime)
                                .add(
                                  _allDay
                                      ? const Duration(days: 1)
                                      : Duration.zero,
                                )
                                .difference(start)
                                .inMinutes,
                      allDay: _allDay,
                      color: _color,
                      completedColor: _doneColor,
                      reminderOffsets: _reminders,
                      reminderSound: _reminderSound,
                      holidayPolicy: previous.nodes.first.holidayPolicy,
                      weekendHolidayPriority:
                          previous.nodes.first.weekendHolidayPriority,
                      legacyMinute: previous.nodes.first.legacyMinute,
                    ),
                  ...previous.nodes.skip(1),
                ],
              );
        _cycleDraft = ScheduleEvent(
          id:
              widget.event?.id ??
              '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(99999)}',
          title: _title.text,
          notes: _notes.text,
          start: start.add(_shift),
          end:
              (_point && !_allDay
                      ? start
                      : _combine(_endDate, _endTime).add(
                          _allDay ? const Duration(days: 1) : Duration.zero,
                        ))
                  .add(_shift),
          allDay: _allDay,
          updatedAt: DateTime.now().toUtc(),
          recurrence: draftRule ?? (_mode == 1 ? formRule : null),
          color: _color,
          completedColor: _doneColor,
          reminderOffsets: _reminders,
          reminderSound: _reminderSound,
          revision: widget.event?.revision ?? 0,
        );
      } else if (mode == 0) {
        _rule = null;
      } else {
        _rule ??= _draftRule(
          RepeatFrequency.daily,
          _combine(_startDate, _startTime),
        );
      }
      _mode = mode;
    });
  }

  static const _repeatLabels = {
    RepeatFrequency.daily: '每日',
    RepeatFrequency.weekly: '每周',
    RepeatFrequency.monthly: '每月',
    RepeatFrequency.interval: '每隔几日',
  };
  String get _ruleSummary =>
      '${_rule!.nodes.isEmpty ? _rule!.minutes.length : _rule!.nodes.length}个节点 · ${_rule!.cycleCount == null ? '至${dateKey(_rule!.until)}' : '${_rule!.cycleCount}轮'}${_shift == Duration.zero ? '' : ' · 整体偏移${_shift.inMinutes}分钟'}';
  ButtonStyle get _optionStyle => OutlinedButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    alignment: Alignment.centerLeft,
  );
  Widget _repeatControl() => _mode == 0
      ? const SizedBox.shrink()
      : MenuAnchor(
          menuChildren: [
            if (_rule != null)
              MenuItemButton(
                onPressed: () => _configureRepeat(_rule!.frequency),
                child: const Text('编辑重复规则'),
              ),
            MenuItemButton(
              onPressed: () => _configureRepeat(null),
              child: const Text('不重复'),
            ),
            for (final entry in _repeatLabels.entries)
              MenuItemButton(
                onPressed: () => _configureRepeat(entry.key),
                child: Text(entry.value),
              ),
          ],
          builder: (context, menu, child) => OutlinedButton.icon(
            key: const ValueKey('event-repeat'),
            style: _optionStyle,
            onPressed: _saving
                ? null
                : () => menu.isOpen ? menu.close() : menu.open(),
            icon: const Icon(Icons.repeat, size: 17),
            label: Text('重复 · ${_repeatLabels[_rule?.frequency] ?? '不重复'}'),
          ),
        );
  Widget _reminderControl() => OutlinedButton.icon(
    key: const ValueKey('event-reminders'),
    style: _optionStyle,
    onPressed: _saving
        ? null
        : () async {
            final result = await editReminders(
              context,
              _reminders,
              _reminderSound,
            );
            if (result != null && mounted) {
              setState(() {
                _reminders = result.offsets;
                _reminderSound = result.sound;
              });
            }
          },
    icon: const Icon(Icons.notifications_outlined, size: 17),
    label: Text(
      _reminders.isEmpty
          ? '提醒 · 无'
          : _reminders.length == 1
          ? '提醒 · ${reminderLabel(_reminders.single)}'
          : '提醒 · ${_reminders.length}条',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  Widget _stackOrRow(List<Widget> fields, {double cutoff = 520}) =>
      LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              cutoff) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  fields[i],
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: fields[i]),
              ],
            ],
          );
        },
      );
  Widget _dates() => LayoutBuilder(
    builder: (context, box) {
      final repeat = widget.event?.seriesId == null
          ? _repeatControl()
          : const Text('仅修改本次', style: TextStyle(color: AppColors.muted));
      Widget dateTime(bool start) {
        final date = _dateField(
          start ? '开始日期' : '结束日期',
          start ? _startDate : _endDate,
        );
        if (_allDay) return date;
        final time = _timeField(
          start ? '开始时间' : '结束时间',
          start ? _startTime : _endTime,
        );
        return LayoutBuilder(
          builder: (context, inner) {
            if (inner.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
                290) {
              return _stackOrRow([date, time], cutoff: 290);
            }
            return Row(
              children: [
                Expanded(flex: 3, child: date),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: time),
              ],
            );
          },
        );
      }

      Widget row(Widget fields, Widget button) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (box.maxWidth / scale < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fields,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: button),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: fields),
            const SizedBox(width: 16),
            SizedBox(width: 184 * scale, child: button),
          ],
        );
      }

      if (MediaQuery.sizeOf(context).width < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dateTime(true),
            if (!_point || _allDay) ...[
              const SizedBox(height: 12),
              dateTime(false),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [repeat, _reminderControl()],
            ),
            if (_rule != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _ruleSummary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(dateTime(true), repeat),
          if (!_point || _allDay) ...[
            const SizedBox(height: 12),
            row(dateTime(false), _reminderControl()),
          ] else ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: _reminderControl()),
          ],
          if (_rule != null) ...[
            const SizedBox(height: 8),
            Text(_ruleSummary, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
    },
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final baseStart = _combine(_startDate, _startTime);
    final start = baseStart.add(_shift),
        end =
            (_point && !_allDay
                    ? baseStart
                    : _combine(
                        _endDate,
                        _endTime,
                      ).add(_allDay ? const Duration(days: 1) : Duration.zero))
                .add(_shift);
    if (end.isBefore(start) || (_allDay && end == start)) {
      setState(() => _error = '结束时间不能早于开始时间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final original = widget.event;
    try {
      await widget.controller.saveEvent(
        ScheduleEvent(
          id:
              original?.id ??
              '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x3fffffff)}',
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          start: start,
          end: end,
          allDay: _allDay,
          completed: _completed,
          reminderOffsets: List.unmodifiable(_reminders),
          reminderSound: _reminderSound,
          updatedAt: DateTime.now().toUtc(),
          revision: (original?.revision ?? 0) + 1,
          recurrence: _rule == null
              ? null
              : _draftRule(_rule!.frequency, baseStart),
          seriesId: original?.seriesId,
          occurrenceKey: original?.occurrenceKey,
          nodeId: original?.nodeId,
          color: _color,
          completedColor: _doneColor,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is FormatException
              ? e.message.toString()
              : '保存失败，请重试。表单内容已保留。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == 2) {
      return CycleEditor(
        controller: widget.controller,
        initial: _cycleDraft!,
        onMode: (mode, draft) => _setMode(mode, draft),
      );
    }
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.event == null ? '新建日程' : '编辑日程',
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
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('event-form-scroll'),
                    child: Form(
                      key: _form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.event?.seriesId == null) ...[
                            repeatModeSelector(_mode, _setMode),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _title,
                            autofocus: MediaQuery.sizeOf(context).width >= 600,
                            maxLength: widget.event?.nodeId == null ? 120 : 241,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '标题',
                              counterText: '',
                            ),
                            validator: (v) =>
                                !hasValidGroupTitle(
                                  v ?? '',
                                  _mode == 1 ? (_rule?.nodes ?? []) : [],
                                )
                                ? '请输入日程标题'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('全天'),
                                  const SizedBox(width: 4),
                                  Semantics(
                                    label: '全天日程',
                                    child: Switch(
                                      value: _allDay,
                                      onChanged: _saving
                                          ? null
                                          : (v) => setState(() {
                                              _allDay = v;
                                              if (v) _point = false;
                                            }),
                                    ),
                                  ),
                                ],
                              ),
                              if (!_allDay)
                                InkWell(
                                  onTap: () => setState(() => _point = !_point),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Checkbox(
                                        value: _point,
                                        onChanged: (v) =>
                                            setState(() => _point = v!),
                                      ),
                                      Text(
                                        MediaQuery.sizeOf(context).width < 600
                                            ? '仅时间点'
                                            : '仅时间点（无时长）',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              SizedBox(
                                width: min(
                                  248 *
                                      MediaQuery.textScalerOf(context).scale(1),
                                  min(
                                        660,
                                        MediaQuery.sizeOf(context).width - 32,
                                      ) -
                                      40,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: _colorButton(false)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _colorButton(true)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _dates(),
                          if (_mode == 1 && _rule != null) ...[
                            const SizedBox(height: 12),
                            HolidayPolicyField(
                              label: '默认节假日设置',
                              policy: _rule!.holidayPolicy,
                              priority: _rule!.weekendHolidayPriority,
                              onChanged: (p, w) => setState(() {
                                final old = _rule!;
                                _rule = RecurrenceRule(
                                  frequency: old.frequency,
                                  until: old.until,
                                  intervalDays: old.intervalDays,
                                  weekdays: old.weekdays,
                                  monthDays: old.monthDays,
                                  minutes: old.minutes,
                                  shiftMinutes: old.shiftMinutes,
                                  cycleCount: old.cycleCount,
                                  holidayPolicy: p,
                                  weekendHolidayPriority: w,
                                  nodes: [
                                    for (final n in old.nodes)
                                      n.holidayPolicy != old.holidayPolicy ||
                                              n.weekendHolidayPriority !=
                                                  old.weekendHolidayPriority
                                          ? n
                                          : RecurrenceNode(
                                              id: n.id,
                                              title: n.title,
                                              notes: n.notes,
                                              dayOffset: n.dayOffset,
                                              minute: n.minute,
                                              durationMinutes:
                                                  n.durationMinutes,
                                              allDay: n.allDay,
                                              color: n.color,
                                              completedColor: n.completedColor,
                                              reminderOffsets:
                                                  n.reminderOffsets,
                                              reminderSound: n.reminderSound,
                                              holidayPolicy: p,
                                              weekendHolidayPriority: w,
                                              legacyMinute: n.legacyMinute,
                                            ),
                                  ],
                                );
                              }),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _notes,
                            minLines: 2,
                            maxLines: 3,
                            maxLength: widget.event?.nodeId == null
                                ? 4000
                                : 8001,
                            decoration: const InputDecoration(
                              labelText: '备注',
                              counterText: '',
                              alignLabelWithHint: true,
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    if (widget.event != null && _rule == null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _completed,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _completed = v!),
                          ),
                          const Text('已完成'),
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? '保存中…' : '保存日程'),
                        ),
                      ],
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
