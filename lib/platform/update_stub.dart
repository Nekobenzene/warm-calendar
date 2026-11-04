import '../domain/app_update.dart';
import 'package:http/http.dart' as http;

const updateTarget = 'web';
http.Client createUpdateClient() => http.Client();
Future<String> downloadUpdate(
  UpdateRelease release,
  void Function(int) progress,
  bool Function() cancelled,
) async => throw const FormatException('请使用桌面或安卓安装版更新');
Future<void> installUpdate(String path) async =>
    throw const FormatException('浏览器预览不执行安装');
