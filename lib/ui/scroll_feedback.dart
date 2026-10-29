import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Feedback belongs to the final viewport, after nested scrolling has consumed
/// the gesture. A brief stretch on touch and a fading edge shadow show the limit.
class ScrollBoundaryFeedback extends StatefulWidget {
  final Widget child;
  const ScrollBoundaryFeedback({super.key, required this.child});
  static void pulse(BuildContext context, double delta) => context
      .findAncestorStateOfType<_ScrollBoundaryFeedbackState>()
      ?.pulse(delta);
  @override
  State<ScrollBoundaryFeedback> createState() => _ScrollBoundaryFeedbackState();
}

class _ScrollBoundaryFeedbackState extends State<ScrollBoundaryFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  bool _top = true;
  void pulse(double delta) {
    if (!mounted || delta.abs() < .1) return;
    _top = delta < 0;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<OverscrollNotification>(
    onNotification: (n) {
      if (n.depth == 0 && n.metrics.axis == Axis.vertical) pulse(n.overscroll);
      return false;
    },
    child: Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          // Scrollables register first when they can consume this wheel event.
          // Only a fully exhausted chain falls through to the viewport edge.
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (_) => pulse(event.scrollDelta.dy),
          );
        }
      },
      child: AnimatedBuilder(
        animation: _fade,
        child: widget.child,
        builder: (context, child) {
          final amount = _fade.isAnimating
              ? (1 - Curves.easeOut.transform(_fade.value))
              : 0.0;
          final touch = MediaQuery.sizeOf(context).width < 600;
          final reduced = MediaQuery.disableAnimationsOf(context);
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scaleY: !reduced && touch ? 1 + amount * .018 : 1,
                  alignment: _top
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: child,
                ),
                if (amount > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _top ? 0 : null,
                    bottom: _top ? null : 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: .16 * amount,
                              ),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
