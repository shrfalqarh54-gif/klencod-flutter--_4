import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const String legacyTasksKey = 'injaz_tasks_v1';
const String legacySettingsKey = 'injaz_settings_v1';
const String legacyListsKey = 'injaz_lists_v1';
const String legacyDefaultListId = 'injaz_default_list';
const String legacyMigrationKey = 'injaz_sqlite_migration_v1';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int version = 2;

  static Future<AppDatabase> open() async {
    final databasesPath = await getDatabasesPath();
    final databasePath = path.join(databasesPath, 'injaz.db');

    final database = await openDatabase(
      databasePath,
      version: version,
      onCreate: (db, _) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 already contains repeat_days/series_id; this bump preserves
          // existing rows while allowing future schema evolution.
          await db.execute('ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
          await db.execute('CREATE INDEX IF NOT EXISTS tasks_notification_id_index ON tasks(notification_id)');
        }
      },
    );

    final appDatabase = AppDatabase._(database);
    await appDatabase._migrateLegacyDataIfNeeded();
    return appDatabase;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE task_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        collapsed INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        day_key TEXT NOT NULL,
        text TEXT NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        status TEXT NOT NULL,
        repeat_daily INTEGER NOT NULL DEFAULT 0,
        repeat_days TEXT NOT NULL DEFAULT '',
        series_id TEXT,
        list_id TEXT NOT NULL,
        notification_id INTEGER,
        snoozed_until TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (list_id) REFERENCES task_lists(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX tasks_day_key_index ON tasks(day_key)
    ''');

    await db.execute('''
      CREATE INDEX tasks_list_id_index ON tasks(list_id)
    ''');
  }

  Future<void> _migrateLegacyDataIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(legacyMigrationKey) == true) {
      return;
    }

    final legacyTasks = prefs.getStringList(legacyTasksKey) ?? <String>[];
    final legacyLists = prefs.getStringList(legacyListsKey) ?? <String>[];
    final legacySettings = prefs.getString(legacySettingsKey);

    await db.transaction((transaction) async {
      final existingLists = await transaction.query('task_lists', limit: 1);
      final existingTasks = await transaction.query('tasks', limit: 1);

      if (existingLists.isEmpty && existingTasks.isEmpty) {
        for (var index = 0; index < legacyLists.length; index++) {
          final raw = jsonDecode(legacyLists[index]);
          if (raw is! Map<String, dynamic>) continue;

          final id = raw['id']?.toString();
          if (id == null || id.isEmpty) continue;

          await transaction.insert(
            'task_lists',
            <String, Object?>{
              'id': id,
              'name': raw['name']?.toString() ?? 'قائمة جديدة',
              'collapsed': raw['collapsed'] == true ? 1 : 0,
              'sort_order': index,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        final hasLists = await transaction.query('task_lists', limit: 1);
        if (hasLists.isEmpty) {
          await transaction.insert('task_lists', <String, Object?>{
            'id': legacyDefaultListId,
            'name': 'قائمتي',
            'collapsed': 0,
            'sort_order': 0,
          });
        }

        for (final item in legacyTasks) {
          final raw = jsonDecode(item);
          if (raw is! Map<String, dynamic>) continue;

          final id = raw['id']?.toString();
          final dayKey = raw['dayKey']?.toString();
          if (id == null || id.isEmpty || dayKey == null || dayKey.isEmpty) {
            continue;
          }

          final listId = raw['listId']?.toString() ?? legacyDefaultListId;
          final listExists = await transaction.query(
            'task_lists',
            where: 'id = ?',
            whereArgs: <Object?>[listId],
            limit: 1,
          );

          if (listExists.isEmpty) {
            await transaction.insert('task_lists', <String, Object?>{
              'id': listId,
              'name': 'قائمتي',
              'collapsed': 0,
              'sort_order': 0,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }

          await transaction.insert(
            'tasks',
            <String, Object?>{
              'id': id,
              'day_key': dayKey,
              'text': raw['text']?.toString() ?? '',
              'hour': raw['hour'] is num ? (raw['hour'] as num).toInt() : 9,
              'minute': raw['minute'] is num ? (raw['minute'] as num).toInt() : 0,
              'color_value': raw['colorValue'] is num
                  ? (raw['colorValue'] as num).toInt()
                  : 0xFF6750A4,
              'status': raw['status']?.toString() ?? 'pending',
              'repeat_daily': raw['repeatDaily'] == true ? 1 : 0,
              'repeat_days': '',
              'series_id': null,
              'list_id': listId,
              'notification_id': null,
              'snoozed_until': null,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      if (legacySettings != null) {
        final decoded = jsonDecode(legacySettings);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            await transaction.insert(
              'app_settings',
              <String, Object?>{
                'key': entry.key,
                'value': jsonEncode(entry.value),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });

    final checkLists = await db.query('task_lists', limit: 1);
    final checkSettings = await db.query('app_settings', limit: 1);
    final checkTasks = await db.query('tasks', limit: 1);

    final migrationSucceeded = legacyLists.isEmpty &&
            legacyTasks.isEmpty &&
            legacySettings == null ||
        checkLists.isNotEmpty || checkTasks.isNotEmpty || checkSettings.isNotEmpty;

    if (migrationSucceeded) {
      await prefs.setBool(legacyMigrationKey, true);
    }
  }

  Future<List<Map<String, Object?>>> getLists() {
    return db.query(
      'task_lists',
      orderBy: 'sort_order ASC, rowid ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasks() {
    return db.query(
      'tasks',
      orderBy: 'day_key ASC, hour ASC, minute ASC, rowid ASC',
    );
  }

  Future<Map<String, String>> getSettings() async {
    final rows = await db.query('app_settings');
    return <String, String>{
      for (final row in rows)
        row['key']! as String: row['value']! as String,
    };
  }

  Future<void> replaceLists(
    List<Map<String, Object?>> rows,
  ) async {
    await db.transaction((transaction) async {
      for (var index = 0; index < rows.length; index++) {
        final row = Map<String, Object?>.from(rows[index]);
        row['sort_order'] = index;
        final id = row['id'];
        final updated = await transaction.update(
          'task_lists',
          row..remove('id'),
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (updated == 0) {
          row['id'] = id;
          await transaction.insert('task_lists', row);
        }
      }
      final ids = rows.map((row) => row['id']).whereType<String>().toList();
      if (ids.isEmpty) {
        await transaction.delete('task_lists');
      } else {
        await transaction.delete(
          'task_lists',
          where: 'id NOT IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
      }
    });
  }

  Future<void> replaceTasks(
    List<Map<String, Object?>> rows,
  ) async {
    await db.transaction((transaction) async {
      await transaction.delete('tasks');
      for (final row in rows) {
        await transaction.insert('tasks', row);
      }
    });
  }

  Future<void> saveSettings(
    Map<String, String> values,
  ) async {
    await db.transaction((transaction) async {
      for (final entry in values.entries) {
        await transaction.insert(
          'app_settings',
          <String, Object?>{
            'key': entry.key,
            'value': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteListAndTasks(String listId) async {
    await db.transaction((transaction) async {
      await transaction.delete(
        'tasks',
        where: 'list_id = ?',
        whereArgs: <Object?>[listId],
      );
      await transaction.delete(
        'task_lists',
        where: 'id = ?',
        whereArgs: <Object?>[listId],
      );
    });
  }

  Future<void> close() => db.close();
}
