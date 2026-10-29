import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'theme.dart';

enum CalendarEditMode { move, start, end }

/// Dismiss only on a real tap, without competing with scroll or double tap.
class ScrollSafeTapRegion extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ScrollSafeTapRegion({super.key, required this.child, this.onTap});
  @override
  State<ScrollSafeTapRegion> createState() => _ScrollSafeTapRegionState();
}

class _ScrollSafeTapRegionState extends State<ScrollSafeTapRegion> {
  int? _pointer;
  double _travel = 0;
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      if (_pointer != null) {
        _travel = 100;
        return;
      }
      _pointer = e.pointer;
      _travel = 0;
    },
    onPointerMove: (e) {
      if (_pointer == e.pointer) _travel += e.delta.distance;
    },
    onPointerUp: (e) {
      if (_pointer != e.pointer) return;
      _pointer = null;
      if (_travel < 9) widget.onTap?.call();
    },
    onPointerCancel: (e) {
      if (_pointer == e.pointer) _pointer = null;
    },
    child: widget.child,
  );
}

/// Selected blocks claim one pointer; two-pointer zoom is handled by the axis.
class CalendarEventInteraction extends StatefulWidget {
  final bool selected, enabled, locked, phone, resizable;
  final VoidCallback onTap, onLongPress, onEnd, onCancel;
  final ValueChanged<CalendarEditMode> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final Widget child;
  const CalendarEventInteraction({
    super.key,
    required this.selected,
    required this.enabled,
    required this.locked,
    required this.phone,
    required this.resizable,
    required this.onTap,
    required this.onLongPress,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.child,
  });
  @override
  State<CalendarEventInteraction> createState() =>
      _CalendarEventInteractionState();
}

class _CalendarEventInteractionState extends State<CalendarEventInteraction> {
  int? _pointer;
  Offset _total = Offset.zero;
  bool _started = false;
  CalendarEditMode _mode = CalendarEditMode.move;
  @override
  void didUpdateWidget(CalendarEventInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.locked) {
      _pointer = null;
      _total = Offset.zero;
      _started = false;
    }
  }

  CalendarEditMode _at(Offset point, double height) {
    if (!widget.resizable) return CalendarEditMode.move;
    final edge = widget.phone ? 10.0 : 7.0;
    if (point.dy <= edge && point.dy < height / 2) {
      return CalendarEditMode.start;
    }
    if (point.dy >= height - edge) return CalendarEditMode.end;
    return CalendarEditMode.move;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final canDrag = widget.enabled && !widget.locked;
      final content = widget.selected
          ? Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: context.appColors.accent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (widget.resizable)
                  for (final top in [true, false])
                    Positioned(
                      left: 0,
                      right: 0,
                      top: top ? 1 : null,
                      bottom: top ? null : 1,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 4,
                            decoration: BoxDecoration(
                              color: context.appColors.accent,
                              border: Border.all(
                                color: context.appColors.surface,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            )
          : widget.child;
      final pointer = canDrag
          ? RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(
                      () => EagerGestureRecognizer(
                        allowedButtonsFilter: (buttons) =>
                            buttons == kPrimaryMouseButton,
                      ),
                      (_) {},
                    ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (_pointer != null || e.buttons != kPrimaryMouseButton) {
                    return;
                  }
                  _pointer = e.pointer;
                  _total = Offset.zero;
                  _started = false;
                  _mode = _at(e.localPosition, box.maxHeight);
                },
                onPointerMove: (e) {
                  if (_pointer != e.pointer) return;
                  _total += e.delta;
                  if (!_started && _total.distance > (widget.phone ? 9 : 5)) {
                    _started = true;
                    widget.onStart(_mode);
                    widget.onUpdate(
                      DragUpdateDetails(
                        delta: _total,
                        globalPosition: e.position,
                      ),
                    );
                  } else if (_started) {
                    widget.onUpdate(
                      DragUpdateDetails(
                        delta: e.delta,
                        globalPosition: e.position,
                      ),
                    );
                  }
                },
                onPointerUp: (e) {
                  if (_pointer != e.pointer) return;
                  _pointer = null;
                  if (_started) {
                    widget.onEnd();
                  } else {
                    widget.onTap();
                  }
                  _started = false;
                },
                onPointerCancel: (e) {
                  if (_pointer == e.pointer) {
                    _pointer = null;
                    _started = false;
                    widget.onCancel();
                  }
                },
                child: content,
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.locked ? null : widget.onTap,
              onLongPress: widget.locked ? null : widget.onLongPress,
              child: content,
            );
      return Semantics(
        selected: widget.selected,
        button: !widget.locked,
        child: MouseRegion(
          cursor: widget.locked
              ? SystemMouseCursors.basic
              : canDrag
              ? (_mode == CalendarEditMode.move
                    ? (_started
                          ? SystemMouseCursors.grabbing
                          : SystemMouseCursors.grab)
                    : SystemMouseCursors.resizeUpDown)
              : SystemMouseCursors.click,
          onHover: canDrag
              ? (e) {
                  final next = _at(e.localPosition, box.maxHeight);
                  if (next != _mode) setState(() => _mode = next);
                }
              : null,
          child: pointer,
        ),
      );
    },
  );
}

