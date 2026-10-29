# 日程表交接

更新于2026-10-29。项目 `D:\projects\日程表`，Flutter/Dart，Git主分支main，远端为 https://github.com/Nekobenzene/warm-calendar 。当前版本0.5.0+5。历史记录存于 `verification/HANDOFF-before-0.5.md`，其中旧限制不代表当前状态。界面规范见 `DESIGN.md`，数据来源见 `THIRD_PARTY.md`。

## 仓库、发布与本机更新

- 源码和测试提交Git，安装包只放GitHub Releases；入口 https://github.com/Nekobenzene/warm-calendar/releases/latest 。版本标签v0.5.0，发布说明见 `releases/0.5.0.md`，后续发布流程见 `RELEASING.md`。
- `.gitignore`排除工具缓存、安装包、数据库、验证记录、Android签名与其他私钥文件；签名密钥仍仅保存在本机忽略目录，不上传。
- 本机已通过正式安装向导安装0.5.0到 `%LOCALAPPDATA%/Programs/WarmCalendar`，桌面“日程表”快捷方式已更新，保留既有自启动选择。日程与配对数据在原用户数据目录，安装未修改数据库。
- `dist/releases/0.5.0/`仅保存Windows安装向导、Android APK和SHA256SUMS.txt。历史构建和旧便携目录移入 `dist/archive/2026-10-29/`，可恢复，没有删除。`dist/README.md`说明当前目录。
- `scripts/prepare-release.ps1`按pubspec版本生成统一英文附件名，拒绝同版本不同内容的覆盖，不改运行目录。GitHub CLI官方便携工具位于忽略的 `.tooling/github-cli`，使用现有账号凭据，未把令牌写入仓库。

## 本轮0.5.0

- 日/周时间轴滚到边缘后将剩余滚轮/触摸位移交给外层页面，上下均支持。最终边界短暂阴影，手机轻微纵向拉伸；系统减少动画设置禁用拉伸。
- 手机滚动保持选中，仅区域外真实点击取消。详情180ms展开并完成下一帧布局后将选中日程滚到可见处，再按最终外层视窗补偿、定位Popover，避免末端/午夜时间点遮挡。减少动画模式使用jumpTo，避免零时长animateTo断言。离开日历卸载滚动内容但保留日期/模式。
- 整体/起止边界拖动支持上下跨午夜及横向跨日，边缘自动滚动。负分钟用DateTime规范化。目标全列宽半透明填色，无边框，覆盖其他事项；原块透明，仅保留选中框。放下后恢复冲突分列，全天改期也有预览。重复仍询问本次/全部/取消，失败原子回滚。
- 最细1分钟分度；小时像素36/60/96/144/240/480/720，对应60/30/15/15/5/5/1分钟。1/5/60分钟线依次细浅/中等/较粗深。工具栏“分度”字体略大粗，加减圆角方框、日期箭头胶囊框；锁有可选中/不可选中旁注，手机位于分度行右侧。
- 提醒横幅减少上下留白。系统通知标题为日程标题，正文含多久后开始、完整开始日期时间；即时回退与排定队列共用格式。
- 成功toast用主题色勾；失败用红褐色叉、浅红边框及微红底，包括通知授权失败。280ms上移淡入，停1500ms，220ms下移淡出，遵循减少动画设置。
- 外观：8预置色、经典色相带、饱和度12%—40%、明暗38%—56%。派生画布、侧栏、按钮、文字强调、边框、横幅和选中底；强调色对白字及选中底对比度≥4.5。默认原暖浅绿。缓存ThemeData，避免时钟刷新反复主题动画。
- 本机PNG/JPG/WebP背景，来源≤20MB，长边缩至1440，转PNG≤4MiB后存base64。主区与侧栏/手机底栏分别调0—30模糊、0—65%图片明显程度，内容面板实底保证可读。支持清除/恢复默认；滑杆松开后应用持久化。照片只在本机及用户导出的备份，不随配对同步。
- 设置平铺六类：外观、日历、日程与提醒、设备与同步、数据与备份、关于。设备名1—60字、本机独立，联网更新对端列表。仅逾期自动完成跨设备共享，其他界面/通知偏好独立。

## 日历数据

