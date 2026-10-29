# 日程同步服务

Node.js 24、内置 HTTP 与 SQLite，无额外依赖。运行、配对、安全边界及公网 HTTPS 部署要求见项目根目录 [LINKING.md](../LINKING.md)。

从项目根目录启动：`node sync-server/server.mjs`。测试：`node --test sync-server/server.test.mjs`。

默认监听 127.0.0.1:4280。每个桌面设备拥有独立数据组，Android 必须通过短期邀请并经桌面确认才能加入。上传按服务端到达顺序覆盖同 ID 记录；游标分页获取变化，软删除保留，暂不解决并发冲突。

设备凭据与邀请使用 256 位随机值，持久化摘要；服务数据库含日程明文及设备信息，应置于可信目录并妥善备份。公开部署须在 HTTPS 代理后使用。服务不写请求凭据日志。`NODE-LICENSE.txt` 为随桌面包分发的 Node.js 运行时许可证。
