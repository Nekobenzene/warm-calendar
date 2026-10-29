import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warm_calendar/domain/models.dart';
import 'package:warm_calendar/domain/time_axis.dart';
import 'package:warm_calendar/domain/calendar_service.dart';
import 'package:warm_calendar/domain/holiday_update.dart';
import 'package:warm_calendar/domain/reminders.dart';
import 'package:warm_calendar/ui/theme.dart';
import 'package:warm_calendar/ui/calendar_page.dart';
import 'package:warm_calendar/ui/components.dart';
import 'package:warm_calendar/ui/appearance.dart';
import 'package:warm_calendar/ui/scroll_feedback.dart';
import 'package:warm_calendar/ui/shell.dart';
import 'calendar_interaction_test.dart' show mountCalendar, block, interaction;
import 'recurrence_test.dart' show testApp;

Map<String, dynamic> holiday(int year) => {
  'year': year,
  'papers': ['https://www.gov.cn/holiday'],
  'days': [
    {'name': '元旦', 'date': '$year-01-01', 'isOffDay': true},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('主题全色相、饱和度边界均保留按钮及选中文字对比度', () {
    for (var hue = 0; hue <= 360; hue += 15) {
      for (final saturation in [.12, .4]) {
        for (final light in [.38, .56]) {
          final p = AppPalette.fromSeed(
            HSLColor.fromAHSL(
              1,
              hue.toDouble(),
              saturation,
              light,
            ).toColor().toARGB32(),
          );
          expect(
            contrastRatio(p.accent, Colors.white),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(p.accent, p.selected),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrastRatio(AppColors.text, p.canvas), greaterThan(7));
          expect(p.canvas.computeLuminance(), greaterThan(.85));
        }
      }
    }
  });
  test('外观与图片参数备份往返，非法数字采用默认值或限制范围', () {
    const image =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6RAAAAAASUVORK5CYII=';
    const settings = AppSettings(
      themeColor: 0xff678293,
      backgroundImage: image,
      mainBlur: 4,
      sidebarBlur: 24,
      mainImageOpacity: .4,
      sidebarImageOpacity: .2,
    );
    final restored = BackupData.decode(
      BackupData([], settings).encode(),
    ).settings;
    expect(restored.themeColor, settings.themeColor);
    expect(restored.backgroundImage, image);
    expect(restored.mainBlur, 4);
    expect(restored.sidebarBlur, 24);
    expect(restored.mainImageOpacity, .4);
    expect(restored.sidebarImageOpacity, .2);
    final bad = AppSettings.fromJson({
      'mainBlur': double.nan,
      'sidebarBlur': 100,
      'mainImageOpacity': -1,
      'themeColor': 'red',
    });
    expect(bad.mainBlur, 8);
    expect(bad.sidebarBlur, 30);
    expect(bad.mainImageOpacity, 0);
    expect(bad.themeColor, 0xff536445);
  });
  test('上下跨午夜以及横向跨日移动，不将时间夹在原日期内', () {
    final start = DateTime(2026, 1, 2, 0, 15);
    expect(
      draggedStart(
        start,
        dx: 0,
        dy: -45,
        dayWidth: 100,
        hourHeight: 60,
        step: 15,
        snap: true,
      ),
      DateTime(2026, 1, 1, 23, 30),
    );
    expect(
      draggedStart(
        DateTime(2026, 1, 1, 23, 30),
        dx: 100,
        dy: 90,
        dayWidth: 100,
        hourHeight: 60,
        step: 1,
        snap: true,
      ),
      DateTime(2026, 1, 3, 1),
    );
    expect(gridMinutes.last, 1);
  });
  test('通知正文同时提供多久后和完整开始时间', () {
    final e = ScheduleEvent(
      id: 'n',
      title: '会议',
      start: DateTime(2026, 1, 1, 12),
      end: DateTime(2026, 1, 1, 13),
      updatedAt: DateTime(2026),
    );
    expect(
      reminderBody(e, DateTime(2026, 1, 1, 10, 30)),
      contains('1小时30分钟后开始'),
    );
    expect(reminderBody(e, e.start), contains('现在开始'));
    expect(
      ReminderRequest('r', 1, e, 10, DateTime(2026, 1, 1, 11, 50), true).body,
      contains('开始：2026-01-01 12:00'),
    );
  });
  test('2027至2050年的农历、节气和传统节日离线可用', () {
    final calendar = CalendarService();
    for (var year = 2027; year <= 2050; year++) {
      for (var month = 1; month <= 12; month++) {
        final date = DateTime(year, month, 15);
        expect(calendar.info(date).lunar, isNotEmpty);
        final term = calendar.nextTerm(date);
        expect(term.name, isNotEmpty);
        expect(term.date.difference(date).inDays, inInclusiveRange(0, 17));
      }
      expect(calendar.info(DateTime(year, 10, 1)).festivals, contains('国庆节'));
      expect(calendar.info(DateTime(year, 1, 1)).holidayYearKnown, false);
    }
  });
  testWidgets('背景图片实际渲染，主区和侧栏明显程度独立且清除后恢复', (tester) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xffff0000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(16, 16);
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final source = base64Encode(bytes.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    final boundary = GlobalKey();
    Future<void> mount(AppSettings settings) async {
      await tester.pumpWidget(
        testApp(
          Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: RepaintBoundary(
                key: boundary,
                child: AppBackground(
                  settings: settings,
                  child: Row(
                    children: [
                      Expanded(
                        child: AppGlassPane(
                          settings: settings,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: AppGlassPane(
                          settings: settings,
                          sidebar: true,
                          child: const SizedBox.expand(),
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
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    await mount(
      AppSettings(
        backgroundImage: source,
        mainBlur: 0,
        sidebarBlur: 20,
        mainImageOpacity: .1,
        sidebarImageOpacity: .6,
      ),
    );
    final repaint =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final result = repaint.toImageSync();
    final pixels = (await tester.runAsync(
      () => result.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    int green(int x) => pixels.getUint8((50 * result.width + x) * 4 + 1);
    expect(green(30), greaterThan(green(130) + 60));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    result.dispose();
    await mount(const AppSettings());
    expect(find.byType(Image), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('背景导入处理保留长宽比并缩至1440，坏图片不会生成背景', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1800, 900);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final prepared = await prepareBackgroundImage(data.buffer.asUint8List());
      final codec = await ui.instantiateImageCodec(base64Decode(prepared));
      final result = (await codec.getNextFrame()).image;
      expect(result.width, 1440);
      expect(result.height, 720);
      result.dispose();
      codec.dispose();
      image.dispose();
      picture.dispose();
      await expectLater(
        prepareBackgroundImage(base64Decode('aW52YWxpZA==')),
        throwsException,
      );
    });
  });
  testWidgets('手机底部详情展开后选中日程保持在可见区域，滚动不取消', (tester) async {
    final c = await mountCalendar(tester, phone: true);
    tester.view.physicalSize = const Size(390, 650);
    final today = dayOnly(DateTime.now());
    c.now = today.add(const Duration(hours: 8));
    await c.saveEvent(
      ScheduleEvent(
        id: 'low',
        title: '下方日程',
        notes: '完整详情',
        start: today.add(const Duration(hours: 12)),
        end: today.add(const Duration(hours: 12, minutes: 30)),
        updatedAt: c.now,
      ),
    );
    await tester.pumpWidget(testApp(AppShell(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('日历'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    final event = find.byKey(ValueKey('interaction-low-${dateKey(today)}'));
    final inner = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('time-axis')),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        )
        .controller!;
    inner.jumpTo(9 * 60);
    await tester.pump();
    await tester.ensureVisible(event);
    await tester.pumpAndSettle();
    await tester.tap(event);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final details = find.byKey(const ValueKey('mobile-calendar-details'));
    expect(details, findsOneWidget);
    expect(
      tester.getBottomLeft(event).dy,
      lessThanOrEqualTo(tester.getTopLeft(details).dy),
    );
    expect(tester.getTopLeft(event).dy, greaterThan(100));
    await tester.dragFrom(
      tester.getTopLeft(event) + const Offset(25, -35),
      const Offset(0, -35),
    );
    await tester.pumpAndSettle();
    expect(details, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('假期自动更新跳过404与空占位；已公布数据保留', () async {
    final client = MockClient((r) async {
      final year = int.parse(r.url.pathSegments.last.substring(0, 4));
      if (year == 2025) {
        return http.Response(
          jsonEncode(holiday(year)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (year == 2026) {
        return http.Response(
          jsonEncode({'year': year, 'papers': [], 'days': []}),
          200,
        );
      }
      return http.Response('', 404);
    });
    final rows = await fetchHolidayData({2025, 2026, 2027}, client: client);
    expect(rows.keys, [2025]);
  });
  for (final reduced in [false, true]) {
    testWidgets('手机在时间轴末端选中时间点后仍完整露在详情上方（减少动画：$reduced）', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final c = await mountCalendar(tester, phone: true);
      tester.view.physicalSize = const Size(390, 844);
      final today = dayOnly(DateTime.now());
      c.now = today.add(const Duration(hours: 23));
      await c.saveEvent(
        ScheduleEvent(
          id: 'last-point',
          title: '午夜前时间点',
          start: today.add(const Duration(hours: 23, minutes: 30)),
          end: today.add(const Duration(hours: 23, minutes: 30)),
          updatedAt: c.now,
        ),
      );
      await tester.pumpWidget(testApp(AppShell(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('日历'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('周'));
      await tester.pumpAndSettle();
      final point = find.byKey(
        ValueKey('interaction-last-point-${dateKey(today)}'),
      );
      await tester.ensureVisible(point);
      await tester.pumpAndSettle();
      await tester.tap(point);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final details = find.byKey(const ValueKey('mobile-calendar-details'));
      expect(details, findsOneWidget);
      expect(
        tester.getBottomLeft(point).dy,
        lessThanOrEqualTo(tester.getTopLeft(details).dy - 4),
      );
    });
  }
  test('无效假期不替换有效年份，更新年份时清除旧条目', () {
    final c = CalendarService();
    c.loadHolidayJson(holiday(2026));
    expect(
      () => c.loadHolidayJson({
        'year': 2026,
        'days': [
          {'name': '错误', 'date': '2026-02-30', 'isOffDay': true},
        ],
      }),
      throwsFormatException,
    );
    expect(c.info(DateTime(2026, 1, 1)).holiday!.name, '元旦');
    c.loadHolidayJson({
      'year': 2026,
      'days': [
        {'name': '劳动节', 'date': '2026-05-01', 'isOffDay': true},
      ],
    });
    expect(c.info(DateTime(2026, 1, 1)).holiday, isNull);
    for (final year in [2030, 2050]) {
      final day = c.info(DateTime(year, 10, 1));
      expect(day.lunar, isNotEmpty);
      expect(day.festivals, isNotEmpty);
      expect(day.holidayYearKnown, false);
    }
  });
  testWidgets('边界跨日调整，预览全列覆盖，原日程只留选中边框', (tester) async {
    final c = await mountCalendar(tester);
    await c.saveEvent(
      ScheduleEvent(
        id: 'other',
        title: '重叠事项',
        start: DateTime(2026, 1, 2, 10),
        end: DateTime(2026, 1, 2, 12),
        updatedAt: c.now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(block);
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('week-days-scroll')),
    );
    final at =
        tester.getBottomLeft(block) +
        Offset(tester.getSize(block).width / 2, -3);
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(list.itemExtent!, 0));
    await tester.pump();
    final preview = find.byKey(const ValueKey('drag-preview-2026-01-02'));
    expect(preview, findsOneWidget);
    expect(tester.getSize(preview).width, closeTo(list.itemExtent! - 4, .1));
    final fill =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: block,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(fill.color, Colors.transparent);
    await gesture.up();
    await tester.pumpAndSettle();
    final changed = c.events.firstWhere((e) => e.id == 'one');
    expect(changed.start, DateTime(2026, 1, 1, 9));
    expect(changed.end, DateTime(2026, 1, 2, 11));
    expect(preview, findsNothing);
  });
  testWidgets('手机选中后的空白滚动保持选中，空白点击取消', (tester) async {
    await mountCalendar(tester, phone: true);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, true);
    final grid = find.byKey(const ValueKey('time-axis'));
    final scroll = find
        .ancestor(of: grid, matching: find.byType(SingleChildScrollView))
        .first;
    final position = tester.getTopLeft(scroll) + const Offset(75, 250);
    await tester.dragFrom(position, const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, true);
    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(interaction(tester).selected, false);
  });
  testWidgets('时间轴滚动到尽头后将剩余滚轮交给整个页面', (tester) async {
    final c = await mountCalendar(tester);
    final outer = ScrollController();
    await tester.pumpWidget(
      testApp(
        SizedBox(
          height: 340,
          child: ScrollBoundaryFeedback(
            child: SingleChildScrollView(
              controller: outer,
              child: Column(
                children: [
                  CalendarPage(
                    controller: c,
                    selectedDate: DateTime(2026, 1, 1),
                    onSelect: (_) {},
                  ),
                  const SizedBox(height: 200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    final inner = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('time-axis')),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        )
        .controller!;
    inner.jumpTo(inner.position.maxScrollExtent);
    outer.jumpTo(0);
    await tester.pump();
    final viewport = find
        .ancestor(
          of: find.byKey(const ValueKey('time-axis')),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final point = tester.getTopLeft(viewport) + const Offset(100, 40);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 100)),
    );
    await tester.pump();
    expect(outer.offset, greaterThan(0));
    expect(inner.offset, inner.position.maxScrollExtent);
    inner.jumpTo(0);
    final before = outer.offset;
    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, -50)),
    );
    await tester.pump();
    expect(outer.offset, lessThan(before));
    inner.jumpTo(inner.position.maxScrollExtent);
    outer.jumpTo(0);
    await tester.pump();
    await tester.dragFrom(point, const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(outer.offset, greaterThan(0));
    inner.jumpTo(0);
    final touchBefore = outer.offset;
    await tester.dragFrom(point, const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(outer.offset, lessThan(touchBefore));
    await tester.pumpWidget(const SizedBox());
    outer.dispose();
  });
  testWidgets('一分分度与锁旁注可达', (tester) async {
    await mountCalendar(tester);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('放大时间轴'));
      await tester.pumpAndSettle();
    }
    expect(find.text('分度 1分钟'), findsOneWidget);
    expect(find.text('可选中'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-lock')));
    await tester.pumpAndSettle();
    expect(find.text('不可选中'), findsOneWidget);
  });
  testWidgets('整页滚轮已到边缘时仍提供短暂反馈', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      testApp(
        ScrollBoundaryFeedback(
          child: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 2000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, -100),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.offset, 0);
    expect(tester.binding.hasScheduledFrame, true);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('失败toast显示叉及红色边框，成功维持勾号', (tester) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessage(context, '操作失败', error: true),
            child: const Text('触发'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('操作失败'), matching: find.byType(Material))
          .first,
    );
    final border = (material.shape as RoundedRectangleBorder).side.color;
    expect(border.r, greaterThan(border.g));
    expect(material.color!.r, greaterThan(material.color!.g));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('操作失败'), findsNothing);
  });
  testWidgets('主题调色窗饱和度有界，色相右端保持360度', (tester) async {
    await tester.pumpWidget(
      testApp(const ThemeColorPicker(initial: 0xff536445)),
    );
    await tester.pumpAndSettle();
    final saturation = tester.widget<Slider>(
      find.byKey(const ValueKey('theme-saturation')),
    );
    expect(saturation.min, .12);
    expect(saturation.max, .4);
    final hue = find.byKey(const ValueKey('theme-hue'));
    await tester.drag(hue, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(hue).value, 360);
  });
}
