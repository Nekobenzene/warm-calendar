# 日程表交接

更新于2026-11-04。项目 `D:\projects\日程表`，Flutter/Dart，Git主分支main，远端为 https://github.com/Nekobenzene/warm-calendar 。当前正式源码为0.6.0+7。历史记录存于 `verification/HANDOFF-before-0.5.md`，其中旧限制不代表当前状态。界面规范见 `DESIGN.md`，数据来源见 `THIRD_PARTY.md`。

## 本轮0.6.0正式发布与本机升级

用户已确认预览无问题，明确授权推送、发布及更新本机为0.6.0（已确认不是0.0.6）。pubspec.yaml和lib/version.dart同步为正式版本，Android构建号7；正式版继续用原包名、数据库、设备凭据、Windows通知身份和4280同步端口。独立预览及其数据保留，正式版不自动导入预览日程。

- 正式Windows、安装向导和APK重新构建；5项更新模块相关测试及静态分析通过，见`verification/*-0.6-release.log`。完整功能的56项相关Flutter测试、10项服务测试及收尾14项复查沿用下方记录，没有重新跑无关全套。
- APK实际核对包名`com.tangtang.warm_calendar`、版本0.6.0/code7、名称“日程表”；证书SHA256仍为原发布证书fe006cfdf4c4bb284b7ecfd7c6ba47572329bc5d335811fd337f63b63ef733ed，可覆盖旧正式版。
- 本机原`%LOCALAPPDATA%/Programs/WarmCalendar`已通过安装向导升级为0.6.0并重新运行。保留原安装目录、快捷方式配置及自启动选择；没有编辑/导入/清理个人日程。日志确认安装成功，卸载记录显示0.6.0，已安装主程序哈希与正式构建一致，见`verification/install-official-0.6.log`及`installed-official-0.6.json`。
- 正式附件在`dist/releases/0.6.0/`，仅Windows安装器、Android APK、SHA256SUMS.txt。发布说明`releases/0.6.0.md`，版本标签v0.6.0，发布入口 https://github.com/Nekobenzene/warm-calendar/releases/tag/v0.6.0 。源码/标签推送main，安装包仅上传Release，不提交工具、凭据、密钥、个人数据库及验证记录。
- Windows应用与安装器仍无受信任代码签名。Android真机通知及从应用内下载到安装完成的完整升级流程仍待实机验收；本机本次验证的是安装器从0.5.0升级至0.6.0。

以下为先前独立预览阶段记录；其中“尚未发布”“未提交”只描述当时状态。

## 本轮0.6本地预览（优先于下方0.5历史说明）

用户要求先交付本地预览，暂不发布。改动尚未提交/推送；没有修改正式安装目录，也没有触发 localhost 文件上传流程。安装包放在 `dist/previews/0.6.0-preview.1/`：`warm-calendar-0.6.0-preview.1-windows-x64-setup.exe`、`windows/warm_calendar.exe`、完整便携压缩包 `windows.zip`、独立 Android APK、校验清单及预览说明。本机已更新独立预览安装，默认开始菜单“日程表 · 本地预览”可打开；没有新增桌面快捷方式或开启自启动。

- 更新：设置→关于提供自动检查、手动检查、下载/取消/重试/继续安装及百分比/MB进度。默认启动及每6小时查本仓库 GitHub 正式 latest；严格匹配平台附件、HTTPS仓库路径、尺寸和GitHub SHA256摘要，下载流校验后才调用安装。Windows复用现有代理设置；Android走FileProvider及系统安装来源授权，不能跳过系统确认。正式模式 Windows 用现有安装目录与 `/SILENT /UPDATE=1` 参数，安装完成重启。预览模式只下载，不执行升级，防止影响正式版。已只读核实v0.5.0资产命名及digest与解析器一致；不能从0.6预览降级到0.5。
- 三种模式：不重复保留原表单；重复日程添加规则/默认假期入口；重复周期独立组标题、频率、左日期/右节点、开始/停止日期或轮数、全局备注。每日无左列；多日Day1起计，每周可切周一至周日，月按当月日期，短月缺日跳过。两列各自滚动，窄屏及大字保持保存/取消可见。
- 节点最多96个，每个可编辑标题、起止日/时间、点型、全天、两色、备注、提醒次数/提前量/声音与假期策略；第一节点可编辑。新节点复用最后一个已添加节点除标题/备注外设置，生成新ID，不能继承旧实例key。允许跨日，节点时长≤周期（月循环按最短28天限制）；组最多10000个展开实例。
- 每个周期节点按起点所属日归属。停止日期含当日起点；轮数含首轮，周名模式首轮可不足整周，假期跳过不补轮。新实例key为锚点日期加稳定nodeId，改时间仍保留单次处理状态；旧多时间点迁移保留legacyMinute key。删除/完成/改期沿用单次例外，整组边界调整只改变目标节点时长，其他节点独立设置保留，失败原子回滚。
- 标题统一为组标题-节点标题，空节点标题用组标题；备注为节点备注、全局备注两行。列表及手机详情显示两行，系统提醒正文也包含组合备注与多久后/开始时间。
- 七类假期：无视、跳过两者、仅跳过假期、仅跳过周末、仅两者、仅周末、仅假期；周末假期可归为其中一类，调休上班优先。依赖假期的规则遇未知年份拒绝保存，不悄悄过滤。纯周末规则可按星期计算。修改默认假期保留已偏离默认值的节点设置，节点仍可独立编辑。
- 日历选中后有删除入口，手机Popover也有；重复继续询问单次/整个。点型为水平线与左侧下垂圆角标签，没有边界手柄，只能整体拖动和编辑；拖动原位只留选中框，目标仍为线/标签。点型不制造虚假一分钟冲突。时间轴新增12/24像素每小时档、120分钟分度，最小档随可用视窗容纳24小时。
- Surface改用Material描边底板，修正ListTile点击反馈被底色遮住的问题。没有改主题风格。
- 同步服务支持组合标题/备注和完整节点规则。单记录≤1.5MiB，请求/响应按约1.8MiB分批，仍最多100项，避免多节点备注较长时同步卡住；旧协议2兼容。Android后台排提醒也载入已缓存的假期表。

