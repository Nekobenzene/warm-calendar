import 'package:flutter/material.dart';

abstract final class AppMotion {
  static Duration hover(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 140);

  static AnimationStyle popup(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 160),
          reverseDuration: Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) =>
        SafeArea(child: themes.wrap(builder(context))),
    transitionBuilder: (context, animation, _, child) {
      final curve = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween(begin: .985, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}
