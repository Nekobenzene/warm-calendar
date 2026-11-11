import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'event_editor.dart';
import 'components.dart';
import 'motion.dart';

class ItemContextMenu extends StatelessWidget {
  final AppController controller;
  final ScheduleEvent? event;
  final bool? isTodo;
  final DateTime? date;
  final Widget child;
  final ValueChanged<ScheduleEvent>? onPaste;
  final bool enabled;
  const ItemContextMenu({
    super.key,
    required this.controller,
    required this.child,
    this.event,
    this.isTodo,
    this.date,
    this.onPaste,
    this.enabled = true,
  });
  Future<void> _menu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final kind = event?.isTodo ?? isTodo;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        overlay.size,
      ),
      popUpAnimationStyle: AppMotion.popup(context),
      items: [
        if (event != null) ...[
          const PopupMenuItem(value: 'copy', child: Text('复制')),
          const PopupMenuItem(value: 'cut', child: Text('剪切')),
        ],
        for (final todo in kind == null ? [false, true] : [kind])
          PopupMenuItem(
            value: todo ? 'paste-todo' : 'paste-event',
            enabled: controller.clipboard.entry(todo) != null,
            child: Text(kind == null ? (todo ? '粘贴待办' : '粘贴日程') : '粘贴'),
          ),
      ],
    );
    if (!context.mounted || value == null) return;
    if (value == 'copy' || value == 'cut') {
      controller.copyItem(event!, cut: value == 'cut');
      showMessage(context, value == 'cut' ? '已剪切，粘贴保存后移除原项' : '已复制');
    } else {
      final draft = controller.pasteDraft(value == 'paste-todo', date: date);
      if (draft == null) return;
      if (onPaste != null) {
        onPaste!(draft);
      } else {
        await openEventEditor(context, controller, event: draft);
        controller.discardPaste(draft.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: enabled
        ? (d) => _menu(context, d.globalPosition)
        : null,
    child: child,
  );
}
