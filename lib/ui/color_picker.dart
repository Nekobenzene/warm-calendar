import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'motion.dart';

enum ColorEncoding { hex, rgba, rgb, hsla }

enum PaletteType { square, wheel, hsl }

const hueBandColors = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

class ColorBandTrack extends RoundedRectSliderTrackShape {
  final List<Color> colors;
  const ColorBandTrack(this.colors);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }
}

String encodeColor(Color color, ColorEncoding mode) {
  final value = color.toARGB32();
  final r = value >> 16 & 255, g = value >> 8 & 255, b = value & 255;
  final a = ((value >> 24 & 255) / 255).toStringAsFixed(3);
  return switch (mode) {
    ColorEncoding.hex =>
      '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}${(value >> 24 & 255).toRadixString(16).padLeft(2, '0').toUpperCase()}',
    ColorEncoding.rgb => 'rgb($r, $g, $b)',
    ColorEncoding.rgba => 'rgba($r, $g, $b, $a)',
    ColorEncoding.hsla => () {
      final hsl = HSLColor.fromColor(color);
      return 'hsla(${hsl.hue.toStringAsFixed(1)}, ${(hsl.saturation * 100).toStringAsFixed(1)}%, ${(hsl.lightness * 100).toStringAsFixed(1)}%, $a)';
    }(),
  };
}

Color? decodeColor(String text, ColorEncoding mode, {double alpha = 1}) {
  if (mode == ColorEncoding.hex) {
    final hex = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return null;
    }
    final value = int.parse(hex, radix: 16);
    return Color(
      hex.length == 6
          ? 0xFF000000 | value
          : (value >> 8) | ((value & 255) << 24),
    );
  }
  final raw = text
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^(?:rgba?|hsla?)\('), '')
      .replaceFirst(RegExp(r'\)$'), '');
  final parts = raw.split(',').map((s) => s.trim()).toList();
  final expected = mode == ColorEncoding.rgb ? 3 : 4;
  if (parts.length != expected) return null;
  double? number(String s, {bool percent = false}) {
    final value = double.tryParse(s.replaceAll('%', ''));
    if (value == null || !value.isFinite) return null;
    return percent || s.endsWith('%') ? value / 100 : value;
  }

  final a = expected == 4 ? number(parts[3]) : alpha;
  if (a == null || a < 0 || a > 1) return null;
  if (mode == ColorEncoding.hsla) {
    final h = number(parts[0]),
        s = number(parts[1], percent: true),
        l = number(parts[2], percent: true);
    if (h == null ||
        s == null ||
        l == null ||
        h < 0 ||
        h > 360 ||
        s < 0 ||
        s > 1 ||
        l < 0 ||
        l > 1) {
      return null;
    }
    return HSLColor.fromAHSL(a, h % 360, s, l).toColor();
  }
  final channels = parts.take(3).map(int.tryParse).toList();
  if (channels.any((c) => c == null || c < 0 || c > 255)) return null;
  return Color.fromRGBO(channels[0]!, channels[1]!, channels[2]!, a);
}

Future<int?> pickEventColor(
  BuildContext context, {
  required String title,
  required int initial,
}) => showAppDialog<int>(
  context: context,
  barrierDismissible: false,
  builder: (_) => EventColorPicker(title: title, initial: initial),
);

class ColorPreview extends StatelessWidget {
  final int color;
  final double size;
  const ColorPreview({super.key, required this.color, this.size = 20});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CustomPaint(
        painter: _CheckerPainter(),
        child: ColoredBox(color: Color(color)),
      ),
    ),
  );
}

class EventColorPicker extends StatefulWidget {
  final String title;
  final int initial;
  const EventColorPicker({
    super.key,
    required this.title,
    required this.initial,
  });
  @override
  State<EventColorPicker> createState() => _EventColorPickerState();
}

