import 'dart:math';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'color_picker.dart';
import 'components.dart';
import 'motion.dart';

Future<void> openTodoEditor(
  BuildContext context,
  AppController controller, {
  ScheduleEvent? task,
}) => showAppDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TodoEditor(controller: controller, task: task),
);

class TodoEditor extends StatefulWidget {
  final AppController controller;
  final ScheduleEvent? task;
  const TodoEditor({super.key, required this.controller, this.task});
  @override
  State<TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<TodoEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _notes = TextEditingController(text: widget.task?.notes ?? '');
  late bool _dated = widget.task?.hasDeadline ?? false;
  late DateTime _deadline =
      widget.task?.deadline ?? DateTime.now().add(const Duration(days: 1));
  late int _color = widget.task?.color ?? 0xffe4ead9;
  late int _completedColor = widget.task?.completedColor ?? 0xffe2e3df;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final old = widget.task;
      final anchor = _dated ? _deadline : (old?.start ?? now);
      final task = old == null
          ? ScheduleEvent(
              id: 'todo-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(0x3fffffff)}',
              isTodo: true,
              hasDeadline: _dated,
              taskCreatedAt: now.toUtc(),
              todoOrder:
                  widget.controller.todos.fold<int>(
                    -1,
                    (n, e) => max(n, e.todoOrder),
                  ) +
                  1,
              title: _title.text.trim(),
              notes: _notes.text.trim(),
              start: anchor,
              end: anchor,
              updatedAt: now.toUtc(),
              reminderOffsets: const [],
              color: _color,
              completedColor: _completedColor,
            )
          : old.copyWith(
              title: _title.text.trim(),
              notes: _notes.text.trim(),
              hasDeadline: _dated,
              start: anchor,
              end: anchor,
              color: _color,
              completedColor: _completedColor,
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

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime(1901),
      lastDate: DateTime(2099, 12, 31),
    );
    if (date != null && mounted) {
      setState(
        () => _deadline = DateTime(
          date.year,
          date.month,
          date.day,
          _deadline.hour,
          _deadline.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time != null && mounted) {
      setState(
        () => _deadline = DateTime(
          _deadline.year,
          _deadline.month,
          _deadline.day,
          time.hour,
          time.minute,
        ),
      );
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
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.task == null ? '新增待办' : '编辑待办'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: '名称'),
                maxLength: 120,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请填写名称' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: '备注'),
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设置截止时间'),
                value: _dated,
                onChanged: _saving ? null : (v) => setState(() => _dated = v!),
              ),
              if (_dated)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _pickDate,
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
                children: [_colorButton(false), _colorButton(true)],
              ),
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
