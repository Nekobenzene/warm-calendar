import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'models.dart';

class HolidayInfo {
  final String name;
  final bool isOffDay;
  const HolidayInfo(this.name, this.isOffDay);
}

class CalendarDay {
  final DateTime date;
  final String lunar;
  final String lunarShort;
  final String yearName;
  final String solarTerm;
  final List<String> festivals;
  final HolidayInfo? holiday;
  final bool holidayYearKnown;
  const CalendarDay({
    required this.date,
    required this.lunar,
    required this.lunarShort,
    required this.yearName,
    required this.solarTerm,
    required this.festivals,
    required this.holiday,
    required this.holidayYearKnown,
  });
  String get week =>
      '星期${const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';
  String get smallLabel => solarTerm.isNotEmpty
      ? solarTerm
      : festivals.isNotEmpty
      ? festivals.first
      : lunarShort;
}

class CalendarService {
  final Map<String, HolidayInfo> _holidays = {};
  final Map<String, CalendarDay> _cache = {};
  final Set<int> holidayYears = {};
  Future<void> load() async {
    for (final year in [2025, 2026]) {
      final j =
          jsonDecode(await rootBundle.loadString('assets/holidays/$year.json'))
              as Map<String, dynamic>;
      loadHolidayJson(j);
    }
  }

  void loadHolidayJson(Map<String, dynamic> j) {
    validateHolidayJson(j);
    _holidays.removeWhere((key, _) => key.startsWith('${j['year']}-'));
    holidayYears.add(j['year'] as int);
    for (final d in j['days'] as List) {
      _holidays[d['date'] as String] = HolidayInfo(
        d['name'] as String,
        d['isOffDay'] as bool,
      );
    }
    _cache.clear();
  }

  bool? isRestDay(DateTime date) {
    if (!holidayYears.contains(date.year)) return null;
    return _holidays[dateKey(date)]?.isOffDay ??
        date.weekday >= DateTime.saturday;
  }

  bool? allowsDate(
    DateTime date,
    HolidayPolicy policy,
    WeekendHolidayPriority priority,
  ) {
    if (policy == HolidayPolicy.ignore) return true;
    final weekendOnly =
        policy == HolidayPolicy.onlyWeekends ||
        policy == HolidayPolicy.skipWeekends;
    if (!weekendOnly && !holidayYears.contains(date.year)) return null;
    final special = _holidays[dateKey(date)];
    var holiday = special?.isOffDay == true;
    var weekend =
        date.weekday >= DateTime.saturday && special?.isOffDay != false;
    if (holiday && weekend) {
      if (priority == WeekendHolidayPriority.holiday) {
        weekend = false;
      } else {
        holiday = false;
      }
    }
    return switch (policy) {
      HolidayPolicy.ignore => true,
      HolidayPolicy.skip => !holiday && !weekend,
      HolidayPolicy.only => holiday || weekend,
      HolidayPolicy.skipHolidays => !holiday,
      HolidayPolicy.skipWeekends => !weekend,
      HolidayPolicy.onlyWeekends => weekend,
      HolidayPolicy.onlyHolidays => holiday,
    };
  }

  CalendarDay info(DateTime date) => _cache.putIfAbsent(dateKey(date), () {
    final solar = Solar.fromDate(date);
    final lunar = solar.getLunar();
    final month = '${lunar.getMonthInChinese()}月';
    final day = lunar.getDayInChinese();
    final festivals = {
      ...solar.getFestivals(),
      ...lunar.getFestivals(),
    }.toList();
    return CalendarDay(
      date: dayOnly(date),
      lunar: '$month$day',
      lunarShort: day == '初一' ? month : day,
      yearName: '${lunar.getYearInGanZhi()}${lunar.getYearShengXiao()}年',
      solarTerm: lunar.getJieQi(),
      festivals: festivals,
      holiday: _holidays[dateKey(date)],
      holidayYearKnown: holidayYears.contains(date.year),
    );
  });
  ({String name, DateTime date}) nextTerm(DateTime date) {
    final term = Solar.fromDate(date).getLunar().getNextJieQi(true);
    return (
      name: term.getName(),
      date: DateTime.parse(term.getSolar().toYmd()),
    );
  }
}

void validateHolidayJson(Map<String, dynamic> j, {int? expectedYear}) {
  final year = j['year'], days = j['days'];
  if (year is! int ||
      year < 1901 ||
      year > 2099 ||
      expectedYear != null && expectedYear != year ||
      days is! List ||
      days.isEmpty ||
      days.length > 400) {
    throw const FormatException('假期数据格式或年份无效');
  }
  final seen = <String>{};
  for (final day in days) {
    if (day is! Map ||
        day['name'] is! String ||
        (day['name'] as String).isEmpty ||
        (day['name'] as String).length > 80 ||
        day['date'] is! String ||
        day['isOffDay'] is! bool) {
      throw const FormatException('假期条目无效');
    }
    final date = DateTime.tryParse(day['date'] as String);
    if (date == null ||
        date.year != year ||
        dateKey(date) != day['date'] ||
        !seen.add(day['date'] as String)) {
      throw const FormatException('假期日期无效或重复');
    }
  }
}
