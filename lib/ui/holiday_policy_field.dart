import 'package:flutter/material.dart';
import '../domain/models.dart';

class HolidayPolicyField extends StatelessWidget {
  final HolidayPolicy policy;
  final WeekendHolidayPriority priority;
  final String label;
  final void Function(HolidayPolicy, WeekendHolidayPriority) onChanged;
  const HolidayPolicyField({
    super.key,
    required this.policy,
    required this.priority,
    required this.onChanged,
    this.label = '节假日',
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<HolidayPolicy>(
        key: ValueKey('holiday-${policy.name}'),
        initialValue: policy,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final p in HolidayPolicy.values)
            DropdownMenuItem(value: p, child: Text(p.label)),
        ],
        onChanged: (p) {
          if (p != null) onChanged(p, priority);
        },
      ),
      if (policy != HolidayPolicy.ignore)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('周末的节假日算作', style: TextStyle(fontSize: 12)),
              for (final p in WeekendHolidayPriority.values)
                ChoiceChip(
                  label: Text(
                    p == WeekendHolidayPriority.holiday ? '节假日' : '周末',
                  ),
                  selected: p == priority,
                  onSelected: (_) => onChanged(policy, p),
                ),
            ],
          ),
        ),
    ],
  );
}
