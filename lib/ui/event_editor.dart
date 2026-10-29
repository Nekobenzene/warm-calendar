import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'event_form.dart';
import 'motion.dart';

Future<void> openEventEditor(
  BuildContext context,
  AppController controller, {
  ScheduleEvent? event,
  DateTime? date,
  bool exactTime = false,
}) async {
  var editing = event;
  if (event?.seriesId != null) {
    final entire = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑重复日程'),
        content: const Text('已单独完成、修改或删除的各次会保留。'),
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
            child: const Text('编辑整个日程'),
          ),
        ],
      ),
    );
    if (entire == null || !context.mounted) return;
    if (entire) editing = controller.seriesFor(event!);
    if (editing == null) return;
  }
  if (!context.mounted) return;
  await showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EventEditor(
      controller: controller,
      event: editing,
      initialDate: date,
      exactTime: exactTime,
    ),
  );
}
