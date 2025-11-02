import 'dart:convert'; // Added for json.encode
import 'package:flutter/material.dart'; // For TimeOfDay
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'baby_tracker.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime TEXT NOT NULL,
            endTime TEXT,
            lastModified TEXT NOT NULL,
            modifiedBy TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE feeding_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime TEXT NOT NULL,
            endTime TEXT,
            source TEXT NOT NULL,
            lastModified TEXT NOT NULL,
            modifiedBy TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_deltas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            table_name TEXT NOT NULL,
            entry_json TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            modified_by TEXT NOT NULL,
            synced BOOLEAN NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE sleep_entries ADD COLUMN lastModified TEXT NOT NULL DEFAULT (datetime("now"))');
          await db.execute('ALTER TABLE sleep_entries ADD COLUMN modifiedBy TEXT NOT NULL DEFAULT "local"');
          await db.execute('ALTER TABLE feeding_entries ADD COLUMN lastModified TEXT NOT NULL DEFAULT (datetime("now"))');
          await db.execute('ALTER TABLE feeding_entries ADD COLUMN modifiedBy TEXT NOT NULL DEFAULT "local"');
          await db.execute('''
            CREATE TABLE pending_deltas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              table_name TEXT NOT NULL,
              entry_json TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              modified_by TEXT NOT NULL,
              synced BOOLEAN NOT NULL DEFAULT 0
            )
          ''');
          await db.rawUpdate('UPDATE sleep_entries SET lastModified = datetime("now"), modifiedBy = "local"');
          await db.rawUpdate('UPDATE feeding_entries SET lastModified = datetime("now"), modifiedBy = "local"');
        }
      },
    );
  }

  // === Pending Deltas ===
  Future<void> addPendingDelta({
    required String type,
    required String tableName,
    required Map<String, dynamic> entryJson,
    required String timestamp,
    required String modifiedBy,
  }) async {
    final db = await database;
    await db.insert(
      'pending_deltas',
      {
        'type': type,
        'table_name': tableName,
        'entry_json': json.encode(entryJson),
        'timestamp': timestamp,
        'modified_by': modifiedBy,
        'synced': 0,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingDeltas() async {
    final db = await database;
    return await db.query('pending_deltas', where: 'synced = ?', whereArgs: [0]);
  }

  Future<void> markDeltasSynced(List<int> ids) async {
    final db = await database;
    await db.update(
      'pending_deltas',
      {'synced': 1},
      where: 'id IN (${ids.join(',')})',
    );
  }

  Future<int> clearSyncedDeltas() async {
    final db = await database;
    return await db.delete('pending_deltas', where: 'synced = 1');
  }

  // === Sleep CRUD ===
  Future<int> insertSleepEntry(SleepEntry entry) async {
    final db = await database;
    final entryWithDefaults = entry.copyWith(
      lastModified: entry.lastModified,
      modifiedBy: entry.modifiedBy,
    );
    final id = await db.insert(
      'sleep_entries',
      entryWithDefaults.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('Inserted sleep entry with id: $id');
    
    await addPendingDelta(
      type: 'insert',
      tableName: 'sleep_entries',
      entryJson: entryWithDefaults.copyWith(id: id).toJson(),
      timestamp: entryWithDefaults.lastModified.toIso8601String(),
      modifiedBy: entryWithDefaults.modifiedBy,
    );
    
    return id;
  }

  Future<List<SleepEntry>> getSleepEntries() async {
    final db = await database;
    final maps = await db.query('sleep_entries', orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) => SleepEntry.fromMap(maps[i]));
  }

  Future<SleepEntry?> getSleepEntryById(int id) async {
    final db = await database;
    final maps = await db.query('sleep_entries', where: 'id = ?', whereArgs: [id]); // Fixed typo: removed scel_id
    if (maps.isNotEmpty) {
      return SleepEntry.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateSleepEntry(SleepEntry entry) async {
    if (entry.id == null) {
      debugPrint('ERROR: Cannot update SleepEntry with null id');
      return;
    }
    final db = await database;
    final entryWithDefaults = entry.copyWith(
      lastModified: entry.lastModified,
      modifiedBy: entry.modifiedBy,
    );
    final count = await db.update(
      'sleep_entries',
      entryWithDefaults.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    debugPrint('updateSleepEntry: updated $count rows');
    
    await addPendingDelta(
      type: 'update',
      tableName: 'sleep_entries',
      entryJson: entryWithDefaults.toJson(),
      timestamp: entryWithDefaults.lastModified.toIso8601String(),
      modifiedBy: entryWithDefaults.modifiedBy,
    );
  }

  Future<void> deleteSleepEntry(int id) async {
    final db = await database;
    await db.delete('sleep_entries', where: 'id = ?', whereArgs: [id]);
    
    await addPendingDelta(
      type: 'delete',
      tableName: 'sleep_entries',
      entryJson: {'id': id},
      timestamp: DateTime.now().toIso8601String(),
      modifiedBy: 'local',
    );
  }

  // === Feeding CRUD ===
  Future<int> insertFeedingEntry(FeedingEntry entry) async {
    final db = await database;
    final entryWithDefaults = entry.copyWith(
      lastModified: entry.lastModified,
      modifiedBy: entry.modifiedBy,
    );
    final id = await db.insert(
      'feeding_entries',
      entryWithDefaults.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('Inserted feeding entry with id: $id');
    
    await addPendingDelta(
      type: 'insert',
      tableName: 'feeding_entries',
      entryJson: entryWithDefaults.copyWith(id: id).toJson(),
      timestamp: entryWithDefaults.lastModified.toIso8601String(),
      modifiedBy: entryWithDefaults.modifiedBy,
    );
    
    return id;
  }

  Future<List<FeedingEntry>> getFeedingEntries() async {
    final db = await database;
    final maps = await db.query('feeding_entries', orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) => FeedingEntry.fromMap(maps[i]));
  }

  Future<FeedingEntry?> getFeedingEntryById(int id) async {
    final db = await database;
    final maps = await db.query('feeding_entries', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return FeedingEntry.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateFeedingEntry(FeedingEntry entry) async {
    if (entry.id == null) {
      debugPrint('ERROR: Cannot update FeedingEntry with null id');
      return;
    }
    final db = await database;
    final entryWithDefaults = entry.copyWith(
      lastModified: entry.lastModified,
      modifiedBy: entry.modifiedBy,
    );
    final count = await db.update(
      'feeding_entries',
      entryWithDefaults.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    debugPrint('updateFeedingEntry: updated $count rows');
    
    await addPendingDelta(
      type: 'update',
      tableName: 'feeding_entries',
      entryJson: entryWithDefaults.toJson(),
      timestamp: entryWithDefaults.lastModified.toIso8601String(),
      modifiedBy: entryWithDefaults.modifiedBy,
    );
  }

  Future<void> deleteFeedingEntry(int id) async {
    final db = await database;
    await db.delete('feeding_entries', where: 'id = ?', whereArgs: [id]);
    
    await addPendingDelta(
      type: 'delete',
      tableName: 'feeding_entries',
      entryJson: {'id': id},
      timestamp: DateTime.now().toIso8601String(),
      modifiedBy: 'local',
    );
  }

  // === Helpers ===
  Future<SleepEntry?> getOngoingSleep() async {
    final entries = await getSleepEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  Future<FeedingEntry?> getOngoingFeeding() async {
    final entries = await getFeedingEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  // === Combined Queries for Pagination ===
  Future<List<dynamic>> getCombinedEntries({
    DateTime? fromDate,
    DateTime? toDate,
    TimeOfDay? fromTime,
    TimeOfDay? toTime,
    bool showSleep = true,
    bool showFeeding = true,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> args = [];

    if (fromDate != null) {
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}startTime >= ?';
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}startTime <= ?';
      args.add(toDate.toIso8601String());
    }
    if (fromTime != null) {
      final formattedFromTime = '${fromTime.hour.toString().padLeft(2, '0')}:${fromTime.minute.toString().padLeft(2, '0')}:00';
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}strftime(\'%H:%M:%S\', startTime) >= ?';
      args.add(formattedFromTime);
    }
    if (toTime != null) {
      final formattedToTime = '${toTime.hour.toString().padLeft(2, '0')}:${toTime.minute.toString().padLeft(2, '0')}:59';
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}strftime(\'%H:%M:%S\', startTime) <= ?';
      args.add(formattedToTime);
    }

    String sleepQuery = '';
    String feedingQuery = '';
    if (showSleep) {
      sleepQuery = "SELECT id, startTime, 'sleep' as type FROM sleep_entries";
      if (whereClause.isNotEmpty) sleepQuery += ' WHERE $whereClause';
    }
    if (showFeeding) {
      feedingQuery = "SELECT id, startTime, 'feeding' as type FROM feeding_entries";
      if (whereClause.isNotEmpty) feedingQuery += ' WHERE $whereClause';
    }

    String unionQuery = '';
    List<dynamic> unionArgs = [];
    if (showSleep && showFeeding) {
      unionQuery = '$sleepQuery UNION $feedingQuery';
      unionArgs = [...args, ...args];
    } else if (showSleep) {
      unionQuery = sleepQuery;
      unionArgs = args;
    } else if (showFeeding) {
      unionQuery = feedingQuery;
      unionArgs = args;
    } else {
      return [];
    }

    final maps = await db.rawQuery(
      '$unionQuery ORDER BY startTime DESC LIMIT ? OFFSET ?',
      [...unionArgs, limit, offset],
    );

    List<dynamic> entries = [];
    for (var map in maps) {
      if (map['type'] == 'sleep') {
        final entry = await getSleepEntryById(map['id'] as int);
        if (entry != null) entries.add(entry);
      } else if (map['type'] == 'feeding') {
        final entry = await getFeedingEntryById(map['id'] as int);
        if (entry != null) entries.add(entry);
      }
    }
    return entries;
  }

  Future<int> getCombinedCount({
    DateTime? fromDate,
    DateTime? toDate,
    TimeOfDay? fromTime,
    TimeOfDay? toTime,
    bool showSleep = true,
    bool showFeeding = true,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> args = [];

    if (fromDate != null) {
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}startTime >= ?';
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}startTime <= ?';
      args.add(toDate.toIso8601String());
    }
    if (fromTime != null) {
      final formattedFromTime = '${fromTime.hour.toString().padLeft(2, '0')}:${fromTime.minute.toString().padLeft(2, '0')}:00';
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}strftime(\'%H:%M:%S\', startTime) >= ?';
      args.add(formattedFromTime);
    }
    if (toTime != null) {
      final formattedToTime = '${toTime.hour.toString().padLeft(2, '0')}:${toTime.minute.toString().padLeft(2, '0')}:59';
      whereClause += '${whereClause.isNotEmpty ? ' AND ' : ''}strftime(\'%H:%M:%S\', startTime) <= ?';
      args.add(formattedToTime);
    }

    int count = 0;
    if (showSleep) {
      count += Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM sleep_entries${whereClause.isNotEmpty ? ' WHERE $whereClause' : ''}',
            args,
          )) ??
          0;
    }
    if (showFeeding) {
      count += Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM feeding_entries${whereClause.isNotEmpty ? ' WHERE $whereClause' : ''}',
            args,
          )) ??
          0;
    }
    return count;
  }
}