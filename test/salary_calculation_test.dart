import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/services/reminder_notification_service.dart';
import 'package:work_helper/utils/money.dart';
import 'package:work_helper/utils/num_utils.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    // 钉住 Asia/Shanghai，使 nextTriggerAt 断言与宿主机时区无关。
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });

  group('Money 分单位口径', () {
    test('yuanToCents 归整到分', () {
      expect(Money.yuanToCents(0.05), 5);
      // 26.555 存储值（26.5549…972）略小于十进制；×100 乘积经 IEEE754
      // 舍入精确为 2655.5；round 远离零 → 2656 分。以实际实现口径为权威。
      expect(Money.yuanToCents(26.555), 2656);
      expect(Money.yuanToCents(-1.5), -150);
    });

    test('yuanToCents 对非有限值 fast-fail', () {
      expect(() => Money.yuanToCents(double.nan), throwsUnsupportedError);
      expect(
        () => Money.yuanToCents(double.infinity),
        throwsUnsupportedError,
      );
    });

    test('centsToYuan / formatYuan 精确还原', () {
      expect(Money.centsToYuan(15), 0.15);
      expect(Money.formatYuan(12345), '123.45');
      expect(Money.formatYuan(5), '0.05');
      expect(Money.formatYuan(-50), '-0.50');
      expect(Money.formatYuan(0), '0.00');
    });
  });

  group('WorkMinutes 分钟口径', () {
    test('8:30 往返无损', () {
      expect(WorkMinutes.hoursToMinutes(8.5), 510);
      expect(WorkMinutes.minutesToHours(510), 8.5);
      expect(WorkMinutes.minutesToHours(WorkMinutes.hoursToMinutes(8.5)), 8.5);
      // 425 分钟是无限循环小数小时（7.0833…），十进制口径必然截断。
      expect(WorkMinutes.hoursTextFromMinutes(425), '7小时5分');
    });

    test('hoursTextFromMinutes 各分支', () {
      expect(WorkMinutes.hoursTextFromMinutes(0), '0分');
      expect(WorkMinutes.hoursTextFromMinutes(45), '45分');
      expect(WorkMinutes.hoursTextFromMinutes(60), '1小时');
      expect(WorkMinutes.hoursTextFromMinutes(90), '1小时30分');
      expect(WorkMinutes.hoursTextFromMinutes(-90), '-1小时30分');
    });

    test('hoursToMinutes 对非有限值 fast-fail', () {
      expect(
        () => WorkMinutes.hoursToMinutes(double.nan),
        throwsUnsupportedError,
      );
    });
  });

  group('NumUtils 病态值兜底', () {
    test('asDouble 绝不产出 NaN/Infinity', () {
      expect(NumUtils.asDouble(null), 0.0);
      expect(NumUtils.asDouble('abc'), 0.0);
      expect(NumUtils.asDouble(double.nan), 0.0);
      expect(NumUtils.asDouble(double.infinity), 0.0);
      expect(NumUtils.asDouble(double.nan, fallback: -1), -1.0);
      expect(NumUtils.asDouble(true), 1.0);
      expect(NumUtils.asDouble(false), 0.0);
      expect(NumUtils.asDouble(' 12.5 '), 12.5);
      expect(NumUtils.asDouble(-3), -3.0);
    });

    test('asInt 向零截断、失败走 fallback', () {
      expect(NumUtils.asInt(1.9), 1);
      expect(NumUtils.asInt('2.5'), 2);
      expect(NumUtils.asInt(-2.5), -2);
      expect(NumUtils.asInt('abc', fallback: 1), 1);
      expect(NumUtils.asInt('', fallback: 7), 7);
      expect(NumUtils.asInt(double.nan, fallback: 9), 9);
      expect(NumUtils.asInt(true), 1);
      expect(NumUtils.asInt(null), 0);
    });
  });

  group('nextTriggerAt 纯函数（不初始化插件）', () {
    tz.TZDateTime at(int y, int m, int d, int h, int mi) =>
        tz.TZDateTime(tz.local, y, m, d, h, mi);

    test('到点前 → 今天', () {
      final r = ReminderNotificationService.nextTriggerAt(
        at(2030, 1, 10, 20, 29),
        20,
        30,
      );
      expect(r, at(2030, 1, 10, 20, 30));
    });

    test('到点后 → 明天', () {
      final r = ReminderNotificationService.nextTriggerAt(
        at(2030, 1, 10, 20, 31),
        20,
        30,
      );
      expect(r, at(2030, 1, 11, 20, 30));
    });

    test('恰好相等 → 视为已过点，顺延明天', () {
      final r = ReminderNotificationService.nextTriggerAt(
        at(2030, 1, 10, 20, 30),
        20,
        30,
      );
      expect(r, at(2030, 1, 11, 20, 30));
    });

    test('月末顺延跨月', () {
      final r = ReminderNotificationService.nextTriggerAt(
        at(2030, 1, 31, 23, 0),
        20,
        30,
      );
      expect(r, at(2030, 2, 1, 20, 30));
    });
  });

  group('calculateMonthlySalary 分单位聚合（内存库）', () {
    late DatabaseHelper helper;

    setUp(() async {
      DatabaseHelper.databasePathOverrideForTest =
          sqflite.inMemoryDatabasePath;
      await DatabaseHelper.instance.resetForTest();
      helper = DatabaseHelper.instance;
    });

    tearDown(() async {
      await DatabaseHelper.instance.resetForTest();
      DatabaseHelper.databasePathOverrideForTest = null;
    });

    Future<void> insertRecord({
      required String id,
      required Object? workload,
      required Object? unitPrice,
      Object? presetPrice = 0.0,
      required DateTime date,
    }) async {
      final db = await helper.database;
      await db.insert('record', {
        'id': id,
        'workload_type': 0,
        'workload': workload,
        'unit_price': unitPrice,
        'preset_price': presetPrice,
        'remark': '',
        'date': date.millisecondsSinceEpoch,
      });
    }

    test('0.05 x 3 行聚合恰为 0.15（浮点直加会得到 0.15000000000000002）', () async {
      for (final (i, day) in [
        (0, 2),
        (1, 15),
        (2, 30),
      ]) {
        await insertRecord(
          id: 'r$i',
          workload: 0.05,
          unitPrice: 1.0,
          date: DateTime(2026, 3, day),
        );
      }
      expect(await helper.calculateMonthlySalary(2026, 3), 0.15);
    });

    test('preset 优先于 unit；脏值经 NumUtils 兜底为 0，不再放大', () async {
      await insertRecord(
        id: 'preset',
        workload: 8.0,
        unitPrice: 20.0,
        presetPrice: 30.0,
        date: DateTime(2026, 3, 10),
      );
      await insertRecord(
        id: 'null-workload',
        workload: null,
        unitPrice: 20.0,
        date: DateTime(2026, 3, 10),
      );
      await insertRecord(
        id: 'nan-workload',
        workload: double.nan,
        unitPrice: 20.0,
        date: DateTime(2026, 3, 10),
      );
      await insertRecord(
        id: 'dirty-rate',
        workload: 8.0,
        unitPrice: '脏值',
        date: DateTime(2026, 3, 10),
      );
      // 仅 preset 行计薪：8 x 30 = 240 元。
      expect(await helper.calculateMonthlySalary(2026, 3), 240.0);
    });

    test('结算窗口按 calculate_day：起含、止不含', () async {
      await helper.updateCalculateDay(5);
      await insertRecord(
        id: 'at-start',
        workload: 10.0,
        unitPrice: 10.0,
        date: DateTime(2026, 3, 5),
      );
      await insertRecord(
        id: 'last-included',
        workload: 5.0,
        unitPrice: 10.0,
        date: DateTime(2026, 4, 4, 23, 59, 59, 999),
      );
      await insertRecord(
        id: 'before-start',
        workload: 99.9,
        unitPrice: 10.0,
        date: DateTime(2026, 3, 4, 23, 59, 59, 999),
      );
      await insertRecord(
        id: 'at-end',
        workload: 99.9,
        unitPrice: 10.0,
        date: DateTime(2026, 4, 5),
      );
      expect(await helper.calculateMonthlySalary(2026, 3), 150.0);
    });

    test('无记录周期返回 0.0', () async {
      expect(await helper.calculateMonthlySalary(2026, 3), 0.0);
    });

    // 脏库越界 calculate_day 读侧收口 1-28，与写侧/备份校验同锁；
    // 结算窗口与 getCalculateDay 同源（写 35 → 读 28）。
    test('calculate_day 越界读侧钳制 1-28 且窗口同源', () async {
      final db = await helper.database;
      await db.update('user', {'calculate_day': 0}, where: 'id = 1');
      expect(await helper.getCalculateDay(), 1);
      await db.update('user', {'calculate_day': 35}, where: 'id = 1');
      expect(await helper.getCalculateDay(), 28);
      // 脏值 35 按 28 参与结算：窗口 [3-28, 4-28) 起含止不含。
      await insertRecord(
        id: 'clamped-window-start',
        workload: 10.0,
        unitPrice: 10.0,
        date: DateTime(2026, 3, 28),
      );
      await insertRecord(
        id: 'before-clamped-window',
        workload: 10.0,
        unitPrice: 10.0,
        date: DateTime(2026, 3, 27, 23, 59, 59, 999),
      );
      expect(await helper.calculateMonthlySalary(2026, 3), 100.0);
    });
  });
}
