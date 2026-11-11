import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../domain/todos.dart';
import 'components.dart';
import 'item_context_menu.dart';
import 'motion.dart';
import 'theme.dart';
import 'todo_editor.dart';

String todoDateText(ScheduleEvent task) {
  final created = task.createdAt.toLocal();
  return '创建 ${dateKey(created)} ${clockText(created)}${task.deadline == null ? '' : '  ·  截止 ${dateKey(task.deadline!)} ${clockText(task.deadline!)}'}';
}

class TodosPage extends StatefulWidget {
  final AppController controller;
  const TodosPage({super.key, required this.controller});
  @override
  State<TodosPage> createState() => TodosPageState();
}

class TodosPageState extends State<TodosPage> {
  final _scroll = ScrollController();
  TodoFilter _filter = TodoFilter.pending;
  bool _multi = false, _busy = false;
  final _selected = <String>{};
  String? _highlight;
  int _focusRevision = 0;
  List<double> _extents = [];
  List<ScheduleEvent> get _visible => widget.controller.todos
      .where((e) => matchesTodo(e, _filter, widget.controller.now))
      .toList();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void focusTask(String id) {
    final task = widget.controller.todos.where((e) => e.id == id).firstOrNull;
    if (task == null) return;
    final revision = ++_focusRevision;
    setState(() {
      if (!matchesTodo(task, _filter, widget.controller.now)) {
        _filter = task.completed ? TodoFilter.completed : TodoFilter.pending;
      }
      _highlight = id;
      _multi = false;
      _selected.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || revision != _focusRevision || !_scroll.hasClients) return;
      final index = _visible.indexWhere((e) => e.id == id);
      if (index < 0) return;
      final offset =
          (_extents.take(index).fold<double>(0, (a, b) => a + b) -
                  _scroll.position.viewportDimension * .25)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(offset);
      } else {
        await _scroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 440),
          curve: Curves.easeInOutCubic,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted && revision == _focusRevision) {
        setState(() => _highlight = null);
      }
    });
  }

  Future<void> _batch({bool? completed, bool delete = false}) async {
    if (_busy || _selected.isEmpty) return;
    final ids = Set<String>.from(_selected);
    if (completed == true && !delete) {
      if (!await confirmTodoCompletion(context, '选中的 ${ids.length} 项待办') ||
          !mounted) {
        return;
      }
    }
    if (delete) {
      final yes = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除待办'),
          content: Text('删除选中的 ${ids.length} 项待办？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.changeTodos(
        ids,
        completed: completed,
        delete: delete,
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _multi = false;
        });
        showMessage(
          context,
          delete
              ? '待办已删除'
              : completed == true
              ? '已标为完成'
              : '已标为未完成',
        );
      }
    } catch (_) {
      if (mounted) showMessage(context, '操作失败，请重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final tasks = _visible;
    final moved = tasks.removeAt(oldIndex);
    tasks.insert(newIndex, moved);
    var ids = tasks.map((e) => e.id).toList();
    if (widget.controller.settings.todoSortDescending) {
      ids = ids.reversed.toList();
    }
    setState(() => _busy = true);
    try {
      await widget.controller.reorderTodos(ids);
    } catch (_) {
      if (mounted) showMessage(context, '排序保存失败，请重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final tasks = _visible;
    final visibleIds = tasks.map((e) => e.id).toSet();
    _selected.removeWhere((id) => !visibleIds.contains(id));
    final chosen = tasks.where((e) => _selected.contains(e.id)).toList();
    final canComplete = chosen.isNotEmpty && chosen.every((e) => !e.completed);
    final canRestore = chosen.isNotEmpty && chosen.every((e) => e.completed);
    final reorderAllowed =
        c.settings.todoSort == TodoSort.importance &&
        (_filter == TodoFilter.pending || _filter == TodoFilter.overdue) &&
        !_multi;
    final dragEnabled = reorderAllowed && !_busy;

    Widget row(int index) {
      final e = tasks[index];
      final child = AnimatedContainer(
        key: ValueKey('todo-row-${e.id}'),
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _highlight == e.id || _selected.contains(e.id)
              ? context.appColors.selected
              : context.appColors.surface,
          border: Border(bottom: BorderSide(color: context.appColors.border)),
        ),
        child: InkWell(
          onTap: _busy
              ? null
              : () {
                  if (_multi) {
                    setState(() {
                      if (!_selected.add(e.id)) _selected.remove(e.id);
                    });
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                if (_multi)
                  Checkbox(
                    value: _selected.contains(e.id),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v!) {
                              _selected.add(e.id);
                            } else {
                              _selected.remove(e.id);
                            }
                          }),
                  ),
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(e.displayColor),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          decoration: e.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (e.notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            e.notes,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 5),
                      Text(
                        todoDateText(e),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: e.statusAt(c.now) == ScheduleStatus.overdue
                              ? AppColors.danger
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_multi && phone)
                  EventOptionsButton(
                    event: e,
                    controller: c,
                    onEdit: () => openTodoEditor(context, c, task: e),
                  ),
                if (!_multi && !phone) ...[
                  const SizedBox(width: 12),
                  _TodoAction(
                    label: '编辑',
                    color: AppColors.text,
                    onPressed: _busy
                        ? null
                        : () => openTodoEditor(context, c, task: e),
                  ),
                  _TodoAction(
                    label: e.completed ? '未完成' : '完成',
                    color: const Color(0xff39714b),
                    onPressed: _busy
                        ? null
                        : () => completeEvent(context, c, e),
                  ),
                  _TodoAction(
                    label: '删除',
                    color: AppColors.danger,
                    onPressed: _busy ? null : () => deleteEvent(context, c, e),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      return KeyedSubtree(
        key: ValueKey(e.id),
        child: ReorderableDelayedDragStartListener(
          index: index,
          enabled: dragEnabled,
          child: ItemContextMenu(controller: c, event: e, child: child),
        ),
      );
    }

    return ItemContextMenu(
      controller: c,
      isTodo: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final filter in TodoFilter.values)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _filter = filter;
                          _selected.clear();
                          _focusRevision++;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 145,
                child: DropdownButtonFormField<TodoSort>(
                  isExpanded: true,
                  initialValue: c.settings.todoSort,
                  decoration: const InputDecoration(
                    labelText: '排序方式',
                    isDense: true,
                  ),
                  items: [
                    for (final s in TodoSort.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(s.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (s) => runAction(
                          context,
                          () => c.updateSettings(
                            c.settings.copyWith(todoSort: s),
                          ),
                        ),
                ),
              ),
              IconButton(
                tooltip: c.settings.todoSortDescending
                    ? '倒序，点击切换正序'
                    : '正序，点击切换倒序',
                onPressed: _busy
                    ? null
                    : () => runAction(
                        context,
                        () => c.updateSettings(
                          c.settings.copyWith(
                            todoSortDescending: !c.settings.todoSortDescending,
                          ),
                        ),
                      ),
                icon: SortDirectionIcon(
                  descending: c.settings.todoSortDescending,
                ),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _multi = !_multi;
                        _selected.clear();
                      }),
                child: Text(_multi ? '退出多选' : '多选'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.repeat, size: 18),
                label: const Text('重复组'),
                onPressed: () => showTodoGroups(context, c),
              ),
            ],
          ),
          if (_multi)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${chosen.length}'),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            if (_selected.length == tasks.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll(visibleIds);
                            }
                          }),
                    child: Text(
                      _selected.length == tasks.length ? '取消全选' : '全选',
                    ),
                  ),
                  TextButton(
                    onPressed: !_busy && canComplete
                        ? () => _batch(completed: true)
                        : null,
                    child: const Text('完成'),
                  ),
                  TextButton(
                    onPressed: !_busy && canRestore
                        ? () => _batch(completed: false)
                        : null,
                    child: const Text('未完成'),
                  ),
                  TextButton(
                    onPressed: !_busy && chosen.isNotEmpty
                        ? () => _batch(delete: true)
                        : null,
                    child: const Text('删除'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Text(
                      '暂无待办',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final textWidth = math.max(
                        24.0,
                        constraints.maxWidth -
                            (phone ? 90 : 254) -
                            (_multi ? 48 : 0),
                      );
                      double textHeight(
                        String text,
                        TextStyle style, {
                        int? maxLines,
                      }) {
                        final painter = TextPainter(
                          text: TextSpan(text: text, style: style),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          maxLines: maxLines,
                        )..layout(maxWidth: textWidth);
                        final height = painter.height;
                        painter.dispose();
                        return height;
                      }

                      final bodyStyle = DefaultTextStyle.of(context).style;
                      _extents = [
                        for (final task in tasks)
                          math.max(
                            phone ? 64.0 : 60.0,
                            17 +
                                textHeight(
                                  task.title,
                                  bodyStyle.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                ) +
                                (task.notes.isEmpty
                                    ? 0
                                    : 3 +
                                          textHeight(
                                            task.notes,
                                            bodyStyle.copyWith(fontSize: 12),
                                          )) +
                                5 +
                                textHeight(
                                  todoDateText(task),
                                  bodyStyle.copyWith(fontSize: 11),
                                  maxLines: 2,
                                ),
                          ),
                      ];
                      return ReorderableListView.builder(
                        key: const ValueKey('todos-list'),
                        scrollController: _scroll,
                        itemExtentBuilder: (index, _) => _extents[index],
                        buildDefaultDragHandles: false,
                        onReorderItem: _reorder,
                        itemCount: tasks.length,
                        autoScrollerVelocityScalar: 60,
                        itemBuilder: (_, i) => row(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TodoAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  const _TodoAction({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(color),
        backgroundColor: WidgetStatePropertyAll(context.appColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(color.withValues(alpha: .20)),
        elevation: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 2 : 0,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(52, 34)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        animationDuration: const Duration(milliseconds: 150),
      ),
      child: Text(label),
    ),
  );
}

Future<void> showTodoOverview(
  BuildContext context,
  AppController c,
  ValueChanged<String> onOpen,
) => showAppDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('全部待办'),
    content: SizedBox(
      width: 560,
      height: math.min(480, MediaQuery.sizeOf(context).height * .6),
      child: AnimatedBuilder(
        animation: c,
        builder: (_, _) {
          final tasks = c.todos;
          if (tasks.isEmpty) return const Center(child: Text('暂无待办'));
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (_, i) {
              final e = tasks[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  onOpen(e.id);
                },
                title: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  e.deadline == null
                      ? '无截止时间'
                      : '截止 ${dateKey(e.deadline!)} ${clockText(e.deadline!)}',
                  maxLines: 2,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: e.completed ? '标为未完成' : '完成',
                      onPressed: () => completeEvent(ctx, c, e),
                      icon: Icon(
                        e.completed
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除待办',
                      onPressed: () => deleteEvent(ctx, c, e),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
    ],
  ),
);

class HomeTodoPanel extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onOpen;
  const HomeTodoPanel({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final pending = controller.todos.where((e) => !e.completed).toList();
    final overdue = pending
        .where((e) => e.statusAt(controller.now) == ScheduleStatus.overdue)
        .length;
    final next = pending.firstOrNull;
    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '${pending.length} 未完成（$overdue 逾期）',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => openTodoEditor(context, controller),
                    child: const Text('新增待办'),
                  ),
                  TextButton(
                    onPressed: () =>
                        showTodoOverview(context, controller, onOpen),
                    child: const Text('查看待办'),
                  ),
                ],
              ),
            ],
          ),
          InkWell(
            onTap: next == null ? null : () => onOpen(next.id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Text(
                    '下一项待办',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      next?.title ?? '没有未完成待办',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (next != null) const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showTodoGroups(
  BuildContext context,
  AppController c,
) => showAppDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('重复待办组'),
    content: SizedBox(
      width: 560,
      height: math.min(400, MediaQuery.sizeOf(context).height * .55),
      child: AnimatedBuilder(
        animation: c,
        builder: (_, _) {
          final groups = c.todoGroups;
          if (groups.isEmpty) return const Center(child: Text('暂无重复待办组'));
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (_, i) {
              final group = groups[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  group.title.isEmpty
                      ? group.todoRepeat!.nodes
                            .map((n) => n.item.title)
                            .join('、')
                      : group.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${group.todoRepeat!.nodes.length} 项 · 起始 ${dateKey(group.start)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '编辑重复组',
                      onPressed: () => openTodoEditor(ctx, c, task: group),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '删除重复组',
                      onPressed: () => deleteEvent(ctx, c, group),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
    ],
  ),
);
