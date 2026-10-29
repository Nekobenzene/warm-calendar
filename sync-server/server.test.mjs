import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readdirSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSyncServer } from './server.mjs';

const event = (id = 'event', extra = {}) => ({ id, title: '同步测试', notes: '',
  start: '2026-10-29T09:00:00.000Z', end: '2026-10-29T10:00:00.000Z',
  updatedAt: '2026-10-29T08:00:00.000Z', revision: 1,
  reminderOffsets: [10, 0], reminderSound: true, color: 0x80e4ead9,
  completedColor: 0xffe2e3df, ...extra });

test('稳定安装凭据复用设备，保留配对；改名、解绑和撤销各自生效', async t => {
  const { call, register, pair, app } = await fixture(t);
  const desktop = await register();
  const proof = { installationId: 'a'.repeat(32), installationSecret: 'b'.repeat(43) };
  const input = { name: '手机A', platform: 'android', ...proof };
  const phone = await call('/v1/devices', null, input, 201);
  await pair(desktop, phone);
  const restored = await call('/v1/devices', null, input, 201);
  assert.equal(restored.deviceId, phone.deviceId);
  assert.equal(restored.linked, true);
  assert.equal(restored.devices.length, 2);
  await call('/v1/state', phone.credential, undefined, 401);
  await call('/v1/devices', null, { ...input, installationSecret: 'c'.repeat(43) }, 403);
  await call('/v1/device-name', restored.credential, { name: '我的 Pixel' });
  assert.equal((await call('/v1/state', desktop.credential)).devices.find(d => d.id === phone.deviceId).name, '我的 Pixel');
  await call('/v1/device-name', restored.credential, { name: '   ' }, 400);
  const other = await call('/v1/devices', null, { name: '手机A', platform: 'android' }, 201);
  assert.notEqual(other.deviceId, phone.deviceId);
  await call('/v1/unlink', desktop.credential, { deviceId: phone.deviceId });
  const unlinked = await call('/v1/devices', null, input, 201);
  assert.equal(unlinked.linked, false);
  await call('/v1/sync', unlinked.credential, { events: [], cursor: 0 }, 403);
  await call('/v1/revoke', unlinked.credential, {});
  const recreated = await call('/v1/devices', null, input, 201);
  assert.equal(recreated.deviceId, phone.deviceId);
  assert.equal(recreated.linked, false);
  assert.equal(app.db.prepare('SELECT count(*) AS n FROM devices WHERE id=?').get(phone.deviceId).n, 1);
});

test('现有设备升级绑定安装凭据，不产生新设备或绕过身份验证', async t => {
  const { call, register } = await fixture(t);
  const desktop = await register();
  const proof = { installationId: 'd'.repeat(32), installationSecret: 'e'.repeat(43) };
  await call('/v1/registration', desktop.credential, proof);
  await call('/v1/registration', desktop.credential, proof);
  const restored = await call('/v1/devices', null, { ...proof, name: '工作电脑', platform: 'desktop' }, 201);
  assert.equal(restored.deviceId, desktop.deviceId);
  assert.equal(restored.groupId, desktop.groupId);
  await call('/v1/registration', restored.credential, { ...proof, installationSecret: 'f'.repeat(43) }, 403);
});

