import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../domain/time_axis.dart';
import '../domain/calendar_layout.dart';
import 'components.dart';
import 'item_context_menu.dart';
import 'event_editor.dart';
import 'theme.dart';
import 'motion.dart';
import 'calendar_blocks.dart';
import 'scroll_feedback.dart';

enum CalendarView { day, week, month }

class CalendarPage extends StatefulWidget {
  final AppController controller;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<ScheduleEvent?>? onSelectionChanged;
  final bool active;
  const CalendarPage({
    super.key,
    required this.controller,
    required this.selectedDate,
    required this.onSelect,
    this.onSelectionChanged,
    this.active = true,
  });
  @override
  State<CalendarPage> createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  CalendarView _view = CalendarView.month;
  late DateTime _focusDate, _firstVisible, _monthDate;
  late final PageController _months;
  final _timeScroll = ScrollController(keepScrollOffset: false);
  final _daysScroll = ScrollController(keepScrollOffset: false),
      _headerScroll = ScrollController(keepScrollOffset: false);
  final _timeViewport = GlobalKey();
  final Object _tapGroup = Object();
  late final AnimationController _popoverAnimation;
  OverlayEntry? _popover;
  Offset? _outsideOrigin;
  int? _outsidePointer;
  double _outsideTravel = 0;
  int _selectionRevision = 0;
  bool _linkingScroll = false,
      _readyDays = false,
      _moving = false,
      _mobileDrag = false,
      _pinching = false;
  double _dayWidth = 0,
      _hourHeight = 60,
      _pinchDistance = 1,
      _pinchHeight = 60,
      _pinchOffset = 0,
      _pinchAnchor = 0;
  final Map<int, Offset> _pointers = {};
  String? _selectedId, _selectionBlock, _axisDate;
  ScheduleEvent? _dragging;
  Timer? _dragAutoTimer;
  int _navigationRevision = 0;
  bool _navigating = false;
  Offset? _dragPointer;
  CalendarEditMode _editMode = CalendarEditMode.move;
  Offset _dragOffset = Offset.zero;
  bool get _phone => MediaQuery.sizeOf(context).width < 600;
  bool get _locked => widget.controller.settings.calendarLocked;
  int get _zoom => hourHeights.indexed
      .reduce(
        (a, b) =>
            (a.$2 - _hourHeight).abs() < (b.$2 - _hourHeight).abs() ? a : b,
      )
      .$1;
  int get _gridMinutes => gridMinutes[_zoom];
  static final _epoch = DateTime.utc(1901);
  static final _last = DateTime(2099, 12, 31);
  int _dayIndex(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).difference(_epoch).inDays;
  DateTime _dayAt(int index) {
    final d = _epoch.add(Duration(days: index));
    return DateTime(d.year, d.month, d.day);
  }

