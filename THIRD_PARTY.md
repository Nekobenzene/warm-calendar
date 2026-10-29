# 开源依赖与数据来源

- Flutter：BSD-3-Clause，<https://github.com/flutter/flutter>。本地 SDK 从官方 stable 源码归档引导，官方标签 `3.47.8` 对应源码提交 `737ba8f885dc774b53b442759999a312c9461e4e`；引擎资源由 Flutter 官方中国镜像获取。归档的本地 Git 元数据仅用于工具引导，不代表原仓库提交历史。
- lunar：MIT，<https://github.com/6tail/lunar-flutter>。用于农历、节日、节气计算。
- Drift / drift_flutter：MIT，<https://github.com/simolus3/drift>。用于 SQLite 数据访问。
- sqlite3.dart：MIT，<https://github.com/simolus3/sqlite3.dart>。Web WASM 来自 sqlite3-3.5.2 官方发行，与当前锁定包版本一致。
- file_selector：BSD-3-Clause，Flutter 官方插件仓库 <https://github.com/flutter/packages>。
- flutter_local_notifications_windows：BSD-3-Clause，<https://github.com/MaikuB/flutter_local_notifications>，用于Windows通知身份及COM激活回调；任务排定、取消和错误返回使用项目内WinRT接口。
- flutter_local_notifications：BSD-3-Clause，同一仓库，用于Android系统定时通知、通知分类、运行时权限和点击回调。
- flutter_timezone：Apache-2.0，<https://github.com/tjarvstrand/flutter_timezone>，读取Android本机IANA时区；timezone：BSD-2-Clause，<https://github.com/srawlins/timezone>，用于定时通知时区转换及IANA数据库。
- window_manager / tray_manager：MIT，<https://github.com/leanflutter/window_manager>、<https://github.com/leanflutter/tray_manager>，用于窗口及系统托盘。
- Windows桌面分发附带微软Visual C++可再发行运行库，来源为官方Visual Studio Build Tools的Redist目录；不包含编译工具。
- Noto Sans SC：SIL Open Font License 1.1，<https://github.com/google/fonts/tree/main/ofl/notosanssc>。许可正文保存在 `assets/fonts/OFL.txt`。
- 2025年节假日与调休数据：MIT，<https://github.com/NateScarlet/holiday-cn/blob/master/2025.json>；原始公告<https://www.gov.cn/zhengce/zhengceku/202411/content_6986383.htm>。
- 2026 年节假日与调休数据：MIT，<https://github.com/NateScarlet/holiday-cn/blob/master/2026.json>。JSON 中保留原始公告来源：<https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm>。数据是第三方对官方公告的结构化整理，不把该仓库当成政府发布渠道。

实际依赖版本以 `pubspec.lock` 为准。Flutter 构建结果包含其生成的第三方许可清单；分发时应一并保留。

设备连接依赖：

- http / crypto：BSD-3-Clause，Dart 官方 <https://github.com/dart-lang/http>、<https://github.com/dart-lang/core>，HTTP 通信及相关密码学工具。
- qr_flutter（BSD-3-Clause）及 qr（BSD-3-Clause）：<https://github.com/theyakka/qr.flutter>，本地生成二维码，不调用外部二维码服务。
- mobile_scanner：BSD-3-Clause，<https://github.com/juliansteenbakker/mobile_scanner>，Android 相机扫码，使用随包 ML Kit 扫描库。
- flutter_secure_storage：BSD-3-Clause，<https://github.com/mogol/flutter_secure_storage>，设备凭据安全存储。
- workmanager：MIT，<https://github.com/fluttercommunity/flutter_workmanager>，Android 有网络约束的后台周期同步。
- path_provider：BSD-3-Clause，Flutter 官方 <https://github.com/flutter/packages>，定位系统应用目录。
- Node.js 24.19.0：MIT 及其随附第三方许可，<https://github.com/nodejs/node>。Windows 包的 `sync-service/` 随附官方 Node 运行时和 `NODE-LICENSE.txt`，同步服务使用内置 `node:sqlite`，无额外 npm 依赖。
- Windows安装向导：Inno Setup 6.7.4，官方发行<https://github.com/jrsoftware/issrc/releases/tag/is-6_7_4>，许可<https://jrsoftware.org/files/is/license.txt>。保留安装引擎原始版权与网站信息；本项目未改动安装引擎。简体中文翻译来自同标签`Files/Languages/Unofficial/ChineseSimplified.isl`，保留维护者署名。工具只用于构建，不随应用安装编译器。

自动更新复用同一holiday-cn仓库的年度JSON，经HTTPS获取；raw.githubusercontent.com不可达时使用jsDelivr镜像。下载校验年份、日期及条目，JSON保留公告来源；空占位或404不视为已公布，不推算法定放假。