class _EventColorPickerState extends State<EventColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  Color get _color => _hsv.toColor();
  PaletteType _type = PaletteType.square;
  ColorEncoding _encoding = ColorEncoding.hex;
  late final TextEditingController _input = TextEditingController(
    text: encodeColor(_color, _encoding),
  );
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _set(Color color, {bool writeInput = true}) {
    setState(() {
      final hsv = HSVColor.fromColor(color);
      _hsv = hsv.saturation == 0 ? hsv.withHue(_hsv.hue) : hsv;
      _error = null;
      if (writeInput) _input.text = encodeColor(_color, _encoding);
    });
  }

  void _setHsv(HSVColor value) => setState(() {
    _hsv = value;
    _error = null;
    _input.text = encodeColor(_color, _encoding);
  });
  void _palette(Offset p, Size size) {
    if (_type == PaletteType.wheel) {
      final dx = p.dx - size.width / 2, dy = p.dy - size.height / 2;
      _setHsv(
        _hsv
            .withHue((math.atan2(dy, dx) * 180 / math.pi + 360) % 360)
            .withValue(
              (math.sqrt(dx * dx + dy * dy) / (size.shortestSide / 2)).clamp(
                0,
                1,
              ),
            ),
      );
    } else if (_type == PaletteType.square) {
      _setHsv(
        _hsv
            .withSaturation((p.dx / size.width).clamp(0, 1))
            .withValue((1 - p.dy / size.height).clamp(0, 1)),
      );
    } else {
      _set(
        HSLColor.fromAHSL(
          _hsv.alpha,
          _hsv.hue,
          (p.dx / size.width).clamp(0, 1),
          (1 - p.dy / size.height).clamp(0, 1),
        ).toColor(),
      );
    }
  }

  void _apply() {
    final color = decodeColor(_input.text, _encoding, alpha: _hsv.alpha);
    if (color == null) {
      setState(() => _error = '颜色编码无效，请检查数值和格式');
      return;
    }
    Navigator.pop(context, color.toARGB32());
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ColorPreview(color: _color.toARGB32(), size: 28),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in [
                    0xFFE4EAD9,
                    0xFFCBDFF0,
                    0xFFD8D1EA,
                    0xFFF0D4DF,
                    0xFFF1D5C2,
                    0xFFF0E5B8,
                    0xFFCBE3DE,
                    0xFFD26666,
                    0xFFE2E3DF,
                    0xFF536445,
                  ])
                    Semantics(
                      button: true,
                      label:
                          '预设 ${encodeColor(Color(preset), ColorEncoding.hex)}',
                      child: InkWell(
                        onTap: () =>
                            _set(Color(preset).withValues(alpha: _hsv.alpha)),
                        borderRadius: BorderRadius.circular(4),
                        child: ColorPreview(color: preset, size: 28),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<PaletteType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PaletteType.square, label: Text('色板')),
                  ButtonSegment(value: PaletteType.wheel, label: Text('色环')),
                  ButtonSegment(value: PaletteType.hsl, label: Text('HSL')),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 176,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = _type == PaletteType.wheel
                        ? 176.0
                        : box.maxWidth;
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: 176,
                        child: Semantics(
                          label: '调色盘',
                          child: RawGestureDetector(
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
                              onPointerDown: (d) =>
                                  _palette(d.localPosition, Size(width, 176)),
                              onPointerMove: (d) =>
                                  _palette(d.localPosition, Size(width, 176)),
                              child: CustomPaint(
                                painter: _PalettePainter(_hsv, _type),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Text(_type == PaletteType.wheel ? '饱和度' : '色相'),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 10,
                        trackShape: ColorBandTrack(
                          _type == PaletteType.wheel
                              ? [
                                  _hsv.withAlpha(1).withSaturation(0).toColor(),
                                  _hsv.withAlpha(1).withSaturation(1).toColor(),
                                ]
                              : hueBandColors,
                        ),
                      ),
                      child: Slider(
                        key: const ValueKey('color-component-slider'),
                        min: 0,
                        max: _type == PaletteType.wheel ? 1 : 360,
                        value: _type == PaletteType.wheel
                            ? _hsv.saturation
                            : _hsv.hue,
                        onChanged: (v) => _setHsv(
                          _type == PaletteType.wheel
                              ? _hsv.withSaturation(v)
                              : _hsv.withHue(v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('不透明度'),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('color-alpha-slider'),
                      value: _hsv.alpha,
                      divisions: 100,
                      label: '${(_hsv.alpha * 100).round()}%',
                      onChanged: (v) => _setHsv(_hsv.withAlpha(v)),
                    ),
                  ),
                  SizedBox(
                    width: 44 * MediaQuery.textScalerOf(context).scale(1),
                    child: Text(
                      '${(_hsv.alpha * 100).round()}%',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, box) {
                  final fields = [
                    SizedBox(
                      width: 92 * MediaQuery.textScalerOf(context).scale(1),
                      child: DropdownButtonFormField<ColorEncoding>(
                        initialValue: _encoding,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '编码'),
                        items: [
                          for (final mode in ColorEncoding.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(mode.name.toUpperCase()),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _encoding = v!;
                          _input.text = encodeColor(_color, _encoding);
                          _error = null;
                        }),
                      ),
                    ),
                    TextField(
                      key: const ValueKey('color-code-input'),
                      controller: _input,
                      decoration: InputDecoration(
                        labelText: '颜色值',
                        errorText: _error,
                        helperText: _encoding == ColorEncoding.hex
                            ? '#RRGGBB 或 #RRGGBBAA'
                            : null,
                      ),
                      onChanged: (v) {
                        final color = decodeColor(
                          v,
                          _encoding,
                          alpha: _hsv.alpha,
                        );
                        if (color != null) _set(color, writeInput: false);
                      },
                    ),
                  ];
                  if (box.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
                      300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fields[0],
                        const SizedBox(height: 12),
                        fields[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      fields[0],
                      const SizedBox(width: 10),
                      Expanded(child: fields[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _apply, child: const Text('应用颜色')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (var y = 0.0; y < size.height; y += 5) {
      for (var x = 0.0; x < size.width; x += 5) {
        p.color = ((x / 5).floor() + (y / 5).floor()).isEven
            ? Colors.white
            : const Color(0xFFD9D9D9);
        canvas.drawRect(Rect.fromLTWH(x, y, 5, 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

class _PalettePainter extends CustomPainter {
  final HSVColor hsv;
  final PaletteType type;
  _PalettePainter(this.hsv, this.type);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    Offset marker;
    if (type == PaletteType.square) {
      paint.shader = LinearGradient(
        colors: [
          Colors.white,
          hsv.withAlpha(1).withSaturation(1).withValue(1).toColor(),
        ],
      ).createShader(rect);
      canvas.drawRect(rect, paint);
      paint.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
      ).createShader(rect);
      canvas.drawRect(rect, paint);
      marker = Offset(
        hsv.saturation * size.width,
        (1 - hsv.value) * size.height,
      );
    } else if (type == PaletteType.wheel) {
      final center = Offset(size.width / 2, size.height / 2),
          radius = size.shortestSide / 2;
      paint.shader = SweepGradient(
        colors: [
          for (var h = 0; h <= 360; h += 60)
            HSVColor.fromAHSV(1, h.toDouble(), hsv.saturation, 1).toColor(),
        ],
      ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
      paint.shader = const RadialGradient(
        colors: [Colors.black, Color(0x00000000)],
      ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
      final angle = hsv.hue * math.pi / 180;
      marker =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (hsv.value * radius);
    } else {
      paint.shader = null;
      for (var y = 0; y < 36; y++) {
        for (var x = 0; x < 36; x++) {
          paint.color = HSLColor.fromAHSL(
            1,
            hsv.hue,
            x / 35,
            1 - y / 35,
          ).toColor();
          canvas.drawRect(
            Rect.fromLTWH(
              x * size.width / 36,
              y * size.height / 36,
              size.width / 36 + .5,
              size.height / 36 + .5,
            ),
            paint,
          );
        }
      }
      final hsl = HSLColor.fromColor(hsv.toColor());
      marker = Offset(
        hsl.saturation * size.width,
        (1 - hsl.lightness) * size.height,
      );
    }
    marker = Offset(
      marker.dx.clamp(4, size.width - 4),
      marker.dy.clamp(4, size.height - 4),
    );
    canvas.drawCircle(
      marker,
      5,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      marker,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PalettePainter oldDelegate) =>
      oldDelegate.hsv != hsv || oldDelegate.type != type;
}
