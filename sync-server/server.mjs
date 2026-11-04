import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const token = () => randomBytes(32).toString('base64url');
const id = () => randomBytes(16).toString('hex');
const digest = value => createHash('sha256').update(value).digest('hex');
class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const requireValue = (condition, status, message) => {
  if (!condition) throw new ApiError(status, message);
};

/** No external dependencies. Bind loopback by default; TLS belongs at the proxy. */
export function createSyncServer({ database = ':memory:', allowedOrigins = [], now = () => Date.now() } = {}) {
  if (database !== ':memory:') mkdirSync(dirname(resolve(database)), { recursive: true });
  const db = new DatabaseSync(database);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS groups (id TEXT PRIMARY KEY, sequence INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL,
      name TEXT NOT NULL, platform TEXT NOT NULL, group_id TEXT NOT NULL, owner INTEGER NOT NULL, seen INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS invites (hash TEXT PRIMARY KEY, owner_id TEXT NOT NULL, expires INTEGER NOT NULL, claimed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, mobile_id TEXT NOT NULL,
      expires INTEGER NOT NULL, code TEXT NOT NULL, status TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS events (group_id TEXT NOT NULL, id TEXT NOT NULL,
      payload TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(group_id,id));
    CREATE TABLE IF NOT EXISTS registrations (id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, device_id TEXT NOT NULL UNIQUE);
    CREATE TABLE IF NOT EXISTS group_settings (group_id TEXT PRIMARY KEY, auto_complete INTEGER NOT NULL);`);
  const get = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const transaction = action => {
    db.exec('BEGIN IMMEDIATE');
    try { const result = action(); db.exec('COMMIT'); return result; }
    catch (error) { db.exec('ROLLBACK'); throw error; }
  };
  const rates = new Map();
  function publicDevice(row) {
    return { id: row.id, name: row.name, platform: row.platform, owner: !!row.owner, lastSeen: row.seen };
  }
  function state(device) {
    const devices = all('SELECT * FROM devices WHERE group_id=? ORDER BY owner DESC, name', device.group_id);
    return { protocol: 2, device: publicDevice(device), groupId: device.group_id,
      linked: device.owner ? devices.length > 1 : devices.some(d => d.owner),
      devices: devices.map(publicDevice) };
  }
  function registration(input) {
    requireValue(typeof input.installationId === 'string' && /^[a-f0-9]{32}$/.test(input.installationId) &&
      typeof input.installationSecret === 'string' && /^[A-Za-z0-9_-]{43}$/.test(input.installationSecret), 400, '设备安装标识无效');
    const saved = get('SELECT * FROM registrations WHERE id=?', input.installationId);
    if (saved) requireValue(timingSafeEqual(Buffer.from(saved.secret_hash), Buffer.from(digest(input.installationSecret))), 403, '设备安装凭据无效');
    return saved;
  }
  function authenticate(request) {
    const match = /^Bearer ([a-f0-9]{32})\.([A-Za-z0-9_-]{43})$/.exec(request.headers.authorization ?? '');
    const device = match && get('SELECT * FROM devices WHERE id=?', match[1]);
    requireValue(device && timingSafeEqual(Buffer.from(device.secret_hash), Buffer.from(digest(match[2]))), 401, '设备凭据无效，请重新连接');
    run('UPDATE devices SET seen=? WHERE id=?', now(), device.id);
    return device;
  }
  async function body(request) {
    const chunks = []; let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      requireValue(size <= 2 * 1024 * 1024, 413, '请求过大');
      chunks.push(chunk);
    }
    try {
      const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
      requireValue(parsed && typeof parsed === 'object' && !Array.isArray(parsed), 400, '请求格式错误');
      return parsed;
    } catch (error) { if (error instanceof ApiError) throw error; throw new ApiError(400, 'JSON格式错误'); }
  }
  function validateEvent(e) {
    requireValue(e && typeof e === 'object' && !Array.isArray(e) && typeof e.id === 'string' && e.id.length > 0 && e.id.length <= 512, 400, '日程ID无效');
    requireValue(typeof e.title === 'string' && e.title.trim().length > 0 && e.title.length <= (e.nodeId ? 241 : 120) &&
      (e.notes == null || typeof e.notes === 'string' && e.notes.length <= (e.nodeId ? 8001 : 4000)) &&
      Number.isFinite(Date.parse(e.start)) && Number.isFinite(Date.parse(e.end)) &&
      Number.isFinite(Date.parse(e.updatedAt)) && Number.isSafeInteger(e.revision) && e.revision >= 0, 400, '日程格式无效');
    const json = JSON.stringify(e);
    requireValue(Buffer.byteLength(json) <= 1536 * 1024, 400, '单项日程过大');
    return json;
  }
  const server = createServer(async (request, response) => {
    const origin = request.headers.origin;
    const send = (status, value) => {
      response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        ...(origin && allowedOrigins.includes(origin) ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}) });
      response.end(JSON.stringify(value));
    };
    try {
      requireValue(!origin || allowedOrigins.includes(origin), 403, '此网页来源未获允许');
      if (request.method === 'OPTIONS') {
        response.writeHead(204, { 'Access-Control-Allow-Origin': origin ?? '',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' });
        response.end(); return;
      }
      const address = request.socket.remoteAddress ?? 'unknown';
      const bucket = rates.get(address) ?? { at: now(), count: 0 };
      if (now() - bucket.at >= 60000) { bucket.at = now(); bucket.count = 0; }
      rates.set(address, bucket);
      if (rates.size > 10000) for (const [key, value] of rates) if (now() - value.at > 60000) rates.delete(key);
      requireValue(++bucket.count <= 600, 429, '请求过于频繁，请稍后重试');
      const path = new URL(request.url, 'http://localhost').pathname;
      if (path === '/health' && request.method === 'GET') { send(200, { ok: true, protocol: 2, service: 'warm-calendar-sync' }); return; }
      if (path === '/v1/devices' && request.method === 'POST') {
        const input = await body(request);
        requireValue(typeof input.name === 'string' && input.name.trim().length > 0 && input.name.length <= 60 && ['desktop', 'android', 'web'].includes(input.platform), 400, '设备名称或类型无效');
        const saved = input.installationId != null || input.installationSecret != null ? registration(input) : null;
        const previous = saved && get('SELECT * FROM devices WHERE id=?', saved.device_id);
        requireValue(!previous || previous.platform === input.platform, 409, '设备类型不匹配');
        requireValue(previous || get('SELECT count(*) AS n FROM devices').n < 500, 409, '服务设备数量已达上限');
        const deviceId = saved?.device_id ?? id(), secret = token(), groupId = previous?.group_id ?? id();
        transaction(() => {
          if (!previous) run('INSERT INTO groups(id) VALUES (?)', groupId);
          run('INSERT OR REPLACE INTO devices VALUES (?,?,?,?,?,?,?)', deviceId, digest(secret), input.name.trim(), input.platform, groupId, input.platform === 'android' ? 0 : 1, now());
          if (!saved && input.installationId != null) run('INSERT INTO registrations VALUES (?,?,?)', input.installationId, digest(input.installationSecret), deviceId);
        });
        send(201, { deviceId, credential: `${deviceId}.${secret}`, ...state(get('SELECT * FROM devices WHERE id=?', deviceId)) }); return;
      }
      const device = authenticate(request);
      if (path === '/v1/state' && request.method === 'GET') { send(200, state(device)); return; }
      if (path === '/v1/device-name' && request.method === 'POST') {
        const input = await body(request);
        requireValue(typeof input.name === 'string' && input.name.trim().length > 0 && input.name.trim().length <= 60, 400, '设备名需为1—60个字符');
        run('UPDATE devices SET name=? WHERE id=?', input.name.trim(), device.id);
        send(200, state(get('SELECT * FROM devices WHERE id=?', device.id))); return;
      }
      if (path === '/v1/registration' && request.method === 'POST') {
        const input = await body(request), saved = registration(input);
        requireValue(!saved || saved.device_id === device.id, 409, '安装标识已绑定其他设备');
        const bound = get('SELECT * FROM registrations WHERE device_id=?', device.id);
        requireValue(!bound || bound.id === input.installationId, 409, '设备已有其他安装标识');
        if (!saved) run('INSERT INTO registrations VALUES (?,?,?)', input.installationId, digest(input.installationSecret), device.id);
        send(200, { ok: true }); return;
      }
      if (path === '/v1/invites' && request.method === 'POST') {
        requireValue(device.owner, 403, '请在桌面端生成二维码');
        const invite = token(), expires = now() + 120000;
        transaction(() => {
          run('DELETE FROM invites WHERE owner_id=? OR expires<=?', device.id, now());
          run("UPDATE requests SET status='expired' WHERE owner_id=? AND status='pending'", device.id);
          run('INSERT INTO invites(hash,owner_id,expires) VALUES (?,?,?)', digest(invite), device.id, expires);
        });
        send(201, { invite, expiresAt: expires }); return;
      }
      if (path === '/v1/pair-requests' && request.method === 'POST') {
        const input = await body(request);
        requireValue(!device.owner && !state(device).linked, 409, '此设备已连接，请先断开原连接');
        requireValue(typeof input.invite === 'string' && input.invite.length === 43, 400, '二维码无效');
        const invite = get('SELECT * FROM invites WHERE hash=?', digest(input.invite));
        requireValue(invite && invite.expires > now() && !invite.claimed, 410, '二维码已过期或已使用，请刷新后扫码');
        const requestId = id(), code = String(randomInt(100000, 1000000));
        transaction(() => {
          run("UPDATE requests SET status='expired' WHERE mobile_id=? AND status='pending'", device.id);
          run('UPDATE invites SET claimed=1 WHERE hash=?', digest(input.invite));
          run('INSERT INTO requests VALUES (?,?,?,?,?,?)', requestId, invite.owner_id, device.id, invite.expires, code, 'pending');
        });
        send(201, { requestId, code, expiresAt: invite.expires, status: 'pending' }); return;
      }
      if (path === '/v1/pair-requests' && request.method === 'GET') {
        requireValue(device.owner, 403, '此操作需要桌面设备');
        run("UPDATE requests SET status='expired' WHERE expires<=? AND status='pending'", now());
        send(200, { requests: all("SELECT r.*,d.name,d.platform FROM requests r JOIN devices d ON d.id=r.mobile_id WHERE r.owner_id=? AND r.status='pending' ORDER BY r.expires", device.id)
          .map(r => ({ requestId: r.id, name: r.name, platform: r.platform, code: r.code, expiresAt: r.expires })) }); return;
      }
      const requestMatch = /^\/v1\/pair-requests\/([a-f0-9]{32})$/.exec(path);
      if (requestMatch && request.method === 'GET') {
        const pairing = get('SELECT * FROM requests WHERE id=?', requestMatch[1]);
        requireValue(pairing && pairing.mobile_id === device.id, 404, '连接请求不存在');
        if (pairing.status === 'pending' && pairing.expires <= now()) {
          pairing.status = 'expired'; run('UPDATE requests SET status=? WHERE id=?', pairing.status, pairing.id);
        }
        send(200, { status: pairing.status, code: pairing.code, ...state(device) }); return;
      }
      if (requestMatch && request.method === 'POST') {
        const input = await body(request);
        const pairing = get('SELECT * FROM requests WHERE id=?', requestMatch[1]);
        requireValue(pairing && pairing.owner_id === device.id && device.owner, 404, '连接请求不存在');
        requireValue(pairing.status === 'pending' && pairing.expires > now(), 410, '连接请求已失效');
        requireValue(typeof input.approve === 'boolean', 400, '请选择允许或拒绝');
        transaction(() => {
          const phone = get('SELECT * FROM devices WHERE id=?', pairing.mobile_id);
          requireValue(!state(phone).linked, 409, '手机已连接其他桌面');
          if (input.approve) run('UPDATE devices SET group_id=? WHERE id=?', device.group_id, phone.id);
          run('UPDATE requests SET status=? WHERE id=?', input.approve ? 'approved' : 'rejected', pairing.id);
        });
        send(200, state(device)); return;
      }
      if (path === '/v1/unlink' && request.method === 'POST') {
        const input = await body(request);
        const target = get('SELECT * FROM devices WHERE id=?', input.deviceId ?? device.id);
        requireValue(target && !target.owner && (target.id === device.id || device.owner && target.group_id === device.group_id), 403, '不能断开此设备');
        transaction(() => {
          const groupId = id(); run('INSERT INTO groups(id) VALUES (?)', groupId);
          run('UPDATE devices SET group_id=? WHERE id=?', groupId, target.id);
          run("UPDATE requests SET status='expired' WHERE mobile_id=? AND status='pending'", target.id);
        });
        send(200, state(get('SELECT * FROM devices WHERE id=?', device.id))); return;
      }
      if (path === '/v1/revoke' && request.method === 'POST') {
        requireValue(!state(device).linked, 409, '请先断开已连接设备');
        transaction(() => {
          run('DELETE FROM invites WHERE owner_id=?', device.id);
          run('DELETE FROM requests WHERE owner_id=? OR mobile_id=?', device.id, device.id);
          run('DELETE FROM devices WHERE id=?', device.id);
          run('DELETE FROM events WHERE group_id=?', device.group_id);
          run('DELETE FROM group_settings WHERE group_id=?', device.group_id);
          run('DELETE FROM groups WHERE id=?', device.group_id);
        });
        send(200, { ok: true }); return;
      }
      if (path === '/v1/sync' && request.method === 'POST') {
        const input = await body(request);
        requireValue(device.owner || state(device).linked, 403, '请先扫码并在桌面端确认连接');
        requireValue(Array.isArray(input.events) && input.events.length <= 100 && Number.isSafeInteger(input.cursor) && input.cursor >= 0, 400, '同步请求无效');
        const values = input.events.map(e => [e, validateEvent(e)]);
        requireValue(input.settings == null || typeof input.settings.autoCompleteExpired === 'boolean', 400, '共享设置无效');
        const output = transaction(() => {
          if (input.settings != null) run('INSERT OR REPLACE INTO group_settings VALUES (?,?)', device.group_id, input.settings.autoCompleteExpired ? 1 : 0);
          for (const [e, json] of values) {
            const old = get('SELECT payload FROM events WHERE group_id=? AND id=?', device.group_id, e.id);
            if (old?.payload === json) continue;
            requireValue(old || get('SELECT count(*) AS n FROM events WHERE group_id=?', device.group_id).n < 20000, 409, '日程数量已达服务上限');
            run('UPDATE groups SET sequence=sequence+1 WHERE id=?', device.group_id);
            const seq = get('SELECT sequence FROM groups WHERE id=?', device.group_id).sequence;
            run('INSERT OR REPLACE INTO events VALUES (?,?,?,?)', device.group_id, e.id, json, seq);
          }
          const current = get('SELECT sequence FROM groups WHERE id=?', device.group_id).sequence;
          const cursor = input.groupId === device.group_id ? Math.min(input.cursor, current) : 0;
          const rows = all('SELECT payload,sequence FROM events WHERE group_id=? AND sequence>? ORDER BY sequence LIMIT 101', device.group_id, cursor);
          const page = []; let pageBytes = 0;
          for (const row of rows) {
            const bytes = Buffer.byteLength(row.payload);
            if (page.length === 100 || page.length > 0 && pageBytes + bytes > 1800 * 1024) break;
            page.push(row); pageBytes += bytes;
          }
          const preferences = get('SELECT auto_complete FROM group_settings WHERE group_id=?', device.group_id);
          return { settings: preferences ? { autoCompleteExpired: !!preferences.auto_complete } : null,
            groupId: device.group_id, cursor: page.length ? page.at(-1).sequence : current,
            hasMore: rows.length > page.length, events: page.map(r => JSON.parse(r.payload)), ...state(device) };
        });
        send(200, output); return;
      }
      throw new ApiError(404, '接口不存在');
    } catch (error) {
      if (!(error instanceof ApiError)) console.error('Sync request failed:', error.message);
      send(error instanceof ApiError ? error.status : 500, { error: error instanceof ApiError ? error.message : '服务暂不可用' });
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return { server, db, close: () => new Promise(resolveClose => server.close(() => { db.close(); resolveClose(); })) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const app = createSyncServer({ database: process.env.SYNC_DATABASE ?? './data/calendar.sqlite',
    allowedOrigins: (process.env.SYNC_ALLOWED_ORIGINS ?? 'http://127.0.0.1:4173,http://127.0.0.1:4174').split(',').filter(Boolean) });
  const host = process.env.SYNC_HOST ?? '127.0.0.1', port = Number(process.env.SYNC_PORT ?? 4280);
  app.server.listen(port, host, () => console.log(`日程同步服务 http://${host}:${port}`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { app.close().then(() => process.exit(0)); });
}
