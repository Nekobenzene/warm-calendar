import 'dart:convert';
import 'package:http/http.dart' as http;
import 'link_models.dart';

class LinkApi {
  final http.Client client;
  LinkApi({http.Client? client}) : client = client ?? http.Client();
  Future<Map<String, dynamic>> call(
    Uri server,
    String path, {
    String? credential,
    Map<String, dynamic>? body,
  }) async {
    final uri = server.resolve(path);
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (credential != null) 'Authorization': 'Bearer $credential',
      };
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..headers.addAll(headers)
        ..followRedirects = false;
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 12));
      if (response.bodyBytes.length > 10 * 1024 * 1024) {
        throw const LinkFailure('服务返回的数据过大');
      }
      final result =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LinkFailure(
          result['error'] as String? ?? '服务请求失败',
          response.statusCode,
        );
      }
      return result;
    } on LinkFailure {
      rethrow;
    } catch (_) {
      throw const LinkFailure('无法连接同步服务，请检查服务地址和网络');
    }
  }

  void close() => client.close();
}
