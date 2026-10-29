import 'dart:math' as math;
import 'models.dart';

class TimedPlacement {
  final ScheduleEvent event;
  final double start, end, occupiedEnd;
  int lane = 0, columns = 1;
  bool separator = false;
  TimedPlacement(this.event, this.start, this.end, this.occupiedEnd);
}

class OverlapRegion {
  final double start, end;
  final bool yellow;
  OverlapRegion(this.start, this.end, this.yellow);
}

({List<TimedPlacement> items, List<OverlapRegion> overlaps}) layoutDay(
  Iterable<ScheduleEvent> events,
  DateTime day, {
  double minimumMinutes = 0,
}) {
  double minute(DateTime d) => sameDay(d, day)
      ? d.hour * 60.0 + d.minute + d.second / 60
      : d.isBefore(day)
      ? 0
      : 1440;
  final items =
      events.where((e) => !e.allDay && e.occursOn(day)).map((e) {
        final start = minute(e.start);
        final end = e.isPoint ? math.min(1440.0, start + 1) : minute(e.end);
        return TimedPlacement(
          e,
          start,
          end,
          math.min(1440, math.max(end, start + minimumMinutes)),
        );
      }).toList()..sort((a, b) {
        final s = a.start.compareTo(b.start);
        return s != 0 ? s : a.event.id.compareTo(b.event.id);
      });
  final cluster = <TimedPlacement>[];
  var clusterEnd = -1.0;
  void finishCluster() {
    if (cluster.isEmpty) return;
    final laneEnds = <double>[];
    for (final item in cluster) {
      var lane = laneEnds.indexWhere((end) => end <= item.start);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(item.occupiedEnd);
      } else {
        laneEnds[lane] = item.occupiedEnd;
      }
      item.lane = lane;
    }
    for (final item in cluster) {
      item.columns = laneEnds.length;
    }
    cluster.clear();
  }

  for (final item in items) {
    if (item.start >= clusterEnd) finishCluster();
    cluster.add(item);
    clusterEnd = math.max(
      item.start >= clusterEnd ? item.occupiedEnd : clusterEnd,
      item.occupiedEnd,
    );
  }
  finishCluster();
  for (final item in items) {
    item.separator = items.any(
      (other) =>
          other != item &&
          other.event.displayColor == item.event.displayColor &&
          other.start <= item.end &&
          other.end >= item.start,
    );
  }
  final boundaries = {
    for (final item in items) ...[item.start, item.end],
  }.toList()..sort();
  final overlaps = <OverlapRegion>[];
  bool reddish(int color) {
    final alpha = (color >> 24 & 255) / 255;
    final r = (color >> 16 & 255) * alpha + 255 * (1 - alpha);
    final g = (color >> 8 & 255) * alpha + 253 * (1 - alpha);
    final b = (color & 255) * alpha + 249 * (1 - alpha);
    return r > 130 && r - g >= 15 && r - b >= 15;
  }

  for (var i = 0; i < boundaries.length - 1; i++) {
    final start = boundaries[i], end = boundaries[i + 1];
    final active = items
        .where((item) => item.start < end && item.end > start)
        .toList();
    if (active.length < 2) continue;
    final yellow = active.any((item) => reddish(item.event.displayColor));
    if (overlaps.isNotEmpty &&
        overlaps.last.end == start &&
        overlaps.last.yellow == yellow) {
      final previous = overlaps.removeLast();
      overlaps.add(OverlapRegion(previous.start, end, yellow));
    } else {
      overlaps.add(OverlapRegion(start, end, yellow));
    }
  }
  return (items: items, overlaps: overlaps);
}
