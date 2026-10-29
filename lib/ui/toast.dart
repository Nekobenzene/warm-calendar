import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

OverlayEntry? _activeToast;

void showToast(OverlayState overlay, String message, {bool error = false}) {
  if (!overlay.mounted) return;
  _activeToast?.remove();
  _activeToast?.dispose();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      error: error,
      onFinish: () {
        if (_activeToast == entry) {
          _activeToast = null;
          entry.remove();
          entry.dispose();
        }
      },
      onUnmount: () {
        if (_activeToast == entry) _activeToast = null;
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final VoidCallback onFinish;
  final VoidCallback onUnmount;
  const _Toast({
    required this.message,
    required this.error,
    required this.onFinish,
    required this.onUnmount,
  });
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve = _animation.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  Timer? _timer;
  bool _closing = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animation.isDismissed && _timer == null) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      if (reduced) {
        _animation.duration = Duration.zero;
        _animation.reverseDuration = Duration.zero;
      }
      _animation.forward().then((_) {
        if (mounted) _timer = Timer(const Duration(milliseconds: 1500), _close);
      });
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _animation.reverse();
    if (mounted) widget.onFinish();
  }

  @override
  void dispose() {
    widget.onUnmount();
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    right: 16,
    bottom: 16,
    width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 360),
    child: SafeArea(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - _curve.value)),
            child: child,
          ),
        ),
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: widget.error
                ? Color.alphaBlend(
                    AppColors.danger.withValues(alpha: .055),
                    context.appColors.surface,
                  )
                : context.appColors.surface,
            elevation: 5,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: widget.error
                    ? AppColors.danger.withValues(alpha: .35)
                    : context.appColors.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    widget.error
                        ? Icons.cancel_outlined
                        : Icons.check_circle_outline,
                    color: widget.error
                        ? AppColors.danger
                        : context.appColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭提示',
                    onPressed: _close,
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
