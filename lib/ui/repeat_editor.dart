import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/calendar_service.dart';
import '../domain/recurrence.dart';
import 'motion.dart';
import 'theme.dart';

Future<RecurrenceRule?> editRepeatRule(
  BuildContext context, {
  required RecurrenceRule initial,
  required CalendarService calendar,
  required DateTime start,
  required DateTime end,
  required bool allDay,
}) => showAppDialog<RecurrenceRule>(
  context: context,
  builder: (_) => _RepeatEditor(
    initial: initial,
    calendar: calendar,
    start: start,
    end: end,
    allDay: allDay,
  ),
);

class _RepeatEditor extends StatefulWidget {
  final RecurrenceRule initial;
  final CalendarService calendar;
  final DateTime start, end;
  final bool allDay;
  const _RepeatEditor({
    required this.initial,
    required this.calendar,
    required this.start,
    required this.end,
    required this.allDay,
  });
  @override
  State<_RepeatEditor> createState() => _RepeatEditorState();
}

class _RepeatEditorState extends State<_RepeatEditor> {
  final _form = GlobalKey<FormState>();
  late RepeatFrequency _frequency = widget.initial.frequency;
  late HolidayPolicy _holiday = widget.initial.holidayPolicy;
  late final _until = TextEditingController(
    text: dateKey(widget.initial.until),
  );
  late final _interval = TextEditingController(
    text: '${widget.initial.intervalDays}',
  );
  late final _monthDays = TextEditingController(
    text:
        (widget.initial.monthDays.isEmpty
                ? [widget.start.day]
                : widget.initial.monthDays)
            .join('、'),
  );
  late final Set<int> _weekdays =
      (widget.initial.weekdays.isEmpty
              ? [widget.start.weekday]
              : widget.initial.weekdays)
          .toSet();
  late final List<TextEditingController> _times = [
    for (final m in widget.initial.minutes.where(
      (m) => m != widget.start.hour * 60 + widget.start.minute,
    ))
      TextEditingController(text: '${pad2(m ~/ 60)}:${pad2(m % 60)}'),
  ];
  String? _error;
  @override
  void dispose() {
    for (final c in [_until, _interval, _monthDays, ..._times]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _date(String text) {
    final date = DateTime.tryParse(text);
    return date != null &&
            date.year >= 1901 &&
            date.year <= 2099 &&
            dateKey(date) == text
        ? date
        : null;
  }

  Future<void> _pickUntil() async {
    final first = dayOnly(widget.start);
    final candidate = _date(_until.text) ?? first;
    final date = await showDatePicker(
      context: context,
      initialDate: candidate.isBefore(first) ? first : candidate,
      firstDate: first,
      lastDate: DateTime(2099, 12, 31),
    );
    if (date != null) setState(() => _until.text = dateKey(date));
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final base = widget.start.hour * 60 + widget.start.minute;
    final minutes = widget.allDay
        ? [0]
        : [
            base,
            for (final field in _times)
              int.parse(field.text.split(':')[0]) * 60 +
                  int.parse(field.text.split(':')[1]),
          ];
    final rule = RecurrenceRule(
      frequency: _frequency,
      until: _date(_until.text)!,
      intervalDays: _frequency == RepeatFrequency.interval
          ? int.parse(_interval.text)
          : 2,
      weekdays: _weekdays.toList()..sort(),
      monthDays: _monthDays.text
          .split(RegExp(r'[,，、\s]+'))
          .where((s) => s.isNotEmpty)
          .map((s) => int.tryParse(s) ?? 0)
          .toList(),
      minutes: minutes,
      holidayPolicy: _holiday,
      shiftMinutes: widget.initial.shiftMinutes,
    );
    try {
      final shift = Duration(minutes: rule.shiftMinutes);
      expandSeries(
        ScheduleEvent(
          id: 'rule-preview',
          title: '重复预览',
          start: widget.start.add(shift),
          end: widget.end.add(shift),
          updatedAt: DateTime.now(),
          allDay: widget.allDay,
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
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('重复设置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
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
                      child: Text('每隔几日'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _frequency = v!),
                ),
                const SizedBox(height: 12),
                if (_frequency == RepeatFrequency.weekly) ...[
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 1; i <= 7; i++)
                        FilterChip(
                          label: Text(
                            '周${const ['一', '二', '三', '四', '五', '六', '日'][i - 1]}',
                          ),
                          selected: _weekdays.contains(i),
                          onSelected: (v) => setState(
                            () => v ? _weekdays.add(i) : _weekdays.remove(i),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_frequency == RepeatFrequency.monthly) ...[
                  TextFormField(
                    controller: _monthDays,
                    decoration: const InputDecoration(
                      labelText: '每月日期',
                      helperText: '如 1、15、28；无该日期的月份跳过',
                    ),
                    validator: (v) {
                      final days = (v ?? '')
                          .split(RegExp(r'[,，、\s]+'))
                          .where((s) => s.isNotEmpty)
                          .map(int.tryParse)
                          .toList();
                      return days.isEmpty ||
                              days.toSet().length != days.length ||
                              days.any((d) => d == null || d < 1 || d > 31)
                          ? '填写1—31，用顿号分隔'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_frequency == RepeatFrequency.interval) ...[
                  TextFormField(
                    controller: _interval,
                    decoration: const InputDecoration(
                      labelText: '间隔天数',
                      suffixText: '天',
                    ),
                    validator: (v) =>
                        (int.tryParse(v ?? '') ?? 0) < 1 ||
                            (int.tryParse(v ?? '') ?? 0) > 365
                        ? '填写1—365'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                if (!widget.allDay) ...[
                  Text(
                    '第1次 ${clockText(widget.start)} · 每日${_times.length + 1}次',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _times.length; i++)
                        SizedBox(
                          width: 168,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _times[i],
                                  decoration: InputDecoration(
                                    labelText: '时间点 ${i + 2}',
                                  ),
                                  validator: (v) =>
                                      RegExp(
                                        r'^([01]\d|2[0-3]):[0-5]\d$',
                                      ).hasMatch(v ?? '')
                                      ? null
                                      : '使用HH:mm',
                                ),
                              ),
                              IconButton(
                                tooltip: '移除此时间点',
                                onPressed: () => setState(() {
                                  final field = _times.removeAt(i);
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => field.dispose(),
                                  );
                                }),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _times.length >= 23
                          ? null
                          : () => setState(
                              () => _times.add(
                                TextEditingController(
                                  text:
                                      '${pad2((widget.start.hour + _times.length + 1) % 24)}:${pad2(widget.start.minute)}',
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加每日时间点'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _until,
                  decoration: InputDecoration(
                    labelText: '重复至（含当天）',
                    suffixIcon: IconButton(
                      tooltip: '选择重复截止日期',
                      onPressed: _pickUntil,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                  ),
                  validator: (v) =>
                      _date(v ?? '') == null ? '使用YYYY-MM-DD（1901—2099）' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<HolidayPolicy>(
                  initialValue: _holiday,
                  decoration: const InputDecoration(labelText: '节假日'),
                  items: const [
                    DropdownMenuItem(
                      value: HolidayPolicy.ignore,
                      child: Text('无视节假日'),
                    ),
                    DropdownMenuItem(
                      value: HolidayPolicy.skip,
                      child: Text('跳过节假日'),
                    ),
                    DropdownMenuItem(
                      value: HolidayPolicy.only,
                      child: Text('只取节假日'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _holiday = v!),
                ),
                if (_holiday != HolidayPolicy.ignore)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '含周末及法定休假，调休上班除外。已收录：${widget.calendar.holidayYears.join('、')}年。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _apply,
                      child: const Text('应用重复规则'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
