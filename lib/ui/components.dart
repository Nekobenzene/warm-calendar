import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/calendar_service.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'motion.dart';
import 'toast.dart';

class SortDirectionIcon extends StatelessWidget {
  final bool descending;
  final double size;
  const SortDirectionIcon({
    super.key,
    required this.descending,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: descending ? .5 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    curve: Curves.easeInOutCubic,
    child: Icon(Icons.arrow_upward, size: size),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: context.appColors.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: borderColor ?? context.appColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class Marker extends StatelessWidget {
  final String label;
  final bool warning;
  const Marker(this.label, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFF3E9DC) : context.appColors.selected,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: warning ? AppColors.warning : context.appColors.accent,
      ),
    ),
  );
}

class DayMarkers extends StatelessWidget {
  final CalendarDay info;
  const DayMarkers(this.info, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (info.holiday != null)
        Marker(
          '${info.holiday!.name} · ${info.holiday!.isOffDay ? '休息' : '调休上班'}',
          warning: !info.holiday!.isOffDay,
        ),
      if (info.solarTerm.isNotEmpty) Marker(info.solarTerm),
      for (final f in info.festivals.where((f) => f != info.holiday?.name))
        Marker(f),
    ],
  );
}

class StatusPill extends StatelessWidget {
  final ScheduleStatus status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: status == ScheduleStatus.overdue
          ? const Color(0xFFF3E9DC)
          : status == ScheduleStatus.ongoing
          ? context.appColors.selected
          : context.appColors.sidebar,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontSize: 12,
        color: status == ScheduleStatus.overdue
            ? AppColors.warning
            : status == ScheduleStatus.ongoing
            ? context.appColors.accent
            : AppColors.muted,
      ),
    ),
  );
}

String eventTimeText(
  ScheduleEvent e,
  AppSettings settings, {
  bool withDate = false,
}) {
  if (e.allDay) {
    final last = e.end.subtract(const Duration(days: 1));
    final range = sameDay(e.start, last)
        ? '${e.start.month}月${e.start.day}日'
        : '${e.start.month}/${e.start.day}—${last.month}/${last.day}';
    return withDate ? '$range · 全天' : '全天';
  }
  final start = clockText(e.start, hour24: settings.hour24);
  if (e.isPoint) {
    return '${withDate ? '${e.start.month}月${e.start.day}日 ' : ''}$start · 时间点';
  }
  final end = clockText(e.end, hour24: settings.hour24);
  final range = sameDay(e.start, e.end)
      ? '$start—$end'
      : '${e.start.month}/${e.start.day} $start—${e.end.month}/${e.end.day} $end';
  return withDate && sameDay(e.start, e.end)
      ? '${e.start.month}月${e.start.day}日 $range'
      : range;
}

class EventRow extends StatelessWidget {
  final ScheduleEvent event;
  final AppController controller;
  final VoidCallback onEdit;
  final bool withDate;
  const EventRow({
    super.key,
    required this.event,
    required this.controller,
    required this.onEdit,
    this.withDate = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: event.completed ? AppColors.muted : AppColors.text,
                      decoration: event.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      Text(
                        eventTimeText(
                          event,
                          controller.settings,
                          withDate: withDate,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!event.completed &&
                          event.end.isBefore(controller.now))
                        const Text(
                          '已过期',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.warning,
                          ),
                        ),
                    ],
                  ),
                  if (event.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        event.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(event.statusAt(controller.now)),
        EventOptionsButton(
          event: event,
          controller: controller,
          onEdit: onEdit,
        ),
      ],
    ),
  );
}

class EventOptionsButton extends StatefulWidget {
  final ScheduleEvent event;
  final AppController controller;
  final VoidCallback onEdit;
  const EventOptionsButton({
    super.key,
    required this.event,
    required this.controller,
    required this.onEdit,
  });
  @override
  State<EventOptionsButton> createState() => _EventOptionsButtonState();
}

