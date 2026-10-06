// 截图生成测试：真实渲染应用页面并输出 PNG。
//
// 说明：
// - 测试引擎（flutter_tester）不携带系统中文字体，中文会渲染为方块。
//   这里把系统「微软雅黑」字体文件以引擎默认族名 Roboto 注册进
//   字体集合，全部默认文本随之真实渲染中文；仅测试内生效。
// - 演示数据走内存库（sqflite_common_ffi）注入，不含任何真实个人信息；
//   班次文案使用「上午班/下午班」等中性词。
// - 产物输出到 build/screenshot-raw/（1080x2340），由脚本改名后送入
//   screenshots/。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/main.dart';

/// 手机竖屏：物理 1080x2340、DPR 3（逻辑 360x780），截出 1080x2340 PNG。
const Size _phoneSize = Size(1080, 2340);
const double _density = 3.0;

/// 截图生成依赖运行机本机的中文字体与图标字体文件；其他环境
/// （CI、无这些文件的机器）自动跳过，避免 golden 对比必败阻塞 `flutter test`。
/// 中文字体用系统等线（Windows 系统常量路径）；图标字体取项目内置
/// SDK 缓存，按运行目录推导，不在源码里写死机器绝对路径。
String get _materialIconsFontPath {
  final base = Directory.current.path;
  return '$base/.flutter-sdk/flutter/bin/cache/artifacts/'
      'material_fonts/MaterialIcons-Regular.otf';
}

bool get _hostFontsAvailable =>
    File('C:/Windows/Fonts/Deng.ttf').existsSync() &&
    File(_materialIconsFontPath).existsSync();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // 与 widget_test 同一基线：':memory:' + resetForTest。文件库路径不行——
  // sqflite ffi 开库前要 await file.exists()，真实 I/O 在 fake-async
  // zone 里永不完成，整个用例会挂死。
  setUp(() async {
    DatabaseHelper.databasePathOverrideForTest = sqflite.inMemoryDatabasePath;
    await DatabaseHelper.instance.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.instance.resetForTest();
    DatabaseHelper.databasePathOverrideForTest = null;
  });

  Future<void> usePhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = _density;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('渲染中文验证：时薪设置页', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    await pumpApp(tester);

    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时薪设置'));
    await tester.pumpAndSettle();

    await shoot(tester, '00-font-check');
  });

  testWidgets('记录页：日历与最近记录', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime(2026, 10, 6, 9, 30);
    await seedRecords(db, now);
    await pumpApp(tester);

    await shoot(tester, '01-record-home');
  });

  testWidgets('记一笔工时弹窗', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime(2026, 10, 6, 9, 30);
    await seedRecords(db, now);
    await pumpApp(tester);

    await tester.tap(find.text('记工时').first);
    await tester.pumpAndSettle();
    // 预填一个真实感工时，避免弹窗里的输入框是空的。
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.pumpAndSettle();

    await shoot(tester, '02-add-record-sheet');
  });

  testWidgets('统计页：本月薪资汇总', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime(2026, 10, 6, 9, 30);
    await seedRecords(db, now);
    await pumpApp(tester);

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();

    await shoot(tester, '03-salary-stats');
  });

  testWidgets('待办页：当月待办列表', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime(2026, 10, 6, 9, 30);
    await seedRecords(db, now);
    await seedTodos(db, now);
    await pumpApp(tester);

    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();

    await shoot(tester, '04-todo');
  });

  testWidgets('设置页', (WidgetTester tester) async {
    if (!_hostFontsAvailable) {
      return;
    }
    await usePhoneViewport(tester);
    await pumpApp(tester);

    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();

    await shoot(tester, '05-settings');
  });
}

/// 统一装帧：注入中文字体、装 Provider 与本地化，pump 主应用。
Future<void> pumpApp(WidgetTester tester) async {
  await loadChineseFont(tester);
  SharedPreferences.setMockInitialValues({
    'settings.hourly_rates': <String>['20.00', '60.00', '80.00'],
    'settings.default_hourly_rate': 60.0,
  });
  final settings = AppSettingsController();
  await settings.load();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(value: settings, child: const MyApp()),
  );
  await tester.pumpAndSettle();
}

/// 把系统等线字体注册为引擎默认族名 Roboto：flutter_tester 里任何未显式
/// 指定字体的文本都会落到 Roboto 族，注册后中文即真实渲染（否则是方块）。
/// 同时注册 MaterialIcons 图标字体，否则底栏/按钮图标全是方块。
/// 真实文件 I/O 与字体引擎调用必须经 tester.runAsync——testWidgets
/// 主体运行在 fake-async zone，裸 await 会永久挂死。
Future<void> loadChineseFont(WidgetTester tester) async {
  await tester.runAsync(() async {
    const fontPath = 'C:/Windows/Fonts/Deng.ttf';
    final fontFile = File(fontPath);
    if (!fontFile.existsSync()) {
      fail('缺少系统字体 $fontPath，无法在测试环境渲染中文');
    }
    final bytes = await fontFile.readAsBytes();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();

    final iconFile = File(_materialIconsFontPath);
    if (iconFile.existsSync()) {
      final iconBytes = await iconFile.readAsBytes();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconBytes.buffer)));
      await iconLoader.load();
    }
  });
}

/// 演示工时记录：本月最近几天，8/6/4 小时交替，时薪 60。
Future<void> seedRecords(sqflite.Database db, DateTime now) async {
  final days = [
    (now, '上午班', 8.0, 0),
    (now.subtract(const Duration(days: 1)), '下午班', 6.0, 1),
    (now.subtract(const Duration(days: 2)), '上午班', 4.0, 2),
    (now.subtract(const Duration(days: 3)), '上午班', 8.0, 0),
    (now.subtract(const Duration(days: 4)), '加班', 2.0, 5),
  ];
  for (var i = 0; i < days.length; i++) {
    final (date, remark, workload, type) = days[i];
    await db.insert('record', {
      'id': 'demo-record-$i',
      'workload_type': type,
      'workload': workload,
      'unit_price': 60.0,
      'preset_price': 60.0,
      'remark': remark,
      'date': DateTime(
        date.year,
        date.month,
        date.day,
        9,
      ).millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  DataStore.instance.bump();
}

/// 演示待办：同一天 3 条，其中 1 条已完成（待办页按日展示，分日会散）。
Future<void> seedTodos(sqflite.Database db, DateTime now) async {
  final rows = [('问一下这个月加班怎么算', 1), ('月底前把考勤表导出', 0), ('下班顺路取一下工牌', 0)];
  final date = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < rows.length; i++) {
    final (title, done) = rows[i];
    await db.insert('todo', {
      'id': 'demo-todo-$i',
      'title': title,
      'remark': '',
      'date': date.millisecondsSinceEpoch,
      'created_at': date
          .subtract(Duration(minutes: 10 * i))
          .millisecondsSinceEpoch,
      'done': done,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// 把当前渲染帧经官方 golden 通道落盘为 PNG（1080x2340）。
/// 路径相对测试文件目录解析；需配合 --update-goldens 运行才会写入。
Future<void> shoot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../build/screenshot-raw/$name.png'),
  );
}
