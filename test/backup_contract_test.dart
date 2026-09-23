import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_helper/data/db/database_helper.dart';

final isFormatFailure = isA<FormatException>();

void main() {
  late DatabaseHelper helper;

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // L-14/M-10：每个用例全新内存库，切断跨用例数据行依赖链。
  setUp(() async {
    DatabaseHelper.databasePathOverrideForTest = sqflite.inMemoryDatabasePath;
    await DatabaseHelper.instance.resetForTest();
    helper = DatabaseHelper.instance;
  });

  tearDown(() async {
    await DatabaseHelper.instance.resetForTest();
    DatabaseHelper.databasePathOverrideForTest = null;
  });

  Future<Database> openDb() => helper.database;

  Future<List<Map<String, Object?>>> rowsOf(String table) async {
    final db = await openDb();
    return db.query(table, orderBy: 'id');
  }

  Future<Map<String, dynamic>> exportPayload() async {
    return jsonDecode(jsonEncode(await helper.exportAll()))
        as Map<String, dynamic>;
  }

  /// 在当前库种一条记录与一条待办，供回滚断言有可观察内容。
  Future<void> seedRows() async {
    final db = await openDb();
    await db.insert('record', {
      'id': 'r1',
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '',
      'date': 1725000000000,
    });
    await db.insert('todo', {
      'id': 't1',
      'title': '种下待办',
      'remark': null,
      'date': 1725000000000,
      'created_at': 1724999999000,
    });
  }

  test('exportAll -> wipe -> importAll keeps every row identical', () async {
    final db = await openDb();
    await db.update('user', {'name': '张三'}, where: 'id = ?', whereArgs: [1]);
    await db.insert('record', {
      'id': 'r1',
      'workload_type': 1,
      'workload': 8.0,
      'unit_price': 25.0,
      'preset_price': 0.0,
      'remark': '正常班',
      'date': 1725000000000,
    });
    // null 列必须原样还原：preset_price 显式写 null（列默认值 0.0 会掩盖丢弃行为）
    await db.insert('record', {
      'id': 'r2',
      'workload_type': 7,
      'workload': null,
      'unit_price': null,
      'preset_price': null,
      'date': 1725000001000,
    });
    await db.insert('todo', {
      'id': 't1',
      'title': '提交周报',
      'remark': null,
      'date': 1725000000000,
      'created_at': 1724999999000,
    });

    final payload = await exportPayload();
    final before = {
      'record': await rowsOf('record'),
      'todo': await rowsOf('todo'),
      'user': await rowsOf('user'),
    };

    await db.delete('record');
    await db.delete('todo');
    await db.delete('user');
    expect(await rowsOf('record'), isEmpty);

    final count = await helper.importAll(payload);
    expect(count, 4);
    for (final table in before.keys) {
      expect(await rowsOf(table), before[table], reason: '$table 内容不一致');
    }
  });

  test('tampered schemaVersion throws and leaves the db untouched', () async {
    await seedRows();
    final before = await rowsOf('record');
    final payload = await exportPayload();
    payload['schemaVersion'] = 999;
    await expectLater(helper.importAll(payload), throwsA(isFormatFailure));
    expect(await rowsOf('record'), before);
  });

  // L-15：backupAt 缺键 / 非数值必须在写库前被拒。
  test('backupAt missing or non-numeric throws and leaves the db untouched',
      () async {
    await seedRows();
    final before = {
      'record': await rowsOf('record'),
      'todo': await rowsOf('todo'),
      'user': await rowsOf('user'),
    };
    final missing = await exportPayload();
    missing.remove('backupAt');
    await expectLater(helper.importAll(missing), throwsA(isFormatFailure));

    final wrongType = await exportPayload();
    wrongType['backupAt'] = '昨天';
    await expectLater(helper.importAll(wrongType), throwsA(isFormatFailure));
    for (final table in before.keys) {
      expect(await rowsOf(table), before[table], reason: '$table 内容不一致');
    }
  });

  test('missing table throws and leaves the db untouched', () async {
    await seedRows();
    final payload = await exportPayload();
    payload.remove('todo');
    await expectLater(helper.importAll(payload), throwsA(isFormatFailure));
    expect(await rowsOf('todo'), hasLength(1));
    expect(await rowsOf('record'), hasLength(1));
  });

  test('a malformed row rolls the whole restore back', () async {
    await seedRows();
    final payload = await exportPayload();
    payload['record'] = [
      {'id': 'bad'},
      42,
    ];
    await expectLater(helper.importAll(payload), throwsA(isFormatFailure));
    expect(await rowsOf('record'), hasLength(1));
  });

  test('v1 user phone is ignored and never restored', () async {
    final db = await openDb();
    final payload = await exportPayload();
    expect(payload['user'], everyElement(isNot(contains('phone'))));
    payload['schemaVersion'] = 1;
    payload['user'] = [
      {
        'id': 1,
        'phone': 'legacy-phone',
        'name': '本机昵称',
        'calculate_day': 12,
        'unexpected': 'ignored',
      },
    ];

    await helper.importAll(payload);

    final user = (await db.query('user')).single;
    expect(user['id'], 1);
    expect(user['phone'], '');
    expect(user['name'], '本机昵称');
    expect(user['calculate_day'], 12);
    expect(user.containsKey('unexpected'), isFalse);
  });

  test('an invalid user row rolls the whole restore back', () async {
    await seedRows();
    final before = {
      'record': await rowsOf('record'),
      'todo': await rowsOf('todo'),
      'user': await rowsOf('user'),
    };
    final payload = await exportPayload();
    payload['user'] = [
      {'id': 1, 'name': '超过十二个字的昵称会被拒绝', 'calculate_day': 12},
    ];

    await expectLater(helper.importAll(payload), throwsA(isFormatFailure));
    for (final table in before.keys) {
      expect(await rowsOf(table), before[table], reason: '$table 内容不一致');
    }
  });

  // L-15：user 表空数组必须被拒（导入后系统将无设置行可读）。
  test('"user":[] throws and leaves the db untouched', () async {
    await seedRows();
    final beforeUser = await rowsOf('user');
    final payload = await exportPayload();
    payload['user'] = [];
    await expectLater(helper.importAll(payload), throwsA(isFormatFailure));
    expect(await rowsOf('user'), beforeUser);
  });

  // L-15：calculate_day 越界（0 / 29）拒绝，边界内（1 / 28）接受。
  test('calculate_day 0 and 29 are rejected, 1 and 28 are accepted', () async {
    for (final day in [0, 29]) {
      final payload = await exportPayload();
      payload['user'] = [
        {'id': 1, 'name': '边界', 'calculate_day': day},
      ];
      await expectLater(
        helper.importAll(payload),
        throwsA(isFormatFailure),
        reason: 'calculate_day=$day 应被拒绝',
      );
    }
    for (final day in [1, 28]) {
      final payload = await exportPayload();
      payload['user'] = [
        {'id': 1, 'name': '边界', 'calculate_day': day},
      ];
      await helper.importAll(payload);
      expect((await rowsOf('user')).single['calculate_day'], day);
    }
  });

  // L-15：任意 user 行 id 强制重编号为 1（表契约恒单行 id=1）。
  test('user row with foreign id is restored renumbered to 1', () async {
    final payload = await exportPayload();
    payload['user'] = [
      {'id': 7, 'name': '外来源头', 'calculate_day': 5},
    ];
    await helper.importAll(payload);
    final user = (await rowsOf('user')).single;
    expect(user['id'], 1);
    expect(user['name'], '外来源头');
    expect(user['calculate_day'], 5);
  });

  // L-15：值类型畸形（列值为 Map）不是解析期 FormatException，
  // 必须以可识别错误原样上抛且整事务回滚，锁定 DB 层语义
  // （屏层 catch→提示的分支归 settings_screen，不在本用例范围）。
  test('a row with an unbindable value type surfaces an identifiable error '
      'and rolls the whole restore back', () async {
    await seedRows();
    final before = {
      'record': await rowsOf('record'),
      'todo': await rowsOf('todo'),
      'user': await rowsOf('user'),
    };
    final payload = await exportPayload();
    payload['record'] = [
      {'id': 'nested', 'workload': {'not': 'bindable'}},
    ];

    Object? thrown;
    try {
      await helper.importAll(payload);
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull, reason: '不可绑定值必须上抛，不得静默吞掉');
    expect(
      thrown,
      anyOf(isA<FormatException>(), isA<DatabaseException>(), isA<ArgumentError>()),
      reason: '实际抛出的错误类型：$thrown',
    );
    for (final table in before.keys) {
      expect(await rowsOf(table), before[table], reason: '$table 未回滚');
    }
  });
}
