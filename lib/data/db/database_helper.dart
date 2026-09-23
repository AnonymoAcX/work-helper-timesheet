import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:work_helper/utils/money.dart';
import 'package:work_helper/utils/num_utils.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Future<Database>? _opening;
  static String? databasePathOverrideForTest;

  DatabaseHelper._init();

  /// 缓存开库 Future：并发首访只开一次。
  Future<Database> get database => _opening ??= _initDB('work_helper.db');

  /// 测试隔离钩子：清空缓存的 [_opening]，下次访问重建全新内存库。
  /// 旧连接以孤悬 Future 尽力关闭——前序用例结束时若仍有在途查询挂在该
  /// 连接锁上，await close 会反向挂死 teardown；不 await 则健康用例照常
  /// 释放句柄，挂死用例随测试进程退出自然回收。仅供测试，不改运行期行为。
  @visibleForTesting
  Future<void> resetForTest() async {
    final pending = _opening;
    _opening = null;
    if (pending == null) return;
    pending
        .then((db) async => db.close())
        .catchError((Object _) {
          // 旧连接开库本身失败/挂死：没有可关闭的句柄，忽略即可。
        });
  }

  Future<Database> _initDB(String filePath) async {
    final path =
        databasePathOverrideForTest ??
        join(await databaseFactory.getDatabasesPath(), filePath);
    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createDB,
        onOpen: _ensureSchema,
      ),
    );
  }

  /// 建表唯一事实源：onCreate/onOpen 共用 _ensureSchema 一套 DDL。
  Future _createDB(Database db, int version) async {
    await _ensureSchema(db);
  }

  Future<void> _ensureSchema(Database db) async {
    await _createUserTable(db);
    await _createRecordTable(db);
    await _ensureUserColumns(db);
    await _ensureRecordColumns(db);
    await _createTodoTable(db);
    await _ensureTodoColumns(db);
  }

  Future<void> _createUserTable(Database db) async {
    // phone 为预留列：本机不使用，备份导出剥离、恢复恒写空串。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user (
        id INTEGER PRIMARY KEY,
        phone TEXT,
        name TEXT,
        calculate_day INTEGER DEFAULT 1
      )
    ''');
    final existing = await db.query('user', limit: 1);
    if (existing.isEmpty) {
      await db.insert('user', {
        'id': 1,
        'phone': '',
        'name': '',
        'calculate_day': 1,
      });
    }
  }

  Future<void> _createRecordTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS record (
        id TEXT PRIMARY KEY,
        workload_type INTEGER DEFAULT 0,
        workload REAL DEFAULT 0.0,
        unit_price REAL DEFAULT 0.0,
        preset_price REAL DEFAULT 0.0,
        remark TEXT DEFAULT '',
        date INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _createTodoTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todo (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        remark TEXT,
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        done INTEGER DEFAULT 0
      )
    ''');
  }

  Future<Set<String>> _columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'].toString()).toSet();
  }

  Future<void> _ensureUserColumns(Database db) async {
    final columns = await _columns(db, 'user');
    if (!columns.contains('calculate_day')) {
      await db.execute(
        'ALTER TABLE user ADD COLUMN calculate_day INTEGER DEFAULT 1',
      );
    }
  }

  Future<void> _ensureRecordColumns(Database db) async {
    final columns = await _columns(db, 'record');
    final migrations = <String, String>{
      'workload_type':
          'ALTER TABLE record ADD COLUMN workload_type INTEGER DEFAULT 0',
      'workload': 'ALTER TABLE record ADD COLUMN workload REAL DEFAULT 0.0',
      'unit_price': 'ALTER TABLE record ADD COLUMN unit_price REAL DEFAULT 0.0',
      'preset_price':
          'ALTER TABLE record ADD COLUMN preset_price REAL DEFAULT 0.0',
      'remark': "ALTER TABLE record ADD COLUMN remark TEXT DEFAULT ''",
      'date': 'ALTER TABLE record ADD COLUMN date INTEGER DEFAULT 0',
    };
    for (final entry in migrations.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  Future<void> _ensureTodoColumns(Database db) async {
    final columns = await _columns(db, 'todo');
    final migrations = <String, String>{
      'done': 'ALTER TABLE todo ADD COLUMN done INTEGER DEFAULT 0',
    };
    for (final entry in migrations.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  /// 按月结算周期汇总工资：user、record 各查一次；金额逐行取整到「分」后
  /// 整数累加，与展示/CSV 共用 Money 同一舍入口径；返回「元」double 仅供展示。
  Future<double> calculateMonthlySalary(int year, int month) async {
    final db = await instance.database;
    // 统一经 getCalculateDay 读取：clamp 收口单一源，杜绝脏库数据造成
    // 结算窗口与展示/查询分叉。
    final calculateDay = await getCalculateDay();
    final start = DateTime(year, month, calculateDay);
    final end = DateTime(year, month + 1, calculateDay);
    final records = await db.query(
      'record',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );

    var cents = 0;
    for (final r in records) {
      final preset = NumUtils.asDouble(r['preset_price']);
      final price = preset > 0 ? preset : NumUtils.asDouble(r['unit_price']);
      cents += Money.yuanToCents(NumUtils.asDouble(r['workload']) * price);
    }
    return Money.centsToYuan(cents);
  }

  Future<void> updateUserName(String name) async {
    final db = await instance.database;
    await db.update('user', {'name': name}, where: 'id = 1');
  }

  Future<void> updateCalculateDay(int day) async {
    final db = await instance.database;
    await db.update(
      'user',
      {'calculate_day': day.clamp(1, 28)},
      where: 'id = 1',
    );
  }

  Future<String> getUserName() async {
    final db = await instance.database;
    final res = await db.query('user', limit: 1);
    return res.isNotEmpty ? (res.first['name']?.toString() ?? '') : '';
  }

  /// 读侧 clamp 与写侧 [updateCalculateDay]、备份校验 `_validateUsers`
  /// 同锁 1-28 口径：脏库值不得形成窗口分叉面。
  Future<int> getCalculateDay() async {
    final db = await instance.database;
    final res = await db.query('user', limit: 1);
    return res.isNotEmpty
        ? NumUtils.asInt(res.first['calculate_day'], fallback: 1).clamp(1, 28)
        : 1;
  }

  Future<List<Map<String, dynamic>>> recordsForMonth(
    int year,
    int month,
  ) async {
    final db = await instance.database;
    final calculateDay = await getCalculateDay();
    final start = DateTime(year, month, calculateDay);
    final end = DateTime(year, month + 1, calculateDay);
    return db.query(
      'record',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> todosForDate(DateTime date) async {
    final db = await instance.database;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).millisecondsSinceEpoch;
    return db.query(
      'todo',
      where: 'date >= ? AND date < ?',
      whereArgs: [start, end],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> insertTodo(Map<String, dynamic> todo) async {
    final db = await instance.database;
    await db.insert('todo', todo, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTodo(String id) async {
    final db = await instance.database;
    await db.delete('todo', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTodoDone(String id, bool done) async {
    final db = await instance.database;
    await db.update(
      'todo',
      {'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static const int backupSchemaVersion = 2;

  /// 备份校验错误中面向用户的业务名词（替代内部表名）。
  static const Map<String, String> _backupTableLabels = {
    'record': '工时记录',
    'todo': '待办事项',
    'user': '本机设置',
  };

  /// 导出 record、todo、user 三表为单个 JSON 结构，含元信息。
  Future<Map<String, dynamic>> exportAll({
    Map<String, dynamic>? settings,
  }) async {
    final db = await instance.database;
    final users = await db.query('user');
    final publicUsers = users
        .map((row) => Map<String, dynamic>.from(row)..remove('phone'))
        .toList(growable: false);
    return {
      'schemaVersion': backupSchemaVersion,
      'backupAt': DateTime.now().millisecondsSinceEpoch,
      'record': await db.query('record'),
      'todo': await db.query('todo'),
      'user': publicUsers,
      'settings': ?settings,
    };
  }

  /// 整表恢复（清空后写入，同一事务）。校验失败抛 [FormatException]，不写库。
  /// 返回恢复的总行数。
  Future<int> importAll(Map<String, dynamic> data) async {
    final version = data['schemaVersion'];
    if (version != 1 && version != backupSchemaVersion) {
      throw FormatException('不支持的备份版本：${version ?? '缺失'}');
    }
    if (data['backupAt'] is! num) {
      throw const FormatException('备份文件缺少生成时间信息');
    }
    const tables = ['record', 'todo', 'user'];
    for (final table in tables) {
      if (data[table] is! List) {
        throw FormatException('备份文件缺少${_backupTableLabels[table]}数据');
      }
      if (table == 'user') _validateUsers(data[table] as List);
    }
    final db = await instance.database;
    var count = 0;
    await db.transaction((txn) async {
      for (final table in tables) {
        count += await _restoreTable(txn, table, data[table] as List);
      }
    });
    return count;
  }

  void _validateUsers(List rows) {
    if (rows.isEmpty) throw const FormatException('备份缺少本地设置');
    if (rows.length != 1) throw const FormatException('备份中的本地设置无效');
    for (final row in rows) {
      if (row is! Map) throw const FormatException('本地设置无法识别');
      final name = row['name'];
      final day = row['calculate_day'];
      if (name is! String || day is! int || day < 1 || day > 28) {
        throw const FormatException('备份中的本地设置无效');
      }
      if (name.runes.length > 12) {
        throw const FormatException('备份中的本地设置无效');
      }
    }
  }

  /// 事务内清空整表并按备份原样写回（null 列保留），返回写入行数。
  Future<int> _restoreTable(Transaction txn, String table, List rows) async {
    await txn.delete(table);
    var written = 0;
    for (final row in rows) {
      if (row is! Map) {
        throw FormatException('备份文件中的${_backupTableLabels[table]}数据无法识别');
      }
      // 纵深防护：record 行 date 显式为 null 时在日期窗口查询下永不可见，
      // 写回只会形成数据黑洞；跳过该行、不计入恢复行数统计。
      // 缺 date 键的行仍走列 DEFAULT 0，行为不变。
      if (table == 'record' && row.containsKey('date') && row['date'] == null) {
        continue;
      }
      final values = table == 'user'
          ? <String, Object?>{
              'id': 1,
              'phone': '',
              'name': row['name'],
              'calculate_day': row['calculate_day'],
            }
          : Map<String, Object?>.from(row);
      await txn.insert(table, values);
      written++;
    }
    return written;
  }
}