/// Claim a press on an enabled event before ancestor scroll views do.
/// A click still edits; moving more than 4px becomes a direct drag.
class CalendarDragHandle extends StatefulWidget {
  final bool enabled;
  final VoidCallback onStart, onEnd, onCancel, onTap;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final Widget child;
  const CalendarDragHandle({
    super.key,
    required this.enabled,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
    required this.onTap,
    required this.onUpdate,
    required this.child,
  });
  @override
  State<CalendarDragHandle> createState() => _CalendarDragHandleState();
}

class _CalendarDragHandleState extends State<CalendarDragHandle> {
  int? _pointer;
  Offset _total = Offset.zero;
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () => EagerGestureRecognizer(
                allowedButtonsFilter: (buttons) =>
                    buttons == kPrimaryMouseButton,
              ),
              (_) {},
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null || e.buttons != kPrimaryMouseButton) return;
          _pointer = e.pointer;
          _total = Offset.zero;
          widget.onStart();
        },
        onPointerMove: (e) {
          if (_pointer != e.pointer) return;
          _total += e.delta;
          widget.onUpdate(
            DragUpdateDetails(delta: e.delta, globalPosition: e.position),
          );
        },
        onPointerUp: (e) {
          if (_pointer != e.pointer) return;
          _pointer = null;
          if (_total.distance > 4) {
            widget.onEnd();
          } else {
            widget.onCancel();
            widget.onTap();
          }
        },
        onPointerCancel: (e) {
          if (_pointer != e.pointer) return;
          _pointer = null;
          widget.onCancel();
        },
        child: widget.child,
      ),
    );
  }
}

Color blockText(int argb) {
  final luminance = Color.alphaBlend(
    Color(argb),
    AppColors.surface,
  ).computeLuminance();
  return luminance > .3
      ? AppColors.text
      : luminance > .179
      ? Colors.black
      : Colors.white;
}

class CalendarBlock extends StatelessWidget {
  final String title;
  final String time;
  final int color;
  final int maxLines;
  final bool separator;
  final VoidCallback onTap;
  const CalendarBlock({
    super.key,
    required this.title,
    required this.time,
    required this.color,
    required this.maxLines,
    required this.separator,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Color(color),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: separator
          ? BorderSide(color: blockText(color).withValues(alpha: .32))
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          '$title\n$time',
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.3, color: blockText(color)),
        ),
      ),
    ),
  );
}

class ConflictOutline extends StatelessWidget {
  final bool yellow;
  const ConflictOutline({super.key, required this.yellow});
  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _DashedOutline(yellow)));
}

class _DashedOutline extends CustomPainter {
  final bool yellow;
  _DashedOutline(this.yellow);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = yellow ? const Color(0xFFF5C400) : const Color(0xFFCC3636)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            .8,
            .8,
            (size.width - 1.6).clamp(0, double.infinity),
            (size.height - 1.6).clamp(0, double.infinity),
          ),
          const Radius.circular(3),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 8) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 5).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) =>
      yellow != oldDelegate.yellow;
}