  int _monthIndex(DateTime d) => (d.year - 1901) * 12 + d.month - 1;
  DateTime _monthAt(int index) => DateTime(1901, index + 1);
  DateTime _weekStart(DateTime d) => DateTime(
    d.year,
    d.month,
    d.day -
        (widget.controller.settings.mondayFirst
            ? d.weekday - 1
            : d.weekday % 7),
  );
  ScheduleEvent? get _selectedEvent => widget.controller.calendarEvents
      .where((e) => e.id == _selectedId)
      .firstOrNull;
  Duration get _travel => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 440);
  @override
  void initState() {
    super.initState();
    _focusDate = dayOnly(widget.selectedDate);
    _firstVisible = _weekStart(_focusDate);
    _monthDate = DateTime(_focusDate.year, _focusDate.month);
    _months = PageController(initialPage: _monthIndex(_monthDate));
    _popoverAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _daysScroll.addListener(_daysChanged);
    _headerScroll.addListener(_headerChanged);
    _timeScroll.addListener(_axisScrolled);
  }

  @override
  void didUpdateWidget(CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (!widget.active) {
        _cancelDrag();
        unawaited(_hidePopover());
      }
      _readyDays = false;
      _axisDate = null;
      if (widget.active && _view == CalendarView.month) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _months.hasClients) {
            _months.jumpToPage(_monthIndex(_monthDate));
          }
        });
      }
    }
    if (!sameDay(widget.selectedDate, _focusDate)) {
      _focusDate = dayOnly(widget.selectedDate);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_goTo(_focusDate));
      });
    }
    if (_locked && _selectedId != null ||
        _selectedId != null && _selectedEvent == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) clearSelection();
      });
    }
  }

  void _axisScrolled() {
    if (_popover != null) unawaited(_hidePopover());
  }

  void _outsideDown(PointerDownEvent event) {
    if (_selectedId == null || _outsidePointer != null) return;
    _outsidePointer = event.pointer;
    _outsideOrigin = event.position;
    _outsideTravel = 0;
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _outsideRoute,
    );
  }

  void _outsideRoute(PointerEvent event) {
    if (event is PointerMoveEvent) _outsideTravel += event.delta.distance;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      final tap =
          event is PointerUpEvent &&
          _outsideTravel < 9 &&
          (event.position - _outsideOrigin!).distance < 9;
      GestureBinding.instance.pointerRouter.removeRoute(
        event.pointer,
        _outsideRoute,
      );
      _outsidePointer = null;
      if (tap && mounted) clearSelection();
    }
  }

  Future<void> _revealSelected(
    ScheduleEvent event,
    BuildContext anchor,
    int revision,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 190));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !anchor.mounted || revision != _selectionRevision) return;
    await Scrollable.ensureVisible(
      anchor,
      duration: _travel,
      alignment: .45,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    if (!mounted || !anchor.mounted || revision != _selectionRevision) return;
    // Nested ensureVisible computes its outer target before the inner scroll
    // finishes. At the end of the day the details can still clip the block, so
    // correct the outer viewport against the final, reduced body geometry.
    final page = Scrollable.maybeOf(context, axis: Axis.vertical);
    final viewport = page?.context.findRenderObject() as RenderBox?;
    final target = anchor.findRenderObject() as RenderBox?;
    if (page != null && viewport != null && target != null) {
      final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
      final block = target.localToGlobal(Offset.zero) & target.size;
      final delta = block.height > visible.height - 16
          ? block.top - visible.top - 8
          : block.bottom > visible.bottom - 8
          ? block.bottom - visible.bottom + 8
          : block.top < visible.top + 8
          ? block.top - visible.top - 8
          : 0.0;
      if (delta.abs() > .5) {
        final destination = (page.position.pixels + delta).clamp(
          page.position.minScrollExtent,
          page.position.maxScrollExtent,
        );
        if (_travel == Duration.zero) {
          page.position.jumpTo(destination);
        } else {
          await page.position.animateTo(
            destination,
            duration: _travel,
            curve: Curves.easeInOutCubic,
          );
        }
      }
    }
    if (!mounted || !anchor.mounted || revision != _selectionRevision) return;
    final box = anchor.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      _showPopover(event, box.localToGlobal(Offset.zero) & box.size);
    }
  }

  void _scrollPageBy(double amount) {
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position != null && position.hasContentDimensions) {
      final old = position.pixels;
      position.jumpTo(
        (old + amount).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      amount -= position.pixels - old;
    }
    if (amount.abs() > .1) ScrollBoundaryFeedback.pulse(context, amount);
  }

  void _scrollTimeBy(double amount) {
    final old = _timeScroll.offset;
    _timeScroll.jumpTo(
      (old + amount).clamp(0, _timeScroll.position.maxScrollExtent),
    );
    _scrollPageBy(amount - (_timeScroll.offset - old));
  }

  bool _timeOverscroll(OverscrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _pinching || _dragging != null) {
      return false;
    }
    _scrollPageBy(n.overscroll);
    return true;
  }

  List<Widget> _dragPreview(DateTime day, double width) {
    final event = _dragging!;
    final range = _rangeFor(event);
    final next = DateTime(day.year, day.month, day.day + 1);
    if (!range.$1.isBefore(next) ||
        range.$2.isBefore(day) ||
        range.$2 == day && range.$1 != range.$2) {
      return [];
    }
    final start = range.$1.isBefore(day)
        ? 0.0
        : range.$1.difference(day).inSeconds / 60;
    final end = range.$2.isAfter(next)
        ? 1440.0
        : range.$2.difference(day).inSeconds / 60;
    return [
      Positioned(
        key: ValueKey('drag-preview-${dateKey(day)}'),
        left: 2,
        width: width - 4,
        top: start * _hourHeight / 60,
        height: event.isPoint
            ? 26
            : math.max(12, (end - start) * _hourHeight / 60),
        child: IgnorePointer(
          child: event.isPoint
              ? PointEventMarker(
                  color: Color(event.displayColor).withValues(alpha: .35),
                  phone: _phone,
                )
              : ColoredBox(
                  color: Color(event.displayColor).withValues(alpha: .35),
                ),
        ),
      ),
    ];
  }

  void _daysChanged() {
    if (!_readyDays || _linkingScroll || _dayWidth <= 0) return;
    _linkingScroll = true;
    if (_headerScroll.hasClients) {
      _headerScroll.jumpTo(
        _daysScroll.offset.clamp(0, _headerScroll.position.maxScrollExtent),
      );
    }
    _linkingScroll = false;
    final day = _dayAt((_daysScroll.offset / _dayWidth + .00001).floor());
    if (!_navigating && !sameDay(day, _firstVisible)) {
      setState(() => _firstVisible = day);
    }
    if (_popover != null) unawaited(_hidePopover());
  }

  void _headerChanged() {
    if (!_readyDays || _linkingScroll || !_daysScroll.hasClients) return;
    _linkingScroll = true;
    _daysScroll.jumpTo(
      _headerScroll.offset.clamp(0, _daysScroll.position.maxScrollExtent),
    );
    _linkingScroll = false;
    final day = _dayAt((_daysScroll.offset / _dayWidth + .00001).floor());
    if (!_navigating && !sameDay(day, _firstVisible)) {
      setState(() => _firstVisible = day);
    }
  }

  void _selectDate(DateTime day) {
    if (_locked) return;
    clearSelection();
    setState(() => _focusDate = dayOnly(day));
    widget.onSelect(_focusDate);
  }

  void clearSelection() {
    _selectionRevision++;
    _cancelDrag();
    unawaited(_hidePopover());
    if (!mounted || _selectedId == null) return;
    setState(() {
      _selectedId = null;
      _selectionBlock = null;
      _mobileDrag = false;
    });
    widget.onSelectionChanged?.call(null);
  }

  Future<void> _hidePopover() async {
    final old = _popover;
    if (old == null) return;
    try {
      await _popoverAnimation.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (_popover == old) {
      old.remove();
      old.dispose();
      _popover = null;
    }
  }

  void _showPopover(ScheduleEvent event, Rect anchor) {
    _popover?.remove();
    _popover?.dispose();
    final size = MediaQuery.sizeOf(context);
    final left = (anchor.center.dx - 126)
        .clamp(8.0, math.max(8.0, size.width - 260))
        .toDouble();
    final top = (anchor.bottom + 8)
        .clamp(
          MediaQuery.paddingOf(context).top + 8,
          math.max(80.0, size.height - 240),
        )
        .toDouble();
    _popover = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        width: 252,
        child: TapRegion(
          groupId: _tapGroup,
          child: FadeTransition(
            opacity: _popoverAnimation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .94, end: 1).animate(
                CurvedAnimation(
                  parent: _popoverAnimation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              alignment: Alignment.topCenter,
              child: Material(
                color: context.appColors.surface,
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: .15),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() => _mobileDrag = true);
                            unawaited(_hidePopover());
                          },
                          icon: const Icon(Icons.open_with, size: 16),
                          label: const Text('拖动'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            unawaited(_hidePopover());
                            openEventEditor(
                              context,
                              widget.controller,
                              event: event,
                            );
                          },
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('编辑'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            await _hidePopover();
                            if (mounted) {
                              await deleteEvent(
                                context,
                                widget.controller,
                                event,
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: AppColors.danger,
                          ),
                          label: const Text(
                            '删除',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_popover!);
    _popoverAnimation.forward(from: 0);
  }

  void _tapEvent(
    ScheduleEvent event,
    String block,
    BuildContext blockContext, {
    bool longPress = false,
  }) {
    if (_locked || _moving || _pinching) return;
    if (_selectedId == event.id && !longPress) {
      unawaited(_hidePopover());
      openEventEditor(context, widget.controller, event: event);
      return;
    }
    setState(() {
      _selectedId = event.id;
      _selectionBlock = block;
      _mobileDrag = false;
    });
    widget.onSelectionChanged?.call(event);
    if (_phone) {
      if (widget.onSelectionChanged == null) {
        final box = blockContext.findRenderObject() as RenderBox?;
        if (box != null) {
          _showPopover(event, box.localToGlobal(Offset.zero) & box.size);
        }
      } else {
        final revision = ++_selectionRevision;
        unawaited(_revealSelected(event, blockContext, revision));
      }
    }
  }

  void _startDrag(
    ScheduleEvent event,
    CalendarEditMode mode,
    BuildContext blockContext,
  ) {
    if (_locked || _pinching) return;
    unawaited(_hidePopover());
    setState(() {
      _dragging = event;
      _editMode = mode;
      _dragOffset = Offset.zero;
    });
    _dragAutoTimer?.cancel();
    _dragAutoTimer = Timer.periodic(
      const Duration(milliseconds: 30),
      (_) => _dragAutoStep(),
    );
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_dragging == null || _pinching) return;
    _dragPointer = details.globalPosition;
    _dragOffset += details.delta;
    setState(() {});
  }

  void _dragAutoStep() {
    if (_dragging == null || _dragPointer == null || !mounted) return;
    final render =
        _timeViewport.currentContext?.findRenderObject() as RenderBox?;
    if (render == null) return;
    final previousOffset = _dragOffset;
    final local = render.globalToLocal(_dragPointer!);
    if (_daysScroll.hasClients) {
      final old = _daysScroll.offset;
      final amount = local.dx < (_phone ? 56 : 64)
          ? -10.0
          : local.dx > render.size.width - 24
          ? 10.0
          : 0.0;
      if (amount != 0) {
        _daysScroll.jumpTo(
          (old + amount).clamp(0, _daysScroll.position.maxScrollExtent),
        );
        _dragOffset += Offset(_daysScroll.offset - old, 0);
      }
    }
    if (_timeScroll.hasClients && !_dragging!.allDay) {
      final y = local.dy;
      final old = _timeScroll.offset;
      final amount = y < 30
          ? -12.0
          : y > render.size.height - 30
          ? 12.0
          : 0.0;
      if (amount != 0) {
        _timeScroll.jumpTo(
          (old + amount).clamp(0, _timeScroll.position.maxScrollExtent),
        );
        _dragOffset += Offset(0, _timeScroll.offset - old);
      }
    }
    if (_dragOffset != previousOffset) setState(() {});
  }

  (DateTime, DateTime) _rangeFor(ScheduleEvent e) {
    if (_editMode == CalendarEditMode.move) {
      final start = e.allDay
          ? DateTime(
              e.start.year,
              e.start.month,
              e.start.day + (_dragOffset.dx / _dayWidth).round(),
            )
          : draggedStart(
              e.start,
              dx: _dragOffset.dx,
              dy: _dragOffset.dy,
              dayWidth: _dayWidth,
              hourHeight: _hourHeight,
              step: _gridMinutes,
              snap: widget.controller.settings.snapToGrid,
            );
      return (start, start.add(e.end.difference(e.start)));
    }
    final base = _editMode == CalendarEditMode.start ? e.start : e.end;
    final resolution = widget.controller.settings.snapToGrid ? _gridMinutes : 1;
    final raw =
        base.hour * 60 + base.minute + _dragOffset.dy * 60 / _hourHeight;
    final at = DateTime(
      base.year,
      base.month,
      base.day + (_dragOffset.dx / _dayWidth).round(),
      0,
      (raw / resolution).round() * resolution,
    );
    return _editMode == CalendarEditMode.start
        ? (at.isAfter(e.end) ? e.end : at, e.end)
        : (e.start, at.isBefore(e.start) ? e.start : at);
  }

  void _cancelDrag() {
    _dragAutoTimer?.cancel();
    _dragAutoTimer = null;
    _dragPointer = null;
    _dragging = null;
    _dragOffset = Offset.zero;
  }

  void _abortDrag() {
    if (!mounted) return;
    setState(_cancelDrag);
  }

  Future<void> _finishDrag() async {
    final event = _dragging;
    if (event == null) return;
    final range = _rangeFor(event);
    final mode = _editMode;
    setState(() {
      _cancelDrag();
      _moving = true;
      _mobileDrag = false;
    });
    try {
      if (range.$1 == event.start && range.$2 == event.end) return;
      var entire = false;
      if (event.seriesId != null) {
        final answer = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(mode == CalendarEditMode.move ? '移动重复日程' : '调整重复日程'),
            content: Text(
              '${dateKey(range.$1)} ${clockText(range.$1)}—${clockText(range.$2)}\n应用于本次还是全部？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('仅本次'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('全部'),
              ),
            ],
          ),
        );
        if (answer == null) return;
        entire = answer;
      }
      await widget.controller.moveEvent(
        event,
        range.$1,
        newEnd: range.$2,
        entireSeries: entire,
      );
      widget.onSelectionChanged?.call(_selectedEvent);
      if (mounted) showMessage(context, event.isTodo ? '待办截止时间已更新' : '日程时间已更新');
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is FormatException ? e.message.toString() : '调整失败，原时间已保留。',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  void _setHeight(double height, double anchor) {
    final next = height.clamp(hourHeights.first, hourHeights.last),
        old = _hourHeight;
    if ((next - old).abs() < .1) return;
    final offset = (_timeScroll.hasClients ? _timeScroll.offset : 0) + anchor;
    setState(() => _hourHeight = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _timeScroll.hasClients) {
        _timeScroll.jumpTo(
          (offset * next / old - anchor).clamp(
            0,
            _timeScroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _buttonZoom(int delta) => _setHeight(
    hourHeights[(_zoom + delta).clamp(0, hourHeights.length - 1)],
    0,
  );
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _dragging != null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final e = signal as PointerScrollEvent;
      if (HardwareKeyboard.instance.isShiftPressed) {
        _setHeight(
          hourHeights[(_zoom + (e.scrollDelta.dy < 0 ? 1 : -1)).clamp(
            0,
            hourHeights.length - 1,
          )],
          event.localPosition.dy -
              (_timeScroll.hasClients ? _timeScroll.offset : 0),
        );
      } else if (e.scrollDelta.dx != 0 && _daysScroll.hasClients) {
        _daysScroll.jumpTo(
          (_daysScroll.offset + e.scrollDelta.dx).clamp(
            0,
            _daysScroll.position.maxScrollExtent,
          ),
        );
      } else if (_timeScroll.hasClients) {
        _scrollTimeBy(e.scrollDelta.dy);
      }
    });
  }

  void _pointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _cancelDrag();
      unawaited(_hidePopover());
      final points = _pointers.values.toList();
      final box =
          _timeViewport.currentContext?.findRenderObject() as RenderBox?;
      _pinchDistance = (points[0] - points[1]).distance;
      _pinchHeight = _hourHeight;
      _pinchOffset = _timeScroll.hasClients ? _timeScroll.offset : 0;
      _pinchAnchor = box == null
          ? 0
          : box
                .globalToLocal((points[0] + points[1]) / 2)
                .dy
                .clamp(0, box.size.height);
      setState(() => _pinching = true);
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_pinching || _pointers.length != 2 || _pinchDistance < 1) return;
    final points = _pointers.values.toList();
    final height =
        (_pinchHeight * (points[0] - points[1]).distance / _pinchDistance)
            .clamp(hourHeights.first, hourHeights.last);
    setState(() => _hourHeight = height);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _timeScroll.hasClients) {
        _timeScroll.jumpTo(
          ((_pinchOffset + _pinchAnchor) * height / _pinchHeight - _pinchAnchor)
              .clamp(0, _timeScroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) setState(() => _pinching = false);
  }

  Future<void> _goTo(DateTime day) async {
    clearSelection();
    if (day.year < 1901 || day.year > 2099) return;
    final revision = ++_navigationRevision;
    _navigating = true;
    setState(() => _focusDate = dayOnly(day));
    widget.onSelect(_focusDate);
    if (_view == CalendarView.month) {
      _monthDate = DateTime(day.year, day.month);
      if (_months.hasClients) {
        await _months.animateToPage(
          _monthIndex(day),
          duration: _navigationDuration(
            (_monthIndex(day) - (_months.page ?? _monthIndex(day)))
                .abs()
                .toDouble(),
          ),
          curve: Curves.easeInOutCubic,
        );
      }
    } else {
      final target = _view == CalendarView.week
          ? _weekStart(day)
          : dayOnly(day);
      _firstVisible = target;
      if (_readyDays && _daysScroll.hasClients) {
        await _daysScroll.animateTo(
          (_dayIndex(target) * _dayWidth).clamp(
            0,
            _daysScroll.position.maxScrollExtent,
          ),
          duration: _navigationDuration(
            ((_dayIndex(target) * _dayWidth) - _daysScroll.offset).abs() /
                math.max(1, _daysScroll.position.viewportDimension),
          ),
          curve: Curves.easeInOutCubic,
        );
      }
    }
    if (mounted && revision == _navigationRevision) {
      setState(() {
        _navigating = false;
        _axisDate = null;
      });
    }
  }

  Duration _navigationDuration(double distance) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(
          milliseconds: (180 + 260 * math.sqrt(distance)).round().clamp(
            180,
            700,
          ),
        );

  void _move(int delta) {
    final first = _weekStart(_firstVisible);
    final day = _view == CalendarView.month
        ? DateTime(_monthDate.year, _monthDate.month + delta, 1)
        : _view == CalendarView.week
        ? DateTime(first.year, first.month, first.day + delta * 7)
        : DateTime(
            _firstVisible.year,
            _firstVisible.month,
            _firstVisible.day + delta,
          );
    unawaited(_goTo(day));
  }

  void _changeView(CalendarView view) {
    _navigationRevision++;
    _navigating = false;
    clearSelection();
    setState(() {
      if (_view == CalendarView.month &&
          (_focusDate.month != _monthDate.month ||
              _focusDate.year != _monthDate.year)) {
        _focusDate = _monthDate;
      }
      _view = view;
      _readyDays = false;
      _dayWidth = 0;
      _axisDate = null;
      _firstVisible = view == CalendarView.week
          ? _weekStart(_focusDate)
          : _focusDate;
      _monthDate = DateTime(_focusDate.year, _focusDate.month);
    });
    if (view == CalendarView.month) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _months.hasClients) {
          _months.jumpToPage(_monthIndex(_monthDate));
        }
      });
    }
  }

  String get _title {
    if (_view == CalendarView.month) {
      return '${_monthDate.year}年${_monthDate.month}月';
    }
    if (_view == CalendarView.day) {
      return '${_firstVisible.year}年${_firstVisible.month}月${_firstVisible.day}日';
    }
    final end = DateTime(
      _firstVisible.year,
      _firstVisible.month,
      _firstVisible.day + 6,
    );
    return '${_firstVisible.year}年${_firstVisible.month}月${_firstVisible.day}日—${end.month}月${end.day}日';
  }

  @override
  void dispose() {
    _dragAutoTimer?.cancel();
    if (_outsidePointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(
        _outsidePointer!,
        _outsideRoute,
      );
    }
    _popover?.remove();
    _popover?.dispose();
    _popoverAnimation.dispose();
    _months.dispose();
    _daysScroll.dispose();
    _headerScroll.dispose();
    _timeScroll.dispose();
    super.dispose();
  }

  Widget _toolbar() {
    final modes = SegmentedButton<CalendarView>(
      showSelectedIcon: false,
      segments: [
        if (_phone)
          const ButtonSegment(value: CalendarView.day, label: Text('日')),
        const ButtonSegment(value: CalendarView.week, label: Text('周')),
        const ButtonSegment(value: CalendarView.month, label: Text('月')),
      ],
      selected: {
        _view == CalendarView.day && !_phone ? CalendarView.week : _view,
      },
      onSelectionChanged: _moving ? null : (v) => _changeView(v.first),
    );
    final unit = _view == CalendarView.month
        ? '月'
        : _view == CalendarView.week
        ? '周'
        : '天';
    final arrows = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.input),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final delta in [-1, 1])
            IconButton(
              tooltip: (delta < 0 ? '上一' : '下一') + unit,
              constraints: const BoxConstraints.tightFor(width: 34, height: 36),
              padding: EdgeInsets.zero,
              onPressed: _moving ? null : () => _move(delta),
              icon: Icon(
                delta < 0 ? Icons.chevron_left : Icons.chevron_right,
                size: 21,
              ),
            ),
        ],
      ),
    );
    final today = OutlinedButton(
      onPressed: _moving ? null : () => _goTo(dayOnly(widget.controller.now)),
      child: const Text('今天'),
    );
    final lock = TextButton.icon(
      key: const ValueKey('calendar-lock'),
      onPressed: _moving
          ? null
          : () => runAction(context, () async {
              clearSelection();
              await widget.controller.updateSettings(
                widget.controller.settings.copyWith(calendarLocked: !_locked),
              );
            }),
      icon: Icon(
        _locked ? Icons.lock_outline : Icons.lock_open_outlined,
        size: 18,
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 40),
      ),
      label: Text(
        _locked ? '不可选中' : '可选中',
        style: const TextStyle(fontSize: 12),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phone) ...[
          Row(
            children: [
              Expanded(child: modes),
              const SizedBox(width: 14),
              today,
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              arrows,
            ],
          ),
        ] else
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 14),
                  arrows,
                  const SizedBox(width: 8),
                  today,
                  const SizedBox(width: 8),
                  lock,
                ],
              ),
              modes,
            ],
          ),
        if (_view != CalendarView.month)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text(
                  '分度 $_gridMinutes分钟',
                  key: const ValueKey('time-grid-resolution'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 10),
                for (final delta in [-1, 1])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 32,
                      height: 34,
                      child: IconButton.outlined(
                        tooltip: delta < 0 ? '缩小时间轴' : '放大时间轴',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed:
                            _dragging != null ||
                                (_zoom == 0 && delta < 0) ||
                                (_zoom == hourHeights.length - 1 && delta > 0)
                            ? null
                            : () => _buttonZoom(delta),
                        icon: Icon(
                          delta < 0 ? Icons.remove : Icons.add,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                if (!_phone)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      'Shift＋滚轮缩放',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                if (_phone) ...[const Spacer(), lock],
              ],
            ),
          ),
        if (_phone && _view == CalendarView.month)
          Align(alignment: Alignment.centerRight, child: lock),
        if (_phone && _mobileDrag)
          Text(
            '拖动色块或上下边界',
            style: TextStyle(fontSize: 12, color: context.appColors.accent),
          ),
        if (_phone || _selectedEvent != null && !_locked)
          SizedBox(
            height: _phone
                ? 64 * math.max(1, MediaQuery.textScalerOf(context).scale(1))
                : null,
            child: _selectedEvent == null || _locked
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedEvent!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (_selectedEvent!.notes.isNotEmpty)
                                Text(
                                  _selectedEvent!.notes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('calendar-delete-selected'),
                          onPressed: () => deleteEvent(
                            context,
                            widget.controller,
                            _selectedEvent!,
                          ),
                          icon: const Icon(Icons.delete_outline, size: 17),
                          label: const Text('删除'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('calendar-edit-selected'),
                          onPressed: () => openEventEditor(
                            context,
                            widget.controller,
                            event: _selectedEvent!,
                          ),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          key: const ValueKey('calendar-complete-selected'),
                          onPressed: () => completeEvent(
                            context,
                            widget.controller,
                            _selectedEvent!,
                          ),
                          child: Text(_selectedEvent!.completed ? '未完成' : '完成'),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    if (!_phone && _view == CalendarView.day) {
      _view = CalendarView.week;
      _readyDays = false;
      _firstVisible = _weekStart(_focusDate);
    }
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: _outsideDown,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            clearSelection();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ItemContextMenu(
          enabled: !_locked,
          controller: widget.controller,
          date: _focusDate,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: clearSelection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(),
                const SizedBox(height: 8),
                if (_view == CalendarView.month)
                  LayoutBuilder(
                    builder: (context, box) {
                      final month = _monthPager();
                      return !_phone && box.maxWidth >= 1020
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: month),
                                const SizedBox(width: 20),
                                SizedBox(width: 280, child: _dayDetails()),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                month,
                                const SizedBox(height: 16),
                                _dayDetails(),
                              ],
                            );
                    },
                  )
                else
                  _timeGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthPager() {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final cellHeight = (_phone ? 76.0 : 112.0) * math.max(1, scale);
    return Surface(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: cellHeight * 6 + 42,
        child: ScrollConfiguration(
          behavior: const _CalendarScrollBehavior(),
          child: PageView.builder(
            key: const ValueKey('month-pager'),
            controller: _months,
            itemCount: 199 * 12,
            onPageChanged: (index) {
              if (_navigating) return;
              final month = _monthAt(index);
              if (!sameDay(month, _monthDate)) {
                setState(() => _monthDate = month);
              }
              if (!_phone) clearSelection();
            },
            itemBuilder: (context, index) {
              final month = _monthAt(index);
              final first = DateTime(month.year, month.month);
              final offset = widget.controller.settings.mondayFirst
                  ? first.weekday - 1
                  : first.weekday % 7;
              final start = DateTime(first.year, first.month, 1 - offset);
              final labels = widget.controller.settings.mondayFirst
                  ? ['一', '二', '三', '四', '五', '六', '日']
                  : ['日', '一', '二', '三', '四', '五', '六'];
              return Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        for (final label in labels)
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var row = 0; row < 6; row++)
                    Row(
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: _monthCell(
                              DateTime(
                                start.year,
                                start.month,
                                start.day + row * 7 + col,
                              ),
                              month,
                              cellHeight,
                              col < 6,
                              row < 5,
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _monthCell(
    DateTime day,
    DateTime month,
    double height,
    bool right,
    bool bottom,
  ) {
    final c = widget.controller,
        info = widget.controller.calendar.info(day),
        events = widget.controller.onDay(day);
    final today = sameDay(day, c.now),
        selected = sameDay(day, _focusDate),
        inMonth = day.month == month.month;
    return Semantics(
      label: '${dateKey(day)} ${info.lunar} ${events.length}项日程',
      selected: selected,
      child: GestureDetector(
        onTap: _locked || day.year < 1901 || day.year > 2099
            ? null
            : () => _selectDate(day),
        onDoubleTap: _locked || day.year < 1901 || day.year > 2099
            ? null
            : () => openEventEditor(context, c, date: day),
        child: Container(
          height: height,
          padding: EdgeInsets.all(_phone ? 4 : 8),
          decoration: BoxDecoration(
            color: selected
                ? context.appColors.selected.withValues(alpha: .65)
                : !inMonth
                ? context.appColors.canvas
                : null,
            border: Border(
              top: BorderSide(color: context.appColors.border),
              right: right
                  ? BorderSide(color: context.appColors.border)
                  : BorderSide.none,
              bottom: bottom
                  ? BorderSide.none
                  : BorderSide(color: context.appColors.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: today ? context.appColors.accent : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected || today
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: today
                            ? Colors.white
                            : inMonth
                            ? AppColors.text
                            : AppColors.muted,
                      ),
                    ),
                  ),
                  if (info.holiday != null)
                    Text(
                      info.holiday!.isOffDay ? '休' : '班',
                      style: TextStyle(
                        fontSize: 10,
                        color: info.holiday!.isOffDay
                            ? context.appColors.accent
                            : AppColors.warning,
                      ),
                    ),
                ],
              ),
              if (c.settings.showLunar)
                Text(
                  info.smallLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _phone ? 10 : 11,
                    color:
                        info.solarTerm.isNotEmpty || info.festivals.isNotEmpty
                        ? context.appColors.accent
                        : AppColors.muted,
                  ),
                ),
              if (_phone && events.isNotEmpty)
                Text(
                  '${events.length}项',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.accent,
                  ),
                ),
              if (!_phone)
                for (final event in events.take(2))
                  Builder(
                    builder: (blockContext) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: ItemContextMenu(
                        controller: widget.controller,
                        event: event,
                        date: day,
                        enabled: !_locked,
                        child: GestureDetector(
                          onTap: _locked
                              ? null
                              : () => _tapEvent(
                                  event,
                                  'month-${event.id}-${dateKey(day)}',
                                  blockContext,
                                ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _dragging?.id == event.id
                                  ? Colors.transparent
                                  : Color(event.displayColor),
                              border: Border.all(
                                color: _selectedId == event.id
                                    ? context.appColors.accent
                                    : context.appColors.canvas,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: blockText(event.displayColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              if (!_phone && events.length > 2)
                Text(
                  '另${events.length - 2}项',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayDetails() {
    final c = widget.controller,
        info = widget.controller.calendar.info(_focusDate),
        events = widget.controller.onDay(_focusDate);
    return Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_focusDate.month}月${_focusDate.day}日 ${info.week}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '农历${info.lunar}',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          DayMarkers(info),
          if (!info.holidayYearKnown)
            const Text(
              '本年度法定节假日数据尚未收录',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          const SizedBox(height: 8),
          const Divider(),
          if (events.isEmpty) const EmptyState('这天没有日程'),
          for (final event in events)
            Builder(
              builder: (blockContext) => AbsorbPointer(
                absorbing: _locked,
                child: EventRow(
                  event: event,
                  controller: c,
                  onEdit: _locked
                      ? () {}
                      : () => _tapEvent(
                          event,
                          'detail-${event.id}',
                          blockContext,
                        ),
                ),
              ),
            ),
          if (!_locked)
            OutlinedButton.icon(
              onPressed: () => openEventEditor(context, c, date: _focusDate),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加日程'),
            ),
        ],
      ),
    );
  }

  Widget _timeGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final count = _view == CalendarView.day ? 1 : 7;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final axisWidth = _phone ? 40.0 : 48.0 * math.max(1, scale);
      // Binary-exact extents avoid accumulated floating-point drift across 199 years.
      final width =
          (((constraints.maxWidth - axisWidth) / count) * 64).floorToDouble() /
          64;
      if ((width - _dayWidth).abs() > .1 || !_readyDays) {
        _dayWidth = width;
        _readyDays = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !_daysScroll.hasClients ||
              !_headerScroll.hasClients) {
            return;
          }
          final at = (_dayIndex(_firstVisible) * width)
              .clamp(0, _daysScroll.position.maxScrollExtent)
              .toDouble();
          _daysScroll.jumpTo(at);
          _headerScroll.jumpTo(
            at.clamp(0, _headerScroll.position.maxScrollExtent),
          );
          _readyDays = true;
        });
      }
      final axisKey = '${dateKey(_focusDate)}-${_view.name}';
      if (_axisDate != axisKey) {
        _axisDate = axisKey;
        final timed =
            widget.controller.onDay(_focusDate).where((e) => !e.allDay).toList()
              ..sort((a, b) => a.start.compareTo(b.start));
        final hour = sameDay(_focusDate, widget.controller.now)
            ? widget.controller.now.hour
            : timed.isEmpty
            ? 9
            : timed.first.start.hour;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _timeScroll.hasClients) {
            _timeScroll.jumpTo(
              (math.max(0, hour - 1) * _hourHeight).clamp(
                0,
                _timeScroll.position.maxScrollExtent,
              ),
            );
          }
        });
      }
      final allDayRows = List.generate(
        count,
        (i) => widget.controller
            .onDay(
              DateTime(
                _firstVisible.year,
                _firstVisible.month,
                _firstVisible.day + i,
              ),
            )
            .where((e) => e.allDay)
            .length,
      ).fold<int>(0, math.max);
      final headerHeight =
          (_phone ? 44.0 : 58.0) * math.max(1, scale) +
          math.min(allDayRows, 3) * (_phone ? 12 : 26);
      final viewportHeight = _phone
          ? (MediaQuery.sizeOf(context).height -
                    320 -
                    math.max(0, headerHeight - 44))
                .clamp(180.0, 560.0)
          : (MediaQuery.sizeOf(context).height - 280).clamp(200.0, 900.0);
      final physics = _pinching
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics();
      if (_zoom == 0) {
        _hourHeight = math.min(hourHeights.first, (viewportHeight - 28) / 24);
      }
      final itemCount = _dayIndex(_last) + 1;
      return Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: Surface(
          padding: EdgeInsets.zero,
          child: ScrollConfiguration(
            behavior: const _CalendarScrollBehavior(),
            child: Column(
              children: [
                SizedBox(
                  height: headerHeight,
                  child: Row(
                    children: [
                      SizedBox(width: axisWidth),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('week-header-scroll'),
                          controller: _headerScroll,
                          scrollDirection: Axis.horizontal,
                          physics: physics,
                          itemExtent: width,
                          itemCount: itemCount,
                          scrollCacheExtent: ScrollCacheExtent.pixels(
                            width * 2,
                          ),
                          itemBuilder: (context, index) =>
                              _dayHeader(_dayAt(index), headerHeight),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  key: _timeViewport,
                  height: viewportHeight,
                  child: NotificationListener<OverscrollNotification>(
                    onNotification: _timeOverscroll,
                    child: SingleChildScrollView(
                      controller: _timeScroll,
                      physics: physics,
                      child: SizedBox(
                        key: const ValueKey('time-axis'),
                        height: 24 * _hourHeight + 28,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: axisWidth,
                              child: Listener(
                                onPointerSignal: _wheel,
                                child: CustomPaint(
                                  painter: _AxisPainter(
                                    _hourHeight,
                                    _gridMinutes,
                                    scale,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                key: const ValueKey('week-days-scroll'),
                                controller: _daysScroll,
                                scrollDirection: Axis.horizontal,
                                physics: physics,
                                itemExtent: width,
                                itemCount: itemCount,
                                scrollCacheExtent: ScrollCacheExtent.pixels(
                                  width * 2,
                                ),
                                itemBuilder: (context, index) =>
                                    _dayColumn(_dayAt(index), width),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _dayHeader(DateTime day, double height) {
    final info = widget.controller.calendar.info(day);
    return GestureDetector(
      onTap: _locked ? null : () => _selectDate(day),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        decoration: BoxDecoration(
          color: sameDay(day, widget.controller.now)
              ? context.appColors.selected
              : null,
          border: Border(
            left: BorderSide(color: context.appColors.border),
            bottom: BorderSide(color: context.appColors.border),
          ),
        ),
        child: Column(
          children: [
            Text(
              _phone
                  ? '${day.day}'
                  : '${day.month}/${day.day} ${info.week.substring(2)}',
              maxLines: 1,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              _phone
                  ? info.week.substring(2)
                  : widget.controller.settings.showLunar
                  ? info.smallLabel
                  : '',
              maxLines: 1,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final event
                            in widget.controller
                                .onDay(day)
                                .where((e) => e.allDay))
                          SizedBox(
                            height: _phone ? 12 : 26,
                            child: _eventWidget(event, day, allDay: true),
                          ),
                      ],
                    ),
                  ),
                  if (_dragging?.allDay == true &&
                      !_rangeFor(_dragging!).$1.isAfter(day) &&
                      _rangeFor(_dragging!).$2.isAfter(day))
                    Positioned.fill(
                      key: ValueKey('all-day-drag-preview-${dateKey(day)}'),
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Color(
                            _dragging!.displayColor,
                          ).withValues(alpha: .35),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayColumn(DateTime day, double width) {
    final layout = layoutDay(
      widget.controller.onDay(day),
      day,
      minimumMinutes: (_phone ? 12 : 24) * 60 / _hourHeight,
    );
    return Listener(
      onPointerSignal: _wheel,
      child: CustomPaint(
        painter: _DayGridPainter(_hourHeight, _gridMinutes, context.appColors),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ScrollSafeTapRegion(
                onTap: _locked ? null : clearSelection,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: _locked
                      ? null
                      : (e) {
                          clearSelection();
                          final minute =
                              (e.localPosition.dy *
                                      60 /
                                      _hourHeight /
                                      _gridMinutes)
                                  .floor() *
                              _gridMinutes;
                          openEventEditor(
                            context,
                            widget.controller,
                            date: DateTime(
                              day.year,
                              day.month,
                              day.day,
                              0,
                              minute,
                            ),
                            exactTime: true,
                          );
                        },
                ),
              ),
            ),
            for (final item in layout.items)
              Positioned(
                key: ValueKey(
                  'calendar-event-${item.event.id}-${dateKey(day)}',
                ),
                left: 2 + item.lane * ((width - 4) / item.columns),
                top: item.start * _hourHeight / 60,
                width: math.max(2, (width - 4) / item.columns - 1),
                height: item.event.isPoint
                    ? 26
                    : math.max(
                        _phone ? 12 : 20,
                        (item.occupiedEnd - item.start) * _hourHeight / 60 - 1,
                      ),
                child: _eventWidget(item.event, day, separator: item.separator),
              ),
            for (final region in layout.overlaps)
              Positioned(
                key: ValueKey('overlap-${dateKey(day)}-${region.start}'),
                left: 1,
                width: width - 2,
                top: region.start * _hourHeight / 60,
                height: math.max(
                  4,
                  (region.end - region.start) * _hourHeight / 60,
                ),
                child: ConflictOutline(yellow: region.yellow),
              ),
            if (_dragging != null && !_dragging!.allDay)
              ..._dragPreview(day, width),
          ],
        ),
      ),
    );
  }

  Widget _eventWidget(
    ScheduleEvent event,
    DateTime day, {
    bool allDay = false,
    bool separator = false,
  }) => Builder(
    builder: (blockContext) {
      final block = '${event.id}-${dateKey(day)}',
          selected = _selectedId == event.id;
      final active = selected && (_selectionBlock == block || !_phone);
      return ItemContextMenu(
        enabled: !_locked,
        controller: widget.controller,
        event: event,
        date: day,
        child: CalendarEventInteraction(
          key: ValueKey('interaction-$block'),
          selected: selected,
          enabled: active && !_moving && !_pinching && (!_phone || _mobileDrag),
          locked: _locked,
          phone: _phone,
          resizable: !allDay && !event.isPoint,
          point: event.isPoint,
          onTap: () => _tapEvent(event, block, blockContext),
          onLongPress: () =>
              _tapEvent(event, block, blockContext, longPress: true),
          onStart: (mode) => _startDrag(event, mode, blockContext),
          onUpdate: _dragUpdate,
          onEnd: _finishDrag,
          onCancel: _abortDrag,
          child: event.isPoint && !allDay
              ? Semantics(
                  label:
                      '${event.title} ${eventTimeText(event, widget.controller.settings)}',
                  child: _dragging?.id == event.id
                      ? const SizedBox.expand()
                      : PointEventMarker(
                          color: Color(event.displayColor),
                          tagKey: ValueKey('point-tag-${event.id}'),
                          phone: _phone,
                          title: _phone ? null : event.title,
                        ),
                )
              : Opacity(
                  opacity: 1,
                  child: Semantics(
                    label:
                        '${event.title} ${eventTimeText(event, widget.controller.settings)}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _dragging?.id == event.id
                            ? Colors.transparent
                            : Color(event.displayColor),
                        borderRadius: BorderRadius.circular(3),
                        border: _dragging?.id == event.id
                            ? null
                            : separator
                            ? Border.all(
                                color: blockText(
                                  event.displayColor,
                                ).withValues(alpha: .32),
                              )
                            : Border.all(
                                color: context.appColors.surface,
                                width: .5,
                              ),
                      ),
                      child:
                          _dragging?.id == event.id ||
                              (_phone && _view == CalendarView.week)
                          ? const SizedBox.expand()
                          : Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                '${allDay ? '全天 · ' : ''}${event.title}${allDay ? '' : '\n${clockText(event.start)}'}',
                                maxLines: allDay ? 1 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: blockText(event.displayColor),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
        ),
      );
    },
  );
}

class _CalendarScrollBehavior extends MaterialScrollBehavior {
  const _CalendarScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _DayGridPainter extends CustomPainter {
  final double height;
  final int step;
  final AppPalette colors;
  _DayGridPainter(this.height, this.step, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    for (var minute = 0; minute < 1440; minute += step) {
      final hour = minute % 60 == 0, five = minute % 5 == 0;
      paint.strokeWidth = hour
          ? 1.2
          : five
          ? .8
          : .45;
      paint.color = hour
          ? colors.input.withValues(alpha: .65)
          : colors.border.withValues(alpha: five ? .95 : .5);
      final y = minute * height / 60;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    paint
      ..color = colors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_DayGridPainter old) =>
      old.height != height ||
      old.step != step ||
      old.colors.border != colors.border;
}

class _AxisPainter extends CustomPainter {
  final double height, scale;
  final int step;
  _AxisPainter(this.height, this.step, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    for (var minute = 0; minute < 1440; minute += step) {
      final labelStep = step == 1
          ? 5
          : step <= 5
          ? 15
          : step <= 15
          ? 30
          : step >= 120
          ? 120
          : 60;
      if (minute % labelStep != 0) continue;
      final text = TextPainter(
        text: TextSpan(
          text: '${pad2(minute ~/ 60)}:${pad2(minute % 60)}',
          style: TextStyle(fontSize: 10 * scale, color: AppColors.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, minute * height / 60 + 2),
      );
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.height != height || old.step != step || old.scale != scale;
}
