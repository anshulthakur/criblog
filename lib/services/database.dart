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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime TEXT NOT NULL,
            endTime TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE feeding_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime TEXT NOT NULL,
            endTime TEXT,
            source TEXT NOT NULL
          )
        ''');
      },
      // onUpgrade: (db, oldVersion, newVersion) async {
      //   if (oldVersion < 2) {
      //     await db.execute('ALTER TABLE feeding_entries ADD COLUMN endTime TEXT');
      //   }
      //   if (oldVersion < 3) {
      //     await db.execute('ALTER TABLE feeding_entries ADD COLUMN source TEXT NOT NULL DEFAULT "breast"');
      //     await db.rawUpdate('UPDATE feeding_entries SET source = "breast" WHERE source IS NULL');
      //   }
      // },
    );
  }

  // === Sleep CRUD ===
  Future<int> insertSleepEntry(SleepEntry entry) async {
    final db = await database;
    final id = await db.insert('sleep_entries', entry.toMap());
    debugPrint('Inserted sleep entry with id: $id');
    return id;
  }

  Future<List<SleepEntry>> getSleepEntries() async {
    final db = await database;
    final maps = await db.query('sleep_entries', orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) => SleepEntry.fromMap(maps[i]));
  }

  Future<SleepEntry?> getSleepEntryById(int id) async {
    final db = await database;
    final maps = await db.query('sleep_entries', where: 'id = ?', whereArgs: [id]);
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
    final count = await db.update(
      'sleep_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );

    debugPrint('updateSleepEntry: updated $count rows');
  }

  Future<void> deleteSleepEntry(int id) async {
    final db = await database;
    await db.delete(
      'sleep_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // === Feeding CRUD ===
  Future<int> insertFeedingEntry(FeedingEntry entry) async {
    final db = await database;
    final id = await db.insert('feeding_entries', entry.toMap());
    debugPrint('Inserted feeding entry with id: $id');
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
  final count = await db.update(
    'feeding_entries',
    entry.toMap(),
    where: 'id = ?',
    whereArgs: [entry.id],
  );

  debugPrint('updateFeedingEntry: updated $count rows');
}


  Future<void> deleteFeedingEntry(int id) async {
    final db = await database;
    await db.delete(
      'feeding_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Helpers
  Future<SleepEntry?> getOngoingSleep() async {
    final entries = await getSleepEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  Future<FeedingEntry?> getOngoingFeeding() async {
    final entries = await getFeedingEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  // Combined Queries for Pagination
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
      unionArgs = [...args, ...args]; // Duplicate args for both parts
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