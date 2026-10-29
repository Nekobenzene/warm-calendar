import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_calendar/app_controller.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/ui/color_picker.dart';
import 'package:warm_calendar/ui/event_editor.dart';
import 'package:warm_calendar/ui/home_page.dart';
import 'prototype_test.dart' show MemoryRepository;
import 'recurrence_test.dart' show testApp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('HEX使用RGBA顺序，RGBA/HSLA/RGB编码透明度往返且拒绝无效值', () {
    const color = Color(0x80446688);
    expect(encodeColor(color, ColorEncoding.hex), '#44668880');
    expect(decodeColor('#44668880', ColorEncoding.hex), color);
    expect(decodeColor('#446688', ColorEncoding.hex), const Color(0xFF446688));
    expect(
      decodeColor(
        encodeColor(color, ColorEncoding.rgba),
        ColorEncoding.rgba,
      )!.toARGB32(),
      color.toARGB32(),
    );
    expect(
      decodeColor(
        'rgb(68, 102, 136)',
        ColorEncoding.rgb,
        alpha: 128 / 255,
      )!.toARGB32(),
      color.toARGB32(),
    );
    final hsl = decodeColor(
      encodeColor(color, ColorEncoding.hsla),
      ColorEncoding.hsla,
    )!;
    expect((hsl.r - color.r).abs(), lessThan(.005));
    expect((hsl.a - color.a).abs(), lessThan(.005));
    expect(decodeColor('rgba(300, 0, 0, 1)', ColorEncoding.rgba), isNull);
    expect(decodeColor('rgba(1, 2, 3, NaN)', ColorEncoding.rgba), isNull);
    expect(decodeColor('#ZZ0000', ColorEncoding.hex), isNull);
    final event = ScheduleEvent(
      id: 'alpha',
      title: '透明色',
      start: DateTime(2026, 1, 1, 9),
      end: DateTime(2026, 1, 1, 10),
      updatedAt: DateTime(2026),
      color: 0x40446688,
      completedColor: 0,
    );
    final restored = BackupData.decode(
      BackupData([event], const AppSettings()).encode(),
    ).events.single;
    expect(restored.color, 0x40446688);
    expect(restored.completedColor, 0);
  });

  for (final scenario in [(390.0, 1.0), (390.0, 2.0)]) {
    testWidgets('独立调色窗的三种调色盘、四种编码和透明度，${scenario.$1}/${scenario.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      int? result;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickEventColor(
                  context,
                  title: '未完成颜色',
                  initial: 0xFFE4EAD9,
                );
              },
              child: const Text('调色'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('调色'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(EventColorPicker), findsOneWidget);
      for (final type in ['色环', 'HSL', '色板']) {
        await tester.ensureVisible(find.text(type));
        await tester.tap(find.text(type));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final component = find.byKey(const ValueKey('color-component-slider'));
      await tester.ensureVisible(component);
      tester.widget<Slider>(component).onChanged!(360);
      await tester.pump();
      expect(tester.widget<Slider>(component).value, 360);
      await tester.tap(find.text('色环'));
      await tester.pumpAndSettle();
      expect(find.text('饱和度'), findsOneWidget);
      tester.widget<Slider>(component).onChanged!(0);
      await tester.pump();
      final gray = decodeColor(
        tester
            .widget<TextField>(find.byKey(const ValueKey('color-code-input')))
            .controller!
            .text,
        ColorEncoding.hex,
      )!;
      expect(gray.r, gray.g);
      expect(gray.g, gray.b);
      for (final mode in ['RGBA', 'RGB', 'HSLA', 'HEX']) {
        final encoding = find.byType(DropdownButtonFormField<ColorEncoding>);
        await tester.ensureVisible(encoding);
        await tester.tap(encoding);
        await tester.pumpAndSettle();
        await tester.tap(find.text(mode).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final input = find.byKey(const ValueKey('color-code-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '#D2666640');
      await tester.pump();
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('color-alpha-slider')))
            .value,
        closeTo(64 / 255, .005),
      );
      await tester.ensureVisible(find.text('应用颜色'));
      await tester.tap(find.text('应用颜色'));
      await tester.pumpAndSettle();
      expect(result, 0x40D26666);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(1366, 768), const Size(1280, 720)]) {
    testWidgets('常规创建表单在$size一页完成，颜色按钮在全天右侧', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        repository: MemoryRepository(),
        calendar: CalendarService(),
      );
      await tester.runAsync(() => c.initialize(startTimer: false));
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openEventEditor(context, c),
              child: const Text('创建'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('event-form-scroll')),
        matching: find.byType(Scrollable),
      );
      expect(
        tester
            .state<ScrollableState>(scrollable.first)
            .position
            .maxScrollExtent,
        0,
      );
      expect(
        tester.getCenter(find.text('未完成颜色')).dx,
        greaterThan(tester.getCenter(find.text('仅时间点（无时长）')).dx),
      );
      expect(
        tester.getCenter(find.text('已完成颜色')).dx,
        greaterThan(tester.getCenter(find.text('未完成颜色')).dx),
      );
      expect(
        tester.getBottomRight(find.text('保存日程')).dy,
        lessThan(size.height),
      );
      expect(find.widgetWithText(TextFormField, '自定义颜色'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('首页全部日程仅当天，跨日计入，下一项可指向明天', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryRepository();
    final now = DateTime(2026, 10, 29, 12);
    ScheduleEvent event(String id, DateTime start, DateTime end) =>
        ScheduleEvent(
          id: id,
          title: id,
          start: start,
          end: end,
          updatedAt: now,
          reminderMinutes: null,
        );
    final rows = [
      event('昨天历史', DateTime(2026, 10, 28, 9), DateTime(2026, 10, 28, 10)),
      event('跨日仍属今天', DateTime(2026, 10, 28, 23), DateTime(2026, 10, 29, 1)),
      event('今天事项', DateTime(2026, 10, 29, 9), DateTime(2026, 10, 29, 10)),
      event('明天事项', DateTime(2026, 10, 30, 9), DateTime(2026, 10, 30, 10)),
    ];
    for (final e in rows) {
      repo.rows[e.id] = e;
    }
    final c = AppController(repository: repo, calendar: CalendarService());
    await tester.runAsync(() => c.initialize(startTimer: false));
    c.now = now;
    await tester.pumpWidget(
      testApp(HomePage(controller: c, onCalendar: (_) {}, onStatus: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('昨天历史'), findsNothing);
    expect(find.text('跨日仍属今天'), findsOneWidget);
    expect(find.text('今天事项'), findsOneWidget);
    expect(
      find.text('明天事项'),
      findsOneWidget,
    ); // Only the next-event panel, not today's board.
    expect(find.text('暂无未完成日程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