test('逾期自动完成双向同步开关，设置独立于日程分页游标，其他设置不外传', async t => {
  const { call, register, pair } = await fixture(t);
  const desktop = await register(), phone = await register('android');
  await pair(desktop, phone);
  await call('/v1/sync', desktop.credential, { events: [], cursor: 0, settings: { autoCompleteExpired: true, notificationSound: false } });
  let received = await call('/v1/sync', phone.credential, { events: [], cursor: 0 });
  assert.deepEqual(received.settings, { autoCompleteExpired: true });
  await call('/v1/sync', phone.credential, { events: [], cursor: received.cursor, groupId: received.groupId, settings: { autoCompleteExpired: false } });
  received = await call('/v1/sync', desktop.credential, { events: [], cursor: received.cursor, groupId: received.groupId });
  assert.deepEqual(received.settings, { autoCompleteExpired: false });
  await call('/v1/sync', desktop.credential, { events: [], cursor: 0, settings: { autoCompleteExpired: 'false' } }, 400);
});
async function fixture(t, options = {}) {
  const app = createSyncServer(options);
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  t.after(() => app.close());
  const base = `http://127.0.0.1:${app.server.address().port}`;
  async function call(path, credential, body, expected = 200) {
    const response = await fetch(base + path, { method: body ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json', ...(credential ? { Authorization: `Bearer ${credential}` } : {}) },
      body: body ? JSON.stringify(body) : undefined });
    const result = await response.json();
    assert.equal(response.status, expected, JSON.stringify(result)); return result;
  }
  const register = (platform = 'desktop') => call('/v1/devices', null, { name: platform, platform }, 201);
  async function pair(desktop, phone) {
    const invite = await call('/v1/invites', desktop.credential, {}, 201);
    const request = await call('/v1/pair-requests', phone.credential, { invite: invite.invite }, 201);
    const pending = await call('/v1/pair-requests', desktop.credential);
    assert.equal(pending.requests[0].code, request.code);
    await call(`/v1/pair-requests/${request.requestId}`, desktop.credential, { approve: true });
    return request;
  }
  return { call, register, pair, app };
}

test('确认前禁止手机同步；确认后双向传递完整日程及删除标记', async t => {
  const { call, register, pair } = await fixture(t);
  const desktop = await register(), phone = await register('android');
  await call('/v1/sync', phone.credential, { cursor: 0, events: [] }, 403);
  const original = event('repeat', { recurrence: { frequency: 'daily', minutes: [540, 600], until: '2026-11-01' } });
  await call('/v1/sync', desktop.credential, { cursor: 0, events: [original] });
  await pair(desktop, phone);
  const first = await call('/v1/sync', phone.credential, { cursor: 0, events: [] });
  assert.deepEqual(first.events, [original]);
  const completed = { ...original, completed: true, revision: 2 };
  await call('/v1/sync', phone.credential, { cursor: first.cursor, groupId: first.groupId, events: [completed] });
  const updated = await call('/v1/sync', desktop.credential, { cursor: first.cursor, groupId: first.groupId, events: [] });
  assert.equal(updated.events[0].completed, true);
  await call('/v1/sync', desktop.credential, { cursor: updated.cursor, groupId: updated.groupId, events: [{ ...completed, deleted: true, revision: 3 }] });
  const deleted = await call('/v1/sync', phone.credential, { cursor: updated.cursor, groupId: updated.groupId, events: [] });
  assert.equal(deleted.events[0].deleted, true);
});

test('二维码轮换、拒绝、过期与重复扫码都不会授权', async t => {
  let clock = Date.now();
  const { call, register } = await fixture(t, { now: () => clock });
  const desktop = await register(), phone = await register('android');
  const old = await call('/v1/invites', desktop.credential, {}, 201);
  const fresh = await call('/v1/invites', desktop.credential, {}, 201);
  await call('/v1/pair-requests', phone.credential, { invite: old.invite }, 410);
  const req = await call('/v1/pair-requests', phone.credential, { invite: fresh.invite }, 201);
  await call('/v1/pair-requests', phone.credential, { invite: fresh.invite }, 410);
  await call(`/v1/pair-requests/${req.requestId}`, desktop.credential, { approve: false });
  assert.equal((await call(`/v1/pair-requests/${req.requestId}`, phone.credential)).status, 'rejected');
  const expiry = await call('/v1/invites', desktop.credential, {}, 201);
  clock += 120001;
  await call('/v1/pair-requests', phone.credential, { invite: expiry.invite }, 410);
});