- 公历/星期/农历/常见节日/节气由lunar离线计算，日期范围1901—2099，无需逐日静态存2030/2050数据。新增测试覆盖2027—2050每年12个月的农历、下一节气与国庆节。
- 法定放假调休无法用历法预测。内置 `assets/holidays/2025.json`、`2026.json`，MIT的NateScarlet/holiday-cn，保留政府公告链接。已检查上游2027.json为papers/days空数组占位，未打包且不标已收录。2030/2050法定放假未公布，不能编造。
- 默认每天联网检查当年前后一年。设置→日历可关闭自动检查或立即更新；显示已收录年份/上次成功检查/实际错误。后台首次检查不阻塞页面，失败当天不反复刷，可手动重试；后台成功不弹toast。
- HTTPS raw.githubusercontent.com/NateScarlet/holiday-cn/master，不可达时jsDelivr镜像。每请求8秒、100KB上限；严格校验年份/规范化日期/不重复/条目类型与数量。404或空占位跳过，坏数据不替换缓存。替换年度前清旧条目，防残留。
- `AppSettings.holidayCache`保存年度JSON，启动载入；失败继续用有效缓存。更新串行保存后清实例缓存/续排提醒。假期筛选重复规则仍禁止使用未知年份，不把未知当工作日。

## 验证与交付

- `verification/tests-0.5-final.log`：完整80项Flutter测试全部通过。包含真实HTTP双客户端同步、SQLite事务回滚、颜色/重复/提醒旧回归；新15项覆盖主题全色相对比度、背景像素渲染/清除、手机详情避让/选中、滚轮及触摸上下滚动交接、跨日边界全宽预览、1分钟/锁旁注、错误toast和2027—2050离线历法。预期失败注入日志及双独立数据库debug提示不代表测试失败。
- 最终修正后 `verification/tests-0.5-final-fixes.log`：29项相关回归通过（本轮19项＋手机布局4项＋日历交互6项）。额外涵盖背景导入缩放/坏图、整页滚轮边缘反馈、末端时间点的正常/减少动画两种模式；不为局部修复重复整套无关测试。实际浏览器发现旧ImageDescriptor尺寸接口在Web不可用，已统一为instantiateImageCodecWithSize，最终构建实际导入成功。
- `verification/analyze-0.5-final.log`：No issues found。`verification/build-web-0.5.log`：release成功，字体与渲染资源随包。服务端本轮无改，上一轮9项Node测试适用，无重复执行。
- 新两端版本、文件大小/哈希与签名状态见 `dist/release-0.5.0.json`。安装EXE `dist/日程表-Setup-0.5.0-x64.exe`；完整Windows目录 `dist/日程表Windows-0_5_0`及同名ZIP；APK `dist/日程表-Android-0.5.0.apk`与通用名 `日程表-Android.apk`一致。
- 0.5.0初次构建未覆盖运行中的旧便携版；随后用户退出应用后已用同一安装向导升级本机，并归档旧目录，见上方发布记录。Android沿用原密钥覆盖安装，勿先卸载。
- 实际浏览器布局与截图记录见 `verification/visual-0.5.md`，隔离端口4181/4182，不向正式4173写测试事项。无连接Android真机，系统横幅/声音/振动、多指与厂商后台策略未宣称实机通过；模拟手势及原生通知参数有测试。
- Windows仍无正规代码签名证书，应用/安装器无受信任签名；不调整智能应用控制或杀毒。用户此前反馈现有环境通知正常，不等于签名问题已解决。

## 稳定架构与数据约定

