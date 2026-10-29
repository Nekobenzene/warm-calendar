import 'dart:convert';
import 'package:http/http.dart' as http;
import 'calendar_service.dart';

/// The upstream repository transcribes published government notices. A 404
/// means no published schedule here, never a reason to invent a future one.
Future<Map<int, Map<String, dynamic>>> fetchHolidayData(
  Set<int> years, {
  http.Client? client,
}) async {
  final owns = client == null;
  final source = client ?? http.Client();
  try {
    final result = <int, Map<String, dynamic>>{};
    for (final year in years.toList()..sort()) {
      if (year < 1901 || year > DateTime.now().year + 1) continue;
      http.Response? response;
      for (final host in [
        'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master',
        'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master',
      ]) {
        try {
          response = await source
              .get(Uri.parse('$host/$year.json'))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) break;
        } catch (_) {
          response = null;
        }
      }
      if (response?.statusCode == 404) continue;
      if (response?.statusCode != 200) {
        throw const FormatException('假期更新暂不可用，请检查网络后重试');
      }
      if (response!.bodyBytes.length > 100000) {
        throw const FormatException('假期数据过大');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('假期数据格式无效');
      }
      // The repository also contains empty files for unpublished future years.
      if (value['year'] == year &&
          value['days'] is List &&
          (value['days'] as List).isEmpty &&
          value['papers'] is List &&
          (value['papers'] as List).isEmpty) {
        continue;
      }
      validateHolidayJson(value, expectedYear: year);
      result[year] = value;
    }
    return result;
  } finally {
    if (owns) source.close();
  }
}
