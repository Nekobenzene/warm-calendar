import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../domain/models.dart';

Future<void> ensureSharedSettings(CalendarDatabase db) => db.customStatement(
  'CREATE TABLE IF NOT EXISTS shared_settings(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL,dirty INTEGER NOT NULL DEFAULT 0)',
);

abstract interface class ScheduleRepository {
  Future<List<ScheduleEvent>> loadEvents();
  Future<AppSettings> loadSettings();
  Future<void> saveEvent(ScheduleEvent event);
  Future<void> saveEvents(List<ScheduleEvent> events);
  Future<void> saveSettings(AppSettings settings);
  Future<void> mergeBackup(BackupData backup);
  Future<void> close();
}

class CalendarDatabase extends GeneratedDatabase {
  CalendarDatabase([QueryExecutor? executor, String name = 'warm_calendar'])
    : super(
        executor ??
            driftDatabase(
              name: name,
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE events (id TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
      );
      await customStatement(
        'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK (id=1), payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE outbox (event_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, queued_at TEXT NOT NULL)',
      );
    },
  );
}

class SqliteScheduleRepository implements ScheduleRepository {
  final CalendarDatabase db;
  SqliteScheduleRepository([CalendarDatabase? database])
    : db = database ?? CalendarDatabase();
  @override
  Future<List<ScheduleEvent>> loadEvents() async =>
      (await db.customSelect('SELECT payload FROM events').get())
          .map(
            (r) => ScheduleEvent.fromJson(
              jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
            ),
          )
          .toList();
  @override
  Future<AppSettings> loadSettings() async {
    final rows = await db
        .customSelect('SELECT payload FROM settings WHERE id=1')
        .get();
    return rows.isEmpty
        ? const AppSettings()
        : AppSettings.fromJson(
            jsonDecode(rows.first.read<String>('payload'))
                as Map<String, dynamic>,
          );
  }

  Future<void> _writeEvent(ScheduleEvent e) async {
    await db.customStatement(
      'INSERT OR REPLACE INTO events (id,payload,updated_at,deleted) VALUES (?,?,?,?)',
      [
        e.id,
        jsonEncode(e.toJson()),
        e.updatedAt.toIso8601String(),
        e.deleted ? 1 : 0,
      ],
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO outbox (event_id,revision,queued_at) VALUES (?,?,?)',
      [e.id, e.revision, DateTime.now().toUtc().toIso8601String()],
    );
  }

  @override
  Future<void> saveEvent(ScheduleEvent event) =>
      db.transaction(() => _writeEvent(event));
  @override
  Future<void> saveEvents(List<ScheduleEvent> events) =>
      db.transaction(() async {
        for (final event in events) {
          await _writeEvent(event);
        }
      });
  @override
  Future<void> saveSettings(AppSettings settings) => db.transaction(() async {
    await ensureSharedSettings(db);
    final old = await loadSettings();
    await db.customStatement(
      'INSERT OR REPLACE INTO settings (id,payload) VALUES (1,?)',
      [jsonEncode(settings.toJson())],
    );
    if (old.autoCompleteExpired != settings.autoCompleteExpired ||
        old.autoCompleteTodos != settings.autoCompleteTodos) {
      await db.customStatement(
        'INSERT OR REPLACE INTO shared_settings(id,payload,dirty) VALUES (1,?,1)',
        [
          jsonEncode({
            'autoCompleteExpired': settings.autoCompleteExpired,
            'autoCompleteTodos': settings.autoCompleteTodos,
            'changeId':
                '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x3fffffff)}',
          }),
        ],
      );
    }
  });
  @override
  Future<void> mergeBackup(BackupData backup) => db.transaction(() async {
    final existing = {for (final e in await loadEvents()) e.id: e};
    for (final e in backup.events) {
      final old = existing[e.id];
      if (old == null || e.updatedAt.isAfter(old.updatedAt)) {
        await _writeEvent(e);
      }
    }
    await saveSettings(backup.settings);
  });
  @override
  Future<void> close() => db.close();
}