- SQLite schema1，事件/设置存JSON，无SQL迁移。备份v3兼容1/2，事务合并，同ID按修改时间保留新版本和删除状态。导入保留本机自启动选择。不得清用户数据库、安全存储、同步数据。
- 首页时间/日期/星期/UTC/农历，下一项固定最近一条未来未完成，四状态只当天（跨日相交计入）。日程页所有日期，卡片正文不编辑，只通过三点菜单；删除先确认。
- 桌面周/月、手机日/周/月；周七天宽连续横滑，手机只色块。箭头/今天440ms easeInOutCubic对齐完整周，月固定六行横滑。手机底部导航，600—899紧凑左栏，900以上完整左栏。
- 桌面单击选中，再点编辑；5px起拖、上下7px边界。手机点击/长按选中，9px阈值/10px边界，Popover选择拖动后可移动/调边界。锁仅本机，禁止选中/拖动/编辑，允许滚动/缩放/换日期。旧calendarDragEnabled/upcomingRows仅兼容读取。
- 定时/跨日/全天/零时长点、独立未完成/完成ARGB颜色（完成默认灰）。同色相邻分割；连通冲突固定列、每事项连续；实际重叠红虚线、偏红改黄线。文字按色块合成背景取对比色。
- 重复每日多次/每周多天/每月多日/间隔日，最多24时间点，必有截止日期，系列≤10000次。按设备本地日期展开；假期无视/跳过/只取，周末计休息、调休上班优先。稳定实例ID，单次例外覆盖模板，整组shiftMinutes平移不复活例外。无固定时区旅行规则。
- 每次最多12提醒，提前0—365天。Windows未来30天最近512条，Android128条，前台每分钟续排，Android后台同步也续排。排定失败运行期间即时回退、成功任务去重；退出后不续排。关机/休眠/强停/权限可能影响送达。
- Android通知走通知音量，high importance/priority，reminder类别；声音×振动四类尊重系统设置。精确权限可用时exactAllowWhileIdle，否则非精确并提示延迟；BOOT/升级恢复排定，不用全屏意图/绕过勿扰。
- 局域网协议2，电脑Node HTTP+SQLite，扫码120秒令牌/电脑确认，前台约2秒轮询，Android后台≥15分钟可推迟。按服务URL保存安装证明，重连复用deviceId并轮换活动令牌，主动解绑再扫码。无证明的同名历史记录不擅自合并；原地址可达自动续连，公网/网络发现/IP迁移未实现。暂无并发冲突合并。
- 共享设置dirty/changeId保证上传中旧ACK不清新修改，只同步autoCompleteExpired。设备名独立接口更新。

## 安装器与开发入口

- `installer/calendar.iss`、Inno6.7.4官方便携编译器在 `.tooling/inno-6.7.4`。AppId `WarmCalendar.Planner.Desktop`；当前用户安装、不需管理员，自选目录/桌面和开始菜单快捷方式及位置/自启/完成运行。静默不启动；AppMutex阻止覆盖运行程序。升级/卸载仅停止同安装目录sync-service，不碰其他Node。
- 共用HKCU Run/WarmCalendar，应用启动读实际启动项，防旧偏好覆盖安装选择。卸载保留日程/设置/配对，移除快捷方式/启动项。上一轮32项真实安装/升级/卸载、4项启动查询测试通过，本轮安装器行为无改。
- `scripts/flutter.ps1`用项目SDK/缓存及TEMP ASCII联接，处理中文路径，不改全局Git。不要打印 `.tooling/signing/key.properties`。Android必须沿用JKS，证书SHA256 `fe006cfdf4c4bb284b7ecfd7c6ba47572329bc5d335811fd337f63b63ef733ed`。

```powershell
.\scripts\flutter.ps1 analyze --no-pub
.\scripts\flutter.ps1 test --no-pub --reporter expanded
.\scripts\flutter.ps1 build web --no-pub --release --no-web-resources-cdn --no-wasm-dry-run
.\scripts\build-desktop.ps1 -PackageName '日程表Windows-0_5_0'
.\scripts\build-installer.ps1 -PackageDirectory 'dist/日程表Windows-0_5_0'
.\scripts\build-android.ps1
```

| 入口 | 责任 |
| --- | --- |
| lib/domain/models.dart | 事件/设置/备份；外观图片和假期缓存 |
| lib/domain/calendar_service.dart / holiday_update.dart | 离线历法、法定假期校验/下载/载入 |
| lib/domain/recurrence.dart / calendar_layout.dart / time_axis.dart | 重复/冲突/分度和跨日换算 |
| lib/domain/reminders.dart | 队列计划和系统通知文本 |
| lib/app_controller.dart | 串行写入、提醒回退/续排、自动完成/假期更新 |
| lib/ui/calendar_page.dart / calendar_blocks.dart | 选中、手势、滚动交接、预览/保存 |
| lib/ui/scroll_feedback.dart | 最终视窗边界阴影/拉伸 |
| lib/ui/appearance.dart / theme.dart | 图片处理/独立毛玻璃/主题 |
| lib/ui/settings_page.dart / holiday_settings.dart | 设置分类与假期更新 |
| lib/ui/shell.dart / toast.dart | 导航/详情/横幅/成功失败提示 |
| lib/platform/ | 三端通知/权限/托盘 |
| lib/sync/ / sync-server/ | 凭据/共享设置/重连/后台同步/本机服务 |
| test/release_05_test.dart | 本轮19项新回归，其余test保留既有回归 |

`.tooling`内一次性改源码/文档脚本已执行，勿重复执行。以实际源码和本文件为准。MSB8029临时联接、依赖的Cupertino字体/Kotlin迁移提示没有导致本轮构建失败，不通过改安全设置处理。
