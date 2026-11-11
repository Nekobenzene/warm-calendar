import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'calendar_page.dart';
import 'event_editor.dart';
import 'home_page.dart';
import 'schedules_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'components.dart';
import 'link_page.dart';
import 'motion.dart';
import 'appearance.dart';
import 'scroll_feedback.dart';
import 'update_panel.dart';
import 'todos_page.dart';
import 'todo_editor.dart';

class AppShell extends StatefulWidget {
  final AppController controller;
  const AppShell({super.key, required this.controller});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    widget.controller.notifications.openedEvent.addListener(_openNotification);
    widget.controller.addListener(_openNotification);
    widget.controller.link?.addListener(_offerPairing);
  }

  final Set<String> _offered = {};
  bool _pairDialogOpen = false;
  void _offerPairing() {
    final link = widget.controller.link;
    if (!mounted ||
        link == null ||
        link.isMobile ||
        _pairDialogOpen ||
        widget.controller.loading) {
      return;
    }
    final request = link.requests
        .where((r) => !_offered.contains(r['requestId']))
        .firstOrNull;
    if (request == null) return;
    _offered.add(request['requestId'] as String);
    _pairDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final yes = await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('允许设备连接'),
          content: Text(
            '${request['name']} 请求同步日程。\n\n校验码：${request['code']}\n请与手机上的数字核对。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许连接'),
            ),
          ],
        ),
      );
      try {
        await link.confirmPair(request['requestId'] as String, yes == true);
      } catch (e) {
        if (mounted) showMessage(context, '$e', error: true);
      } finally {
        _pairDialogOpen = false;
      }
    });
  }

  void _openNotification() {
    final c = widget.controller;
    final id = c.notifications.openedEvent.value;
    if (!mounted || c.loading || id == null) return;
    c.notifications.openedEvent.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final event = c.allItems.where((e) => e.id == id).firstOrNull;
      if (event == null) {
        showMessage(context, '此日程已删除或不再存在');
        return;
      }
      _openCalendar(event.start);
      openEventEditor(context, c, event: event);
    });
  }

  @override
  void dispose() {
    widget.controller.notifications.openedEvent.removeListener(
      _openNotification,
    );
    widget.controller.removeListener(_openNotification);
    widget.controller.link?.removeListener(_offerPairing);
    super.dispose();
  }

  int _page = 0;
  final _calendarKey = GlobalKey<CalendarPageState>();
  final _todosKey = GlobalKey<TodosPageState>();
  String? _calendarSelection;
  DateTime _selected = dayOnly(DateTime.now());
  ScheduleStatus? _status;
  int _filterRevision = 0;
  static const _names = ['首页', '日历', '日程', '待办', '链接', '设置'];
  static const _icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.checklist_outlined,
    Icons.task_alt,
    Icons.link,
    Icons.settings_outlined,
  ];
  void _openCalendar(DateTime day) => setState(() {
    _selected = dayOnly(day);
    _page = 1;
  });
  void _openTodo(String id) {
    setState(() => _page = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _todosKey.currentState?.focusTask(id);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return AppBackground(
        settings: c.settings,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          bottomNavigationBar: MediaQuery.sizeOf(context).width < 600
              ? AppGlassPane(
                  settings: c.settings,
                  sidebar: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.appColors.border),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: _page == 1 && _calendarSelection != null
                              ? _calendarDetails(c)
                              : const SizedBox.shrink(),
                        ),
                        NavigationBar(
                          height: 68,
                          backgroundColor: Colors.transparent,
                          indicatorColor: context.appColors.selected,
                          selectedIndex: _page,
                          onDestinationSelected: (i) =>
                              setState(() => _page = i),
                          destinations: [
                            for (var i = 0; i < _names.length; i++)
                              NavigationDestination(
                                icon: Icon(_icons[i]),
                                label: _names[i],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) {
                final compact = box.maxWidth < 900;
                final narrow = box.maxWidth < 600;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow)
                      AppGlassPane(
                        settings: c.settings,
                        sidebar: true,
                        child: Container(
                          width: compact ? 68 : 184,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: context.appColors.border,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 0 : 20,
                                  28,
                                  compact ? 0 : 20,
                                  32,
                                ),
                                child: Row(
                                  mainAxisAlignment: compact
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      color: context.appColors.accent,
                                      size: 23,
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(width: 11),
                                      const Text(
                                        '日程表',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              for (var i = 0; i < _names.length; i++)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 7 : 12,
                                    0,
                                    compact ? 7 : 12,
                                    7,
                                  ),
                                  child: Semantics(
                                    selected: _page == i,
                                    button: true,
                                    label: _names[i],
                                    child: Material(
                                      color: _page == i
                                          ? context.appColors.selected
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      child: InkWell(
                                        onTap: () => setState(() => _page = i),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: compact ? 0 : 14,
                                            vertical: compact ? 10 : 13,
                                          ),
                                          child: compact
                                              ? Column(
                                                  children: [
                                                    Icon(
                                                      _icons[i],
                                                      size: 21,
                                                      color: _page == i
                                                          ? context
                                                                .appColors
                                                                .accent
                                                          : AppColors.muted,
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      _names[i],
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: _page == i
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                        color: _page == i
                                                            ? context
                                                                  .appColors
                                                                  .accent
                                                            : AppColors.muted,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    Icon(
                                                      _icons[i],
                                                      size: 20,
                                                      color: _page == i
                                                          ? context
                                                                .appColors
                                                                .accent
                                                          : AppColors.muted,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      _names[i],
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: _page == i
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                        color: _page == i
                                                            ? context
                                                                  .appColors
                                                                  .accent
                                                            : AppColors.muted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (!compact && !c.loading && c.error == null)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(24, 16, 12, 24),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.storage_outlined,
                                        size: 16,
                                        color: AppColors.muted,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '本地存储',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: AppGlassPane(
                        settings: c.settings,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: EdgeInsets.fromLTRB(
                                narrow ? 16 : 32,
                                narrow
                                    ? 10
                                    : _page == 0
                                    ? 16
                                    : 24,
                                narrow ? 16 : 32,
                                narrow
                                    ? 10
                                    : _page == 0
                                    ? 16
                                    : 20,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _names[_page],
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontSize: narrow ? 20 : 24),
                                  ),
                                  const Spacer(),
                                  if (_page < 4 && !(narrow && _page == 0))
                                    FilledButton.icon(
                                      onPressed: c.loading || c.error != null
                                          ? null
                                          : _page == 3
                                          ? () => openTodoEditor(context, c)
                                          : () => openEventEditor(
                                              context,
                                              c,
                                              date: _page == 1
                                                  ? _selected
                                                  : null,
                                            ),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: Text(
                                        _page == 3
                                            ? '新增待办'
                                            : narrow
                                            ? '新建'
                                            : '新建日程',
                                      ),
                                    ),
                                  if (!narrow && _page < 3) ...[
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      key: const ValueKey('desktop-new-todo'),
                                      onPressed: c.loading || c.error != null
                                          ? null
                                          : () => openTodoEditor(context, c),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('新建待办'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Divider(),
                            UpdatePanel(controller: c, compact: true),
                            if (c.dueReminders.isNotEmpty) _reminderBanner(c),
                            if (c.notificationError != null)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  c.notificationError!,
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            if (c.automationError != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                child: Text(
                                  c.automationError!,
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: c.loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : c.error != null
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              c.error!,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            OutlinedButton(
                                              onPressed: c.initialize,
                                              child: const Text('重试'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ScrollBoundaryFeedback(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        alignment: Alignment.topLeft,
                                        children:
                                            <Widget>[
                                                  Padding(
                                                    padding: EdgeInsets.all(
                                                      narrow ? 12 : 24,
                                                    ),
                                                    child: HomePage(
                                                      controller: c,
                                                      onCalendar: _openCalendar,
                                                      onTodo: _openTodo,
                                                      onSchedules: () =>
                                                          setState(() {
                                                            _page = 2;
                                                            _status = null;
                                                            _filterRevision++;
                                                          }),
                                                      onStatus: (status) =>
                                                          setState(() {
                                                            _status = status;
                                                            _filterRevision++;
                                                            _page = 2;
                                                          }),
                                                    ),
                                                  ),
                                                  SingleChildScrollView(
                                                    key: const PageStorageKey(
                                                      'calendar-scroll',
                                                    ),
                                                    padding: EdgeInsets.all(
                                                      narrow ? 12 : 28,
                                                    ),
                                                    child: CalendarPage(
                                                      key: _calendarKey,
                                                      active: _page == 1,
                                                      controller: c,
                                                      selectedDate: _selected,
                                                      onSelect: (d) => setState(
                                                        () => _selected =
                                                            dayOnly(d),
                                                      ),
                                                      onSelectionChanged: (event) {
                                                        if (mounted) {
                                                          setState(
                                                            () =>
                                                                _calendarSelection =
                                                                    event?.id,
                                                          );
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                  SingleChildScrollView(
                                                    key: const PageStorageKey(
                                                      'schedules-scroll',
                                                    ),
                                                    padding: EdgeInsets.all(
                                                      narrow ? 12 : 28,
                                                    ),
                                                    child: SchedulesPage(
                                                      controller: c,
                                                      initialStatus: _status,
                                                      filterRevision:
                                                          _filterRevision,
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: EdgeInsets.all(
                                                      narrow ? 12 : 28,
                                                    ),
                                                    child: TodosPage(
                                                      key: _todosKey,
                                                      controller: c,
                                                    ),
                                                  ),
                                                  if (c.link == null)
                                                    Padding(
                                                      padding: EdgeInsets.all(
                                                        narrow ? 12 : 28,
                                                      ),
                                                      child: const Text(
                                                        '当前验证环境未启用设备连接',
                                                      ),
                                                    )
                                                  else
                                                    SingleChildScrollView(
                                                      key: const PageStorageKey(
                                                        'link-scroll',
                                                      ),
                                                      padding: EdgeInsets.all(
                                                        narrow ? 12 : 28,
                                                      ),
                                                      child: LinkPage(
                                                        controller: c.link,
                                                      ),
                                                    ),
                                                  SingleChildScrollView(
                                                    key: const PageStorageKey(
                                                      'settings-scroll',
                                                    ),
                                                    padding: EdgeInsets.all(
                                                      narrow ? 12 : 28,
                                                    ),
                                                    child: SettingsPage(
                                                      controller: c,
                                                      onManageLinks: () =>
                                                          setState(
                                                            () => _page = 4,
                                                          ),
                                                    ),
                                                  ),
                                                ].indexed
                                                .map(
                                                  (item) => Offstage(
                                                    offstage: item.$1 != _page,
                                                    child: Semantics(
                                                      container: true,
                                                      explicitChildNodes: true,
                                                      child: TickerMode(
                                                        enabled:
                                                            item.$1 == _page,
                                                        child: item.$2,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
  Widget _calendarDetails(AppController c) {
    final event = c.calendarEvents
        .where((e) => e.id == _calendarSelection)
        .firstOrNull;
    if (event == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('mobile-calendar-details'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  eventTimeText(event, c.settings, withDate: true),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (event.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      event.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭日程详情',
            onPressed: () => _calendarKey.currentState?.clearSelection(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _reminderBanner(AppController c) {
    final e = c.dueReminders.first;
    return Semantics(
      liveRegion: true,
      child: Container(
        color: context.appColors.selected,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 20,
              color: context.appColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${e.isTodo ? '待办' : '日程'}提醒：${e.title}${c.dueReminders.length > 1 ? '（另${c.dueReminders.length - 1}项）' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(40, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => openEventEditor(context, c, event: e),
              child: const Text('查看'),
            ),
            IconButton(
              tooltip: '关闭此提醒',
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: () => c.dismissReminder(e),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
