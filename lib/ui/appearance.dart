import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'components.dart';
import 'motion.dart';
import 'color_picker.dart';

Future<String> prepareBackgroundImage(Uint8List source) async {
  if (source.length > 20 * 1024 * 1024) {
    throw const FormatException('请选择20MB以内的图片');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  // This API reads intrinsic dimensions on every renderer and owns the buffer.
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final ratio = math.min(1.0, 1440 / math.max(width, height));
      return ui.TargetImageSize(
        width: math.max(1, (width * ratio).round()),
        height: math.max(1, (height * ratio).round()),
      );
    },
  );
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 4 * 1024 * 1024) {
      throw const FormatException('图片处理后仍过大，请选择较小的图片');
    }
    return base64Encode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

class AppBackground extends StatefulWidget {
  final AppSettings settings;
  final Widget child;
  const AppBackground({super.key, required this.settings, required this.child});
  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  String _source = '';
  Uint8List? _bytes;
  @override
  Widget build(BuildContext context) {
    if (_source != widget.settings.backgroundImage) {
      _source = widget.settings.backgroundImage;
      try {
        _bytes = _source.isEmpty ? null : base64Decode(_source);
      } catch (_) {
        _bytes = null;
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.appColors.canvas),
        if (_bytes != null)
          Positioned.fill(
            child: Image.memory(
              _bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, error, stack) =>
                  ColoredBox(color: context.appColors.canvas),
            ),
          ),
        if (_bytes != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(
              color: context.appColors.canvas.withValues(
                alpha: 1 - widget.settings.mainImageOpacity,
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class AppGlassPane extends StatelessWidget {
  final AppSettings settings;
  final bool sidebar;
  final Widget child;
  const AppGlassPane({
    super.key,
    required this.settings,
    required this.child,
    this.sidebar = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = sidebar
        ? context.appColors.sidebar
        : context.appColors.canvas;
    if (settings.backgroundImage.isEmpty) {
      return ColoredBox(color: color, child: child);
    }
    final blur = sidebar ? settings.sidebarBlur : settings.mainBlur;
    final opacity = sidebar
        ? settings.sidebarImageOpacity
        : settings.mainImageOpacity;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: color.withValues(alpha: 1 - opacity),
          child: child,
        ),
      ),
    );
  }
}

class AppearanceSettings extends StatefulWidget {
  final AppController controller;
  const AppearanceSettings({super.key, required this.controller});
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool _busy = false;
  AppSettings? _draft;
  Future<void> _save(AppSettings value) async {
    try {
      await widget.controller.updateSettings(value);
    } catch (_) {
      if (mounted) showMessage(context, '外观设置保存失败，请重试。', error: true);
    }
    if (mounted) setState(() => _draft = null);
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '图片',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('请选择20MB以内的图片');
      }
      final prepared = await prepareBackgroundImage(await file.readAsBytes());
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(backgroundImage: prepared),
      );
      if (mounted) showMessage(context, '背景图片已更新');
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is FormatException
              ? e.message.toString()
              : '无法读取图片，请选择有效的PNG、JPG或WebP图片。',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _slider(
    String name,
    double value,
    double max,
    ValueChanged<double> change,
    AppSettings current, {
    bool percent = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(name)),
          Text(
            percent ? '${(value * 100).round()}%' : value.round().toString(),
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
      Slider(
        value: value,
        min: 0,
        max: max,
        onChanged: change,
        onChangeEnd: (_) => _save(_draft ?? current),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, settings = _draft ?? c.settings;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('主题色')),
              OutlinedButton.icon(
                key: const ValueKey('theme-color-picker'),
                icon: ColorPreview(color: settings.themeColor, size: 18),
                label: const Text('调整颜色'),
                onPressed: () async {
                  final color = await showAppDialog<int>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) =>
                        ThemeColorPicker(initial: c.settings.themeColor),
                  );
                  if (color != null) {
                    await _save(c.settings.copyWith(themeColor: color));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('背景图片')),
              if (settings.backgroundImage.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      _save(c.settings.copyWith(backgroundImage: '')),
                  child: const Text('清除'),
                ),
              OutlinedButton(
                onPressed: _busy ? null : _upload,
                child: Text(_busy ? '处理图片…' : '选择图片'),
              ),
            ],
          ),
          if (settings.backgroundImage.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('主界面', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _slider(
              '毛玻璃模糊度',
              settings.mainBlur,
              30,
              (v) => setState(() => _draft = settings.copyWith(mainBlur: v)),
              settings,
            ),
            _slider(
              '图片明显程度',
              settings.mainImageOpacity,
              .65,
              (v) => setState(
                () => _draft = settings.copyWith(mainImageOpacity: v),
              ),
              settings,
              percent: true,
            ),
            const SizedBox(height: 10),
            const Text(
              '侧边栏 / 底部导航栏',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _slider(
              '毛玻璃模糊度',
              settings.sidebarBlur,
              30,
              (v) => setState(() => _draft = settings.copyWith(sidebarBlur: v)),
              settings,
            ),
            _slider(
              '图片明显程度',
              settings.sidebarImageOpacity,
              .65,
              (v) => setState(
                () => _draft = settings.copyWith(sidebarImageOpacity: v),
              ),
              settings,
              percent: true,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _save(
                c.settings.copyWith(
                  themeColor: 0xff536445,
                  backgroundImage: '',
                  mainBlur: 8,
                  sidebarBlur: 16,
                  mainImageOpacity: .16,
                  sidebarImageOpacity: .12,
                ),
              ),
              child: const Text('恢复默认外观'),
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeColorPicker extends StatefulWidget {
  final int initial;
  const ThemeColorPicker({super.key, required this.initial});
  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  late HSLColor _color;
  @override
  void initState() {
    super.initState();
    final c = HSLColor.fromColor(Color(widget.initial));
    _color = c
        .withSaturation(c.saturation.clamp(.12, .40))
        .withLightness(c.lightness.clamp(.38, .56));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.fromSeed(_color.toColor().toARGB32());
    return AlertDialog(
      title: const Text('主题色'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final hue in [
                    85.0,
                    35.0,
                    0.0,
                    325.0,
                    275.0,
                    230.0,
                    200.0,
                    165.0,
                  ])
                    IconButton(
                      tooltip: '选择预置色',
                      onPressed: () => setState(
                        () => _color = HSLColor.fromAHSL(1, hue, .25, .46),
                      ),
                      icon: ColorPreview(
                        color: HSLColor.fromAHSL(
                          1,
                          hue,
                          .25,
                          .46,
                        ).toColor().toARGB32(),
                        size: 28,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('色相'),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  trackShape: const ColorBandTrack(hueBandColors),
                ),
                child: Slider(
                  key: const ValueKey('theme-hue'),
                  min: 0,
                  max: 360,
                  value: _color.hue,
                  onChanged: (v) => setState(() => _color = _color.withHue(v)),
                ),
              ),
              const Text('饱和度'),
              Slider(
                key: const ValueKey('theme-saturation'),
                min: .12,
                max: .40,
                value: _color.saturation,
                onChanged: (v) =>
                    setState(() => _color = _color.withSaturation(v)),
              ),
              const Text('明暗'),
              Slider(
                min: .38,
                max: .56,
                value: _color.lightness,
                onChanged: (v) =>
                    setState(() => _color = _color.withLightness(v)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '文字与底色预览',
                        style: TextStyle(color: palette.accent),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '按钮',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color.toColor().toARGB32()),
          child: const Text('应用'),
        ),
      ],
    );
  }
}
