import 'package:flutter/material.dart';
import '../domain/reminders.dart';
import 'motion.dart';

class ReminderSelection {
  final List<int> offsets;
  final bool sound;
  const ReminderSelection(this.offsets, this.sound);
}

Future<ReminderSelection?> editReminders(
  BuildContext context,
  List<int> offsets,
  bool sound,
) => showAppDialog<ReminderSelection>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ReminderEditor(offsets: offsets, sound: sound),
);

class _ReminderEditor extends StatefulWidget {
  final List<int> offsets;
  final bool sound;
  const _ReminderEditor({required this.offsets, required this.sound});
  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final Set<int> _selected = widget.offsets.toSet();
  late bool _sound = widget.sound;
  final _amount = TextEditingController();
  int _unit = 1;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _add() {
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value < 0 || value * _unit > 525600) {
      setState(() => _error = '输入0—365天内的整数提前量');
      return;
    }
    final minutes = value * _unit;
    if (_selected.length >= 12 && !_selected.contains(minutes)) {
      setState(() => _error = '每次日程最多设置12条提醒');
      return;
    }
    setState(() {
      _selected.add(minutes);
      _error = null;
      _amount.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('提醒设置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in [0, 5, 10, 15, 30, 60, 1440])
                          FilterChip(
                            label: Text(reminderLabel(m)),
                            selected: _selected.contains(m),
                            onSelected: (v) => setState(() {
                              if (v && _selected.length >= 12) {
                                _error = '每次日程最多设置12条提醒';
                                return;
                              }
                              v ? _selected.add(m) : _selected.remove(m);
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, box) {
                        final amount = TextField(
                          key: const ValueKey('custom-reminder-amount'),
                          controller: _amount,
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _add(),
                          decoration: const InputDecoration(
                            labelText: '自定义提前量',
                          ),
                        );
                        final unit = DropdownButtonFormField<int>(
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '单位'),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('分钟')),
                            DropdownMenuItem(value: 60, child: Text('小时')),
                            DropdownMenuItem(value: 1440, child: Text('天')),
                          ],
                          onChanged: (v) => setState(() => _unit = v!),
                        );
                        if (box.maxWidth /
                                MediaQuery.textScalerOf(context).scale(1) <
                            320) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              amount,
                              const SizedBox(height: 12),
                              unit,
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _add,
                                child: const Text('添加提醒'),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: amount),
                            const SizedBox(width: 8),
                            SizedBox(width: 100, child: unit),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _add,
                              child: const Text('添加'),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _selected.isEmpty ? '不提醒' : '已选${_selected.length}条',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m
                            in _selected.toList()
                              ..sort((a, b) => b.compareTo(a)))
                          InputChip(
                            label: Text(reminderLabel(m)),
                            onDeleted: () =>
                                setState(() => _selected.remove(m)),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _sound,
                          onChanged: (v) => setState(() => _sound = v!),
                        ),
                        const Flexible(child: Text('提示音')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('清空提醒'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        ReminderSelection(
                          _selected.toList()..sort((a, b) => b.compareTo(a)),
                          _sound,
                        ),
                      ),
                      child: const Text('应用提醒'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
