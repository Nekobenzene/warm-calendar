import 'package:flutter/material.dart';
import '../domain/models.dart';

class AutomationFields extends StatelessWidget {
  final ItemAutomation value;
  final bool single;
  final ValueChanged<ItemAutomation> onChanged;
  const AutomationFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.single = false,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 0,
    children: [
      for (final entry in <(String, bool, ValueChanged<bool>)>[
        (
          '逾期自动完成',
          value.completeExpired,
          (v) => onChanged(value.copyWith(completeExpired: v)),
        ),
        (
          '完成后自动删除',
          value.deleteCompleted,
          (v) => onChanged(value.copyWith(deleteCompleted: v)),
        ),
        if (single)
          (
            '逾期自动删除',
            value.deleteExpired,
            (v) => onChanged(value.copyWith(deleteExpired: v)),
          ),
      ])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: entry.$2, onChanged: (v) => entry.$3(v!)),
            Flexible(child: Text(entry.$1)),
          ],
        ),
    ],
  );
}
