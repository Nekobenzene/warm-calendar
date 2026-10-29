import 'models.dart';

const hourHeights = [36.0, 60.0, 96.0, 144.0, 240.0, 480.0, 720.0];
const gridMinutes = [60, 30, 15, 15, 5, 5, 1];

DateTime draggedStart(
  DateTime start, {
  required double dx,
  required double dy,
  required double dayWidth,
  required double hourHeight,
  required int step,
  required bool snap,
}) {
  final dayShift = (dx / dayWidth).round();
  final raw = start.hour * 60 + start.minute + dy * 60 / hourHeight;
  final resolution = snap ? step : 1;
  final minutes = (raw / resolution).round() * resolution;
  return DateTime(start.year, start.month, start.day + dayShift, 0, minutes);
}

String shiftLabel(Duration offset) {
  final minutes = offset.inMinutes;
  final days = minutes.abs() ~/ 1440;
  final hours = minutes.abs() % 1440 ~/ 60;
  final rest = minutes.abs() % 60;
  return '${minutes < 0 ? '提前' : '推后'}${days > 0 ? '$days天' : ''}${hours > 0 ? '$hours小时' : ''}${rest > 0 ? '$rest分钟' : ''}';
}

String pointOrRange(ScheduleEvent event) => event.isPoint ? '时间点' : '日程';
