import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import '../data/repository.dart';
import '../domain/models.dart';
import 'link_models.dart';

abstract class SyncStore {
  Future<Map<String, dynamic>?> pendingPreferences() async => null;
  Future<bool> applyPreferences(
    Map<String, dynamic>? remote,
    Map<String, dynamic>? sent,
  ) async => false;
  Future<void> initialize();
  Future<({String? groupId, int cursor})> position();
  Future<List<PendingChange>> pending();
  Future<void> seed();
  Future<bool> apply(
    List<ScheduleEvent> remote,
    List<PendingChange> sent,
    String groupId,
    int cursor,
  );
}

class SqliteSyncStore implements SyncStore {
  final CalendarDatabase db;
  SqliteSyncStore(this.db);
  @override
  Future<void> initialize() async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS link_state (id INTEGER PRIMARY KEY CHECK(id=1), group_id TEXT, cursor INTEGER NOT NULL DEFAULT 0)',
    );
    await ensureSharedSettings(db);
    final rows = await db
        .customSelect('SELECT payload FROM shared_settings WHERE id=1')
        .get();
    if (rows.isEmpty) {
      final settings = await SqliteScheduleRepository(db).loadSettings();
      if (settings.autoCompleteExpired) {
        await db.customStatement(
          'INSERT INTO shared_settings(id,payload,dirty) VALUES (1,?,1)',
          [
            jsonEncode({'autoCompleteExpired': true, 'changeId': 'migration'}),
          ],
        );
      }
    }
  }

  @override
  Future<Map<String, dynamic>?> pendingPreferences() async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM shared_settings WHERE id=1 AND dirty=1',
        )
        .get();
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first.read<String>('payload'))
              as Map<String, dynamic>;
  }

  @override
  Future<bool> applyPreferences(
    Map<String, dynamic>? remote,
    Map<String, dynamic>? sent,
  ) => db.transaction(() async {
    if (sent != null) {
      await db.customStatement(
        'UPDATE shared_settings SET dirty=0 WHERE id=1 AND payload=?',
        [jsonEncode(sent)],
      );
    }
    if (remote == null || remote['autoCompleteExpired'] is! bool) return false;
    final dirty = await pendingPreferences();
    if (dirty != null) return false;
    final settings = await SqliteScheduleRepository(db).loadSettings();
    final value = remote['autoCompleteExpired'] as bool;
    if (settings.autoCompleteExpired != value) {
      await db.customStatement(
        'INSERT OR REPLACE INTO settings(id,payload) VALUES (1,?)',
        [jsonEncode(settings.copyWith(autoCompleteExpired: value).toJson())],
      );
    }
    await db.customStatement(
      'INSERT OR REPLACE INTO shared_settings(id,payload,dirty) VALUES (1,?,0)',
      [
        jsonEncode({'autoCompleteExpired': value}),
      ],
    );
    return settings.autoCompleteExpired != value;
  });
  @override
  Future<({String? groupId, int cursor})> position() async {
    final rows = await db
        .customSelect('SELECT group_id,cursor FROM link_state WHERE id=1')
        .get();
    return rows.isEmpty
        ? (groupId: null, cursor: 0)
        : (
            groupId: rows.first.readNullable<String>('group_id'),
            cursor: rows.first.read<int>('cursor'),
          );
  }

  @override
  Future<List<PendingChange>> pending() async =>
      (await db
              .customSelect(
                'SELECT e.payload FROM outbox o JOIN events e ON e.id=o.event_id ORDER BY o.queued_at,o.event_id LIMIT 100',
              )
              .get())
          .map((r) {
            final payload = r.read<String>('payload');
            return PendingChange(
              ScheduleEvent.fromJson(
                jsonDecode(payload) as Map<String, dynamic>,
              ),
              payload,
            );
          })
          .toList();
  @override
  Future<void> seed() => db.transaction(() async {
    for (final row
        in await db.customSelect('SELECT id,payload FROM events').get()) {
      final event = ScheduleEvent.fromJson(
        jsonDecode(row.read<String>('payload')) as Map<String, dynamic>,
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO outbox(event_id,revision,queued_at) VALUES (?,?,?)',
        [event.id, event.revision, DateTime.now().toUtc().toIso8601String()],
      );
    }
    await db.customStatement(
      'INSERT OR REPLACE INTO link_state(id,group_id,cursor) VALUES (1,NULL,0)',
    );
  });
  @override
  Future<bool> apply(
    List<ScheduleEvent> remote,
    List<PendingChange> sent,
    String groupId,
    int cursor,
  ) => db.transaction(() async {
    for (final item in sent) {
      // Only acknowledge the exact snapshot uploaded; edits made in flight remain queued.
      await db.customStatement(
        'DELETE FROM outbox WHERE event_id=? AND EXISTS (SELECT 1 FROM events WHERE id=? AND payload=?)',
        [item.event.id, item.event.id, item.payload],
      );
    }
    var changed = false;
    for (final event in remote) {
      final local = await db
          .customSelect(
            'SELECT e.payload,o.event_id FROM events e LEFT JOIN outbox o ON e.id=o.event_id WHERE e.id=?',
            variables: [Variable.withString(event.id)],
          )
          .get();
      if (local.isNotEmpty &&
          local.first.readNullable<String>('event_id') != null) {
        continue;
      }
      final payload = jsonEncode(event.toJson());
      if (local.isNotEmpty && local.first.read<String>('payload') == payload) {
        continue;
      }
      await db.customStatement(
        'INSERT OR REPLACE INTO events(id,payload,updated_at,deleted) VALUES (?,?,?,?)',
        [
          event.id,
          payload,
          event.updatedAt.toIso8601String(),
          event.deleted ? 1 : 0,
        ],
      );
      changed = true;
    }
    final old = await position();
    final next = old.groupId == groupId && old.cursor > cursor
        ? old.cursor
        : cursor;
    await db.customStatement(
      'INSERT OR REPLACE INTO link_state(id,group_id,cursor) VALUES (1,?,?)',
      [groupId, next],
    );
    return changed;
  });
}