### 预览身份与验证

- `lib/version.dart`维护版本及预览身份；包含`-preview`的版本自动使用独立`warm_calendar_preview`数据库、预览凭据。Windows C++按FLUTTER_VERSION选择独立Preview互斥；通知AUMID为`WarmCalendar.Planner.Preview`，激活CLSID尾号8812，自启动键`WarmCalendarPreview`，不再复用旧Verification身份。本机服务独立4281端口及`sync-service-preview`目录。正式4280和数据库不变。
- Android Gradle按版本自动生成 `com.tangtang.warm_calendar.preview`、名称“日程表·预览”，可与正式版并存；后台与前台使用同一预览数据库/凭据。APK经aapt核对实际包名/版本，签名SHA256仍为下文原密钥。未连接Android真机，不宣称系统安装、更新、声音/振动实机验收。
- `verification/tests-0.6-final.log`：56项相关Flutter测试通过（新重复/更新/UI与旧重复/日历交互/手机布局/提醒/同步），没有重跑无关全套。真实本地HTTP流下载覆盖进度、缓存、坏摘要及残留清理，安装调用使用假实现，不执行真实升级。
- `verification/sync-server-0.6.log`：10项服务端测试通过，包含96个长备注节点、字节分页及组合文本。
- `verification/analyze-0.6-final.log`：No issues found。Web/Windows/Android release构建分别见build-*-0.6.log。收尾修复后仅重跑提醒及本轮UI两个相关测试文件，14项通过（与前述56项有重叠，不相加），见`tests-0.6-notification-fix.log`；Windows及APK重新编译。
- Windows独立预览安装器已实际运行并退出0，安装目录`%LOCALAPPDATA%/Programs/WarmCalendarPreview`，记录见`verification/install-preview-0.6.log`；只选择开始菜单快捷方式，未开自启动。只读核对正式安装记录仍为0.5.0及原目录。未执行真实版本升级；Windows/Android更新安装流程仍待端到端验收。
- 首次通知修复：安装快捷方式本身并未解决`permission: 0x80070490`。已确认Windows在应用首次发通知前可能尚无对应通知状态项；只对Setting查询的ERROR_NOT_FOUND返回`unregistered`（界面“待首次通知确认”），不中断托盘或排队初始化，其他错误仍抛出。应用明确设置进程AUMID及有效图标路径。全新Preview身份启动没有初始化错误；从应用内发测试提醒后，系统权限为Enabled，Windows通知历史含该测试内容及提示音XML，见`verification/preview-notification-native.log`。这不等同于已听到提示音或观察到横幅，也未重新验收所有定时场景。
- 实际网页在独立4183端口查看1280×800桌面周期编辑和390×844手机节点表单，保存按钮与主要字段均可见，浏览器无错误日志；截图 `verification/preview-06-cycle.png`、`verification/preview-06-mobile-node.jpg`。未上传文件或向正式4173写数据。临时网页草稿未保存并关闭；Windows独立预览窗口保留供查看。已安装主程序哈希与交付包一致（`verification/installed-preview-0.6.json`）。

复现构建：`scripts/build-desktop.ps1 -OutputDirectory dist/previews/0.6.0-preview.1/windows`；`scripts/build-android.ps1 -OutputPath dist/previews/0.6.0-preview.1/warm-calendar-0.6.0-preview.1-android.apk`。正式发布前同时更新pubspec.yaml和lib/version.dart，去掉preview标识，再验证真实安装升级；不要将此便携预览当正式Release附件。

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
- 初次构建清单已归档为 `dist/archive/2026-10-29/release-0.5.0.json`，其中记录的是归档前路径。完整Windows构建及旧名APK也在该归档目录。当前正式安装包在 `dist/releases/0.5.0/`，采用 `warm-calendar-0.5.0-windows-x64-setup.exe`、`warm-calendar-0.5.0-android.apk`统一名称，并附SHA256SUMS.txt。
- GitHub Release https://github.com/Nekobenzene/warm-calendar/releases/tag/v0.5.0 已正式发布并设为latest。两个安装包及校验文件均逐一核对GitHub资产SHA256与本地一致。本机安装的data/app.so也与已发布Windows构建逐字节哈希一致，已正常启动进入设置页。
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