class _EventOptionsButtonState extends State<EventOptionsButton> {
  final _focus = FocusNode();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  bool _menuOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = context.findRenderObject()! as RenderBox;
    final rect =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    setState(() => _menuOpen = true);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTRB(rect.left, rect.bottom + 4, rect.right, rect.bottom + 4),
        Offset.zero & overlay.size,
      ),
      color: context.appColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      popUpAnimationStyle: AppMotion.popup(context),
      requestFocus: true,
      items: [
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              SizedBox(width: 10),
              Text('删除', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'complete',
          child: Row(
            children: [
              Icon(widget.event.completed ? Icons.undo : Icons.check, size: 18),
              const SizedBox(width: 10),
              Text(widget.event.completed ? '标为未完成' : '标为已完成'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 10),
              Text('编辑'),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (value == 'delete') {
      await deleteEvent(context, widget.controller, widget.event);
    }
    if (value == 'complete' && mounted) {
      await completeEvent(context, widget.controller, widget.event);
    }
    if (value == 'edit') widget.onEdit();
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused || _menuOpen;
    return Tooltip(
      message: '选项',
      excludeFromSemantics: true,
      child: Semantics(
        key: ValueKey('event-options-${widget.event.id}'),
        button: true,
        label: '选项',
        onTap: _openMenu,
        child: FocusableActionDetector(
          focusNode: _focus,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _openMenu();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openMenu,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedContainer(
              width: 40,
              height: 40,
              duration: AppMotion.hover(context),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: context.appColors.selected.withValues(
                  alpha: _pressed
                      ? .65
                      : active
                      ? .4
                      : 0,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: context.appColors.input.withValues(
                    alpha: _focused
                        ? .9
                        : active
                        ? .25
                        : 0,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: active ? .035 : 0),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.more_horiz,
                size: 22,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> completeEvent(
  BuildContext context,
  AppController controller,
  ScheduleEvent event,
) async {
  if (event.isTodo && !event.completed) {
    final confirmed = await confirmTodoCompletion(context, event.title);
    if (!confirmed || !context.mounted) return;
  }
  if (context.mounted) {
    await runAction(
      context,
      () => controller.toggleCompleted(event),
      success: event.isTodo ? (event.completed ? '待办已标为未完成' : '待办已完成') : null,
    );
  }
}

Future<bool> confirmTodoCompletion(BuildContext context, String title) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成待办'),
        content: Text('将“$title”标为已完成？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('完成'),
          ),
        ],
      ),
    ) ==
    true;

class EmptyState extends StatelessWidget {
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState(this.message, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_note_outlined,
            color: AppColors.muted,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(onPressed: onAction, child: Text(action!)),
            ),
        ],
      ),
    ),
  );
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  showToast(Overlay.of(context, rootOverlay: true), message, error: error);
}

void _showMessage(
  OverlayState overlay,
  double width,
  String message, {
  bool error = false,
}) {
  showToast(overlay, message, error: error);
}

Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = Overlay.of(context, rootOverlay: true);
  final width = MediaQuery.sizeOf(context).width;
  try {
    await action();
    if (success != null) _showMessage(messenger, width, success);
    return true;
  } catch (_) {
    _showMessage(messenger, width, '保存失败，请重试。原有数据已保留。', error: true);
    return false;
  }
}

Future<void> deleteEvent(
  BuildContext context,
  AppController controller,
  ScheduleEvent event,
) async {
  final messenger = Overlay.of(context, rootOverlay: true);
  final width = MediaQuery.sizeOf(context).width;
  final repeated = event.seriesId != null || event.todoRepeat != null;
  final confirmed = await showAppDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(event.isTodo ? '删除待办' : '删除日程'),
      content: Text(
        repeated
            ? '删除“${event.title}”的本次，还是整个重复${event.isTodo ? '待办组' : '日程'}？整组包含已完成和已单独修改的各次。'
            : '删除“${event.title}”？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        if (repeated && event.seriesId != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'once'),
            child: const Text('仅删除本次'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, repeated ? 'series' : 'once'),
          child: Text(repeated ? (event.isTodo ? '删除整个待办组' : '删除整个日程') : '删除'),
        ),
      ],
    ),
  );
  if (confirmed != null && context.mounted) {
    try {
      await controller.deleteEvent(event, entireSeries: confirmed == 'series');
      _showMessage(
        messenger,
        width,
        confirmed == 'series'
            ? (event.isTodo ? '重复待办组已删除' : '整个重复日程已删除')
            : event.isTodo
            ? '待办已删除'
            : '日程已删除',
      );
    } catch (_) {
      _showMessage(
        messenger,
        width,
        '删除失败，${event.isTodo ? '待办' : '日程'}已保留，请重试。',
        error: true,
      );
    }
  }
}