test('凭据、日程分组和桌面确认权限互相隔离', async t => {
  const { call, register } = await fixture(t);
  const desktop = await register(), outsider = await register(), phone = await register('android');
  await call('/v1/state', desktop.deviceId + '.' + 'x'.repeat(43), undefined, 401);
  await call('/v1/sync', desktop.credential, { cursor: 0, events: [event()] });
  assert.equal((await call('/v1/sync', outsider.credential, { cursor: 0, groupId: desktop.groupId, events: [] })).events.length, 0);
  const invite = await call('/v1/invites', desktop.credential, {}, 201);
  const req = await call('/v1/pair-requests', phone.credential, { invite: invite.invite }, 201);
  await call(`/v1/pair-requests/${req.requestId}`, outsider.credential, { approve: true }, 404);
  await call('/v1/sync', phone.credential, { cursor: 0, events: [] }, 403);
});

test('断开后手机立即失去旧分组访问，重配对从新游标开始', async t => {
  const { call, register, pair } = await fixture(t);
  const desktop = await register(), phone = await register('android');
  await pair(desktop, phone);
  const initial = await call('/v1/sync', desktop.credential, { cursor: 0, events: [event()] });
  await call('/v1/unlink', desktop.credential, { deviceId: phone.deviceId });
  await call('/v1/sync', phone.credential, { cursor: initial.cursor, groupId: initial.groupId, events: [] }, 403);
  await pair(desktop, phone);
  const next = await call('/v1/sync', phone.credential, { cursor: 900, groupId: 'old-group', events: [] });
  assert.equal(next.events.length, 1);
});

test('相同上传可重试且分页不会遗漏超过100项的数据', async t => {
  const { call, register } = await fixture(t);
  const desktop = await register();
  const page = Array.from({ length: 100 }, (_, i) => event('a' + i));
  let result = await call('/v1/sync', desktop.credential, { cursor: 0, events: page });
  const cursor = result.cursor;
  result = await call('/v1/sync', desktop.credential, { cursor, groupId: result.groupId, events: page });
  assert.equal(result.events.length, 0); assert.equal(result.cursor, cursor);
  await call('/v1/sync', desktop.credential, { cursor, groupId: result.groupId, events: [event('last')] });
  result = await call('/v1/sync', desktop.credential, { cursor: 0, events: [] });
  assert.equal(result.events.length, 100); assert.equal(result.hasMore, true);
  const second = await call('/v1/sync', desktop.credential, { cursor: result.cursor, groupId: result.groupId, events: [] });
  assert.equal(second.events.length, 1); assert.equal(second.hasMore, false);
  await call('/v1/sync', desktop.credential, { cursor: 0, events: [event('bad', { title: '' })] }, 400);
});

test('服务重启后设备和日程持久保留；撤销凭据后不可访问', async t => {
  const folder = mkdtempSync(join(tmpdir(), 'warm-calendar-sync-test-'));
  const database = join(folder, 'calendar.sqlite');
  const app = createSyncServer({ database });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  let base = `http://127.0.0.1:${app.server.address().port}`;
  const created = await (await fetch(base + '/v1/devices', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'persistent', platform: 'desktop' }) })).json();
  const headers = { Authorization: `Bearer ${created.credential}`, 'Content-Type': 'application/json' };
  await fetch(base + '/v1/sync', { method: 'POST', headers, body: JSON.stringify({ cursor: 0, events: [event()] }) });
  await app.close();
  const reopened = createSyncServer({ database });
  await new Promise(resolve => reopened.server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${reopened.server.address().port}`;
  const reply = await (await fetch(base + '/v1/sync', { method: 'POST', headers, body: JSON.stringify({ cursor: 0, events: [] }) })).json();
  assert.equal(reply.events[0].id, 'event');
  assert.equal((await fetch(base + '/v1/revoke', { method: 'POST', headers, body: '{}' })).status, 200);
  assert.equal((await fetch(base + '/v1/state', { headers })).status, 401);
  await reopened.close();
  for (const name of readdirSync(folder)) rmSync(join(folder, name));
  rmdirSync(folder);
});
