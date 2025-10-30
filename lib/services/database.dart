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
  Future<void> insertSleepEntry(SleepEntry entry) async {
    final db = await database;
    await db.insert('sleep_entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SleepEntry>> getSleepEntries() async {
    final db = await database;
    final maps = await db.query('sleep_entries', orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) => SleepEntry.fromMap(maps[i]));
  }

  Future<void> updateSleepEntry(SleepEntry entry) async {
    final db = await database;
    await db.update(
      'sleep_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteSleepEntry(int id) async {
    final db = await database;
    await db.delete('sleep_entries', where: 'id = ?', whereArgs: [id]);
  }

  // === Feeding CRUD ===
  Future<void> insertFeedingEntry(FeedingEntry entry) async {
    final db = await database;
    await db.insert('feeding_entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<FeedingEntry>> getFeedingEntries() async {
    final db = await database;
    final maps = await db.query('feeding_entries', orderBy: 'startTime DESC');
    return List.generate(maps.length, (i) => FeedingEntry.fromMap(maps[i]));
  }

  Future<void> updateFeedingEntry(FeedingEntry entry) async {
    final db = await database;
    await db.update(
      'feeding_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteFeedingEntry(int id) async {
    final db = await database;
    await db.delete('feeding_entries', where: 'id = ?', whereArgs: [id]);
  }

  // === Helper Methods ===
  Future<SleepEntry?> getOngoingSleep() async {
    final entries = await getSleepEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  Future<FeedingEntry?> getOngoingFeeding() async {
    final entries = await getFeedingEntries();
    return entries.isNotEmpty && entries.first.endTime == null ? entries.first : null;
  }

  // === Debug / Reset ===
  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete('sleep_entries');
    await db.delete('feeding_entries');
  }
}