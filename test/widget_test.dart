import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/screens/record_screen.dart';
import 'package:work_helper/screens/schedule_screen.dart';
import 'package:work_helper/screens/settings_screen.dart';

import 'package:work_helper/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // 单例连接若跨用例共享，前一用例结束时在途的查询会
  // 永久挂住该连接的内部锁，后续用例的 DB await 全部死锁，表现为
  // ScheduleScreen 加载转圈 → pumpAndSettle 超时级联失败。
  // 每用例 resetForTest 重建全新内存库，从源头切断共享。
  setUp(() async {
    DatabaseHelper.databasePathOverrideForTest = sqflite.inMemoryDatabasePath;
    await DatabaseHelper.instance.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.instance.resetForTest();
    DatabaseHelper.databasePathOverrideForTest = null;
  });

  testWidgets('shows main navigation tabs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('工时'), findsWidgets);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('个人'), findsOneWidget);
  });

  testWidgets('main screens fit a narrow phone viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    expectNoFlutterException(tester, 'initial screen');

    for (final label in ['待办', '统计', '个人']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expectNoFlutterException(tester, label);
    }

    for (final removed in ['收件箱', '工友交流', '建议反馈', '更多设置']) {
      expect(find.text(removed), findsNothing);
    }
    expect(find.text('提醒'), findsOneWidget);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    expect(find.text('通知栏提醒'), findsOneWidget);
    expectNoFlutterException(tester, '提醒设置');
  });

  testWidgets('settings does not expose nickname controls', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.updateUserName('初始昵称');
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    // 设置屏不展示昵称，断言真实存储的昵称值不出现在界面上，
    // 锁定「不暴露昵称控件」的行为本身。
    expect(find.textContaining('初始昵称'), findsNothing);
    expect(find.text('修改昵称'), findsNothing);
  });

  testWidgets('record sheet lists work types and quick workload controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记工时'));
    await tester.pumpAndSettle();

    expect(find.text('班次'), findsOneWidget);
    for (final label in ['白班', '夜班', '早班', '中班', '晚班', '加班', '请假', '休假']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('工作量'), findsOneWidget);
    expect(find.text('8小时'), findsOneWidget);
    expect(find.text('预定时薪'), findsOneWidget);

    await tester.tap(find.text('休假').last);
    await tester.pumpAndSettle();
    expect(find.text('工作量'), findsNothing);
    expect(find.text('预定时薪'), findsNothing);
    expectNoFlutterException(tester, '记工时弹窗');
  });

  testWidgets('record entries can be edited and deleted', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('记工时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '保存'));
    await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
    // 保存链路无延时逻辑（无 Timer/Future.delayed），去掉掩盖性的
    // pump(2s)，只留确定性 pumpAndSettle，避免残留计时器语义。
    await tester.pumpAndSettle();

    expect(find.text('修改'), findsWidgets);
    expect(find.text('删除'), findsWidgets);

    await tester.ensureVisible(find.text('修改').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('修改工时'), findsOneWidget);
    for (final value in ['NaN', 'Infinity', '25']) {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('工时填错了'), findsOneWidget);
      expect(find.textContaining('修改工时'), findsOneWidget);
    }
    expectNoFlutterException(tester, '修改工时弹窗');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除工时'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expectNoFlutterException(tester, '删除确认');
  });

  testWidgets('calendar can move between months', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    // 注入固定时钟（12 月），跨年切换全部确定，不再依赖真实时钟。
    final clock = DateTime(2031, 12, 15, 10, 0);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: RecordScreen(now: () => clock)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('recordMonthTitle'))).data,
      '12',
    );
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('recordMonthTitle'))).data,
      '1',
    );
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('recordMonthTitle'))).data,
      '12',
    );
    expectNoFlutterException(tester, '上下月切换');
  });

  testWidgets('calendar keeps the selected day when moving months', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    final now = DateTime(2030, 1, 31);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: RecordScreen(now: () => now)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '31'),
    );
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2月28日').first, findsOneWidget);
    expectNoFlutterException(tester, '跨月保留选中日期');
  });

  testWidgets('month title opens date picker and applies selected date', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    final now = DateTime.now();
    await tester.tap(find.textContaining('月/').first);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    expect(find.text('六'), findsWidgets);
    expect(find.textContaining('年'), findsWidgets);
    expect(find.textContaining('月'), findsWidgets);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('SELECT DATE'), findsNothing);
    expect(find.text('CANCEL'), findsNothing);
    expect(find.text('OK'), findsNothing);
    expectNoFlutterException(tester, '月份标题日期选择器');
  });

  test('hourly rate visibility is compatible and filters shortcuts', () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rates': ['20.00', '25.00'],
    });
    final settings = AppSettingsController();
    await settings.load();
    expect(settings.visibleHourlyRates, containsAll([20.0, 25.0]));
    await settings.updateHourlyRateVisibility(20, false);
    expect(settings.visibleHourlyRates, isNot(contains(20.0)));
    expect(settings.hourlyRates, contains(20.0));
    await settings.addHourlyRate(30);
    expect(settings.visibleHourlyRates, contains(30.0));
    final reloaded = AppSettingsController();
    await reloaded.load();
    expect(reloaded.visibleHourlyRates, isNot(contains(20.0)));
    expect(reloaded.visibleHourlyRates, contains(25.0));
  });

  testWidgets('month title clamps selected date outside picker range', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    final db = await DatabaseHelper.instance.database;
    await db.delete('record');
    final firstDay = DateTime(2090, 1, 10);
    await db.insert('record', {
      'id': 'picker-boundary',
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '',
      'date': firstDay.millisecondsSinceEpoch,
    });
    addTearDown(
      () =>
          db.delete('record', where: 'id = ?', whereArgs: ['picker-boundary']),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: RecordScreen(now: () => DateTime(2090, 1, 31)),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.text('月/2089年').first);
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expectNoFlutterException(tester, '范围外月份标题日期选择器');
  });

  testWidgets('schedule title follows selected date across months', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScheduleScreen(initialDate: DateTime(2031, 2, 10))),
    );
    await tester.pumpAndSettle();

    // '2' 来自注入的 initialDate（2031年2月），与真实时钟无关；
    // 「今」按定义取真实今天，仅容忍跨午夜瞬间的前后月差，其余确定。
    expect(
      tester.widget<Text>(find.byKey(const Key('scheduleMonthTitle'))).data,
      '2',
    );
    final todayBefore = DateTime.now();
    await tester.tap(find.text('今'));
    await tester.pumpAndSettle();
    final todayAfter = DateTime.now();
    expect(
      [todayBefore.month.toString(), todayAfter.month.toString()],
      contains(
        tester.widget<Text>(find.byKey(const Key('scheduleMonthTitle'))).data,
      ),
    );
    expectNoFlutterException(tester, '待办跨月标题');
  });

  testWidgets('empty todo content stays in the dialog with a field error', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: ScheduleScreen(initialDate: DateTime(2031, 2, 10))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
    await tester.pump();

    expect(find.text('待办内容不能为空'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.widgetWithText(ElevatedButton, '保存'), findsOneWidget);
    expectNoFlutterException(tester, '待办空内容校验');
  });

  // 用例原名与 SettingsScreen 段承载「昵称刷新」语义，但设置屏已彻底
  // 移除昵称展示（findsNothing 恒真）；按已批准行为改名为真实被测行为。
  testWidgets('restore refreshes schedule todos', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = await DatabaseHelper.instance.database;
    final date = DateTime(2032, 3, 4);
    await db.delete('todo', where: 'id = ?', whereArgs: ['restore-todo']);
    await db.insert('todo', {
      'id': 'restore-todo',
      'title': '恢复前待办',
      'remark': '',
      'date': date.millisecondsSinceEpoch,
      'created_at': 1,
    });

    await tester.pumpWidget(
      MaterialApp(home: ScheduleScreen(initialDate: date)),
    );
    await tester.pumpAndSettle();
    expect(find.text('恢复前待办'), findsOneWidget);

    await db.delete('todo', where: 'id = ?', whereArgs: ['restore-todo']);
    await db.insert('todo', {
      'id': 'restore-todo',
      'title': '恢复后待办',
      'remark': '',
      'date': date.millisecondsSinceEpoch,
      'created_at': 2,
    });
    DataStore.instance.bump();
    DataStore.instance.bump();
    DataStore.instance.bump();
    await tester.pumpAndSettle();

    expect(find.text('恢复后待办'), findsOneWidget);
    expect(find.text('恢复前待办'), findsNothing);
    expectNoFlutterException(tester, '连续刷新');

    await db.delete('todo', where: 'id = ?', whereArgs: ['restore-todo']);
  });

  test('hourly rate presets include 10 through 19 after migration', () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rates': ['20.00', '25.00'],
      'settings.hourly_rate_preset_version': 1,
    });
    final settings = AppSettingsController();
    await settings.load();

    for (var rate = 10; rate <= 19; rate++) {
      expect(settings.hourlyRates, contains(rate.toDouble()));
    }
    expect(settings.hourlyRates, containsAll([20.0, 25.0]));
  });

  test('workload quick options save, reload, and filter visibility', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppSettingsController.workloadQuickOptionsKey),
      isNotNull,
    );
    expect(settings.visibleWorkloadQuickOptions, hasLength(8));

    await settings.updateWorkloadQuickOption(
      1,
      settings.workloadQuickOptions[1].copyWith(visible: false),
    );
    await settings.addWorkloadQuickOption(
      const WorkloadQuickOption(label: '半天', minutes: 360, visible: true),
    );

    final reloaded = AppSettingsController();
    await reloaded.load();
    expect(reloaded.workloadQuickOptions[1].visible, isFalse);
    expect(reloaded.visibleWorkloadQuickOptions.map((item) => item.label), [
      '1小时',
      '3小时',
      '4小时',
      '8小时',
      '10小时',
      '11.5小时',
      '12小时',
      '6小时',
    ]);
  });

  test('workloadQuickOptions getter is a stable instance until data changes', () async {
    // Selector 切片相等依赖同一引用——同一数据版本两次读取必须
    // identical；数据实际变化后才换新实例，否则变更无法被订阅方感知。
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    final first = settings.workloadQuickOptions;
    expect(identical(first, settings.workloadQuickOptions), isTrue);
    await settings.removeWorkloadQuickOption(0);
    final second = settings.workloadQuickOptions;
    expect(identical(first, second), isFalse);
    expect(identical(second, settings.workloadQuickOptions), isTrue);
    expect(second, hasLength(first.length - 1));
  });

  test('workload quick options ignore legacy labels when loading', () async {
    SharedPreferences.setMockInitialValues({
      AppSettingsController.workloadQuickOptionsKey: jsonEncode([
        const WorkloadQuickOption(
          label: '旧名称',
          minutes: 90,
          visible: true,
        ).toJson(),
      ]),
    });
    final settings = AppSettingsController();
    await settings.load();

    expect(settings.workloadQuickOptions.single.label, '1.5小时');
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        prefs.getString(AppSettingsController.workloadQuickOptionsKey)!,
      ).single['label'],
      '1.5小时',
    );
  });

  test('malformed workload quick options restore and save defaults', () async {
    SharedPreferences.setMockInitialValues({
      AppSettingsController.workloadQuickOptionsKey:
          '[{"label":"错误","minutes":60}]',
    });
    final settings = AppSettingsController();
    await settings.load();

    expect(
      settings.workloadQuickOptions.map((item) => item.toJson()).toList(),
      AppSettingsController.defaultWorkloadQuickOptions
          .map((item) => item.toJson())
          .toList(),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        prefs.getString(AppSettingsController.workloadQuickOptionsKey)!,
      ),
      AppSettingsController.defaultWorkloadQuickOptions
          .map((item) => item.toJson())
          .toList(),
    );
  });

  testWidgets('record quick buttons consume visible configured options', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      AppSettingsController.workloadQuickOptionsKey: jsonEncode([
        const WorkloadQuickOption(
          label: '半天',
          minutes: 360,
          visible: true,
        ).toJson(),
        const WorkloadQuickOption(
          label: '隐藏项',
          minutes: 420,
          visible: false,
        ).toJson(),
      ]),
    });
    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记工时'));
    await tester.pumpAndSettle();

    expect(find.text('6小时'), findsOneWidget);
    expect(find.text('隐藏项'), findsNothing);
    await tester.tap(find.text('6小时'));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == '6',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings exposes workload quick option controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工时设置'));
    await tester.pumpAndSettle();

    expect(find.text('工时设置'), findsOneWidget);
    expect(find.text('设置记工时页面常用的工时选项，不会修改已有记录。'), findsOneWidget);
    expect(find.text('工时（小时）'), findsNothing);
    expect(find.text('显示'), findsWidgets);
    expect(find.byType(Switch), findsWidgets);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(settings.workloadQuickOptions.first.visible, isFalse);
  });

  testWidgets('settings pages keep the shared visual style contract', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    Future<void> pumpSettingsPage(String title) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            key: ValueKey(title),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    await pumpSettingsPage('工时设置');
    final workloadTitle = find.text('工时设置');
    final workloadTitleColor = tester.widget<Text>(workloadTitle).style?.color;
    final workloadScaffold = tester.widget<Scaffold>(
      find.ancestor(of: workloadTitle, matching: find.byType(Scaffold)),
    );
    final workloadTheme = Theme.of(tester.element(workloadTitle));
    final workloadHeader = tester.widget<Container>(
      find.ancestor(of: workloadTitle, matching: find.byType(Container)),
    );
    final workloadBody = tester.widget<Text>(
      find.text('设置记工时页面常用的工时选项，不会修改已有记录。'),
    );
    final workloadCard = tester.widget<Card>(
      find.ancestor(of: find.text('1小时'), matching: find.byType(Card)),
    );
    final workloadAdd = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '添加',
      ),
    );
    final workloadAddIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '添加',
        ),
        matching: find.byType(Icon),
      ),
    );

    await pumpSettingsPage('时薪设置');
    final hourlyTitle = find.text('时薪设置');
    final hourlyScaffold = tester.widget<Scaffold>(
      find.ancestor(of: hourlyTitle, matching: find.byType(Scaffold)),
    );
    final hourlyTheme = Theme.of(tester.element(hourlyTitle));
    final hourlyHeader = tester.widget<Container>(
      find.ancestor(of: hourlyTitle, matching: find.byType(Container)),
    );
    final hourlyBody = tester.widget<Text>(find.text('¥10.00 / 小时'));
    final hourlyCard = tester.widget<Card>(
      find.ancestor(of: find.text('¥10.00 / 小时'), matching: find.byType(Card)),
    );
    final hourlyAdd = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '添加',
      ),
    );
    final hourlyAddIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '添加',
        ),
        matching: find.byType(Icon),
      ),
    );

    expect(
      workloadScaffold.backgroundColor,
      workloadTheme.scaffoldBackgroundColor,
    );
    expect(hourlyScaffold.backgroundColor, hourlyTheme.scaffoldBackgroundColor);
    expect(workloadScaffold.backgroundColor, hourlyScaffold.backgroundColor);
    expect(workloadHeader.color, const Color(0xFF4C86F7));
    expect(hourlyHeader.color, workloadHeader.color);
    expect(workloadTitleColor, Colors.white);
    expect(tester.widget<Text>(hourlyTitle).style?.color, Colors.white);
    expect(workloadBody.style?.color, workloadTheme.colorScheme.onSurface);
    expect(hourlyBody.style?.color, hourlyTheme.colorScheme.onSurface);
    expect(workloadBody.style?.color, hourlyBody.style?.color);
    expect(workloadCard.color, workloadTheme.cardColor);
    expect(hourlyCard.color, hourlyTheme.cardColor);
    expect(workloadCard.color, hourlyCard.color);
    expect(workloadAdd.runtimeType, IconButton);
    expect(hourlyAdd.runtimeType, IconButton);
    expect(workloadAddIcon.color, Colors.white);
    expect(hourlyAddIcon.color, workloadAddIcon.color);
  });

  testWidgets('settings exposes hourly rate names and visibility controls', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时薪设置'));
    await tester.pumpAndSettle();

    expect(find.text('时薪设置'), findsOneWidget);
    expect(find.text('常用时薪'), findsOneWidget);
    expect(find.text('显示'), findsWidgets);
    expect(find.text('默认时薪'), findsOneWidget);
    expect(find.text('设为默认'), findsWidgets);
    expect(find.text('删除'), findsWidgets);

    final firstSwitch = find.byType(Switch).first;
    expect(settings.visibleHourlyRates, contains(settings.hourlyRates.first));
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    expect(
      settings.visibleHourlyRates,
      isNot(contains(settings.hourlyRates.first)),
    );
  });

  testWidgets('hourly rate circle and default button select the same rate', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时薪设置'));
    await tester.pumpAndSettle();

    final firstRateCard = find.ancestor(
      of: find.text('¥10.00 / 小时'),
      matching: find.byType(Card),
    );
    final secondRateCard = find.ancestor(
      of: find.text('¥11.00 / 小时'),
      matching: find.byType(Card),
    );

    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pumpAndSettle();
    expect(settings.defaultHourlyRate, 10);
    expect(
      find.descendant(
        of: firstRateCard,
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: secondRateCard,
        matching: find.byIcon(Icons.circle_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, '设为默认').first);
    await tester.pumpAndSettle();
    expect(settings.defaultHourlyRate, 11);
    expect(
      find.descendant(
        of: firstRateCard,
        matching: find.byIcon(Icons.circle_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: secondRateCard,
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondRateCard, matching: find.text('默认时薪')),
      findsOneWidget,
    );
  });

  testWidgets('workload settings edits hours without a name field', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      AppSettingsController.workloadQuickOptionsKey: jsonEncode([
        const WorkloadQuickOption(
          label: '旧名称一',
          minutes: 60,
          visible: true,
        ).toJson(),
        const WorkloadQuickOption(
          label: '旧名称二',
          minutes: 120,
          visible: true,
        ).toJson(),
      ]),
    });
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工时设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改').first);
    await tester.pumpAndSettle();

    expect(find.text('编辑工时设置'), findsOneWidget);
    expect(find.text('名称'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '0');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('工时必须大于0且不超过24小时'), findsOneWidget);
    expect(find.text('编辑工时设置'), findsOneWidget);
    expectNoFlutterException(tester, '工时设置非法编辑');

    await tester.enterText(fields.first, 'NaN');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('工时必须大于0且不超过24小时'), findsOneWidget);
    expect(find.text('编辑工时设置'), findsOneWidget);
    expectNoFlutterException(tester, '工时设置非法数字');

    await tester.enterText(fields.first, '2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('工时不能重复'), findsOneWidget);
    expect(find.text('编辑工时设置'), findsOneWidget);
    expectNoFlutterException(tester, '工时设置重复工时');

    await tester.enterText(fields.first, '4.0');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('4小时'), findsOneWidget);
    expectNoFlutterException(tester, '工时设置合法编辑');

    final addButton = find.byTooltip('添加');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('添加工时设置'), findsOneWidget);
    expect(find.text('名称'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '1.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('1.5小时'), findsOneWidget);
    expectNoFlutterException(tester, '工时设置合法添加');
  });

  testWidgets('workload settings shows expected update errors in Chinese', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工时设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改').first);
    await tester.pumpAndSettle();

    await settings.updateWorkloadQuickOption(
      0,
      settings.workloadQuickOptions.first.copyWith(minutes: 30),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('列表已更新，请重新编辑'), findsOneWidget);
    expect(find.text('编辑工时设置'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expectNoFlutterException(tester, '工时设置预期异常反馈');
  });

  testWidgets('workload settings rejects non-finite hours', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: settings, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工时设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改').first);
    await tester.pumpAndSettle();

    for (final value in ['NaN', 'Infinity']) {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('工时必须大于0且不超过24小时'), findsOneWidget);
      expect(find.text('编辑工时设置'), findsOneWidget);
      expectNoFlutterException(tester, '非有限工时编辑');
    }
  });

  testWidgets('today reminder banner follows clock and record refresh', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    // 独立固定日期，隔离其他用例写入的真实今天数据
    final fakeDay = DateTime(2030, 1, 1);
    final db = await DatabaseHelper.instance.database;
    Future<void> clearFakeDay() async {
      await db.delete(
        'record',
        where: 'date >= ? AND date < ?',
        whereArgs: [
          fakeDay.millisecondsSinceEpoch,
          fakeDay.add(const Duration(days: 1)).millisecondsSinceEpoch,
        ],
      );
    }

    await clearFakeDay();
    addTearDown(clearFakeDay);

    Future<void> pumpWithClock(DateTime clock) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(home: RecordScreen(now: () => clock)),
        ),
      );
      await tester.pumpAndSettle();
      expectNoFlutterException(tester, '工时页横幅');
    }

    // 18 点后、今日无记录 → 横幅出现
    await pumpWithClock(DateTime(2030, 1, 1, 18, 0));
    expect(find.text('今天还没记录工时'), findsOneWidget);

    // 插入今日记录并 bump DataStore → 保活页面重查，横幅消失
    await db.insert('record', {
      'id': 'banner-today',
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '',
      'date': DateTime(2030, 1, 1, 9, 0).millisecondsSinceEpoch,
    });
    DataStore.instance.bump();
    await tester.pumpAndSettle();
    expect(find.text('今天还没记录工时'), findsNothing);

    // 删除记录并 bump → 横幅重新出现（刷新机制对删除同样生效）
    await clearFakeDay();
    DataStore.instance.bump();
    await tester.pumpAndSettle();
    expect(find.text('今天还没记录工时'), findsOneWidget);

    // 18 点前且无记录 → 不出现横幅（时间条件独立成立）
    await pumpWithClock(DateTime(2030, 1, 1, 9, 0));
    expect(find.text('今天还没记录工时'), findsNothing);
  });

  testWidgets('copy to tomorrow inserts a next-day record row', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();

    final sourceDay = DateTime(2030, 1, 31);
    final targetDay = DateTime(2030, 2, 1);
    final db = await DatabaseHelper.instance.database;
    Future<void> clearDays() async {
      await db.delete(
        'record',
        where: 'date >= ? AND date < ?',
        whereArgs: [
          sourceDay.millisecondsSinceEpoch,
          targetDay.add(const Duration(days: 1)).millisecondsSinceEpoch,
        ],
      );
    }

    await clearDays();
    addTearDown(clearDays);
    await db.insert('record', {
      'id': 'copy-src',
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '夜班转',
      'date': sourceDay.millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: RecordScreen(now: () => DateTime(2030, 1, 31, 19, 0)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectNoFlutterException(tester, '工时页复制入口');

    expect(find.text('复制'), findsOneWidget);
    await tester.ensureVisible(find.text('复制'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expectNoFlutterException(tester, '复制到明天');

    final copied = await db.query(
      'record',
      where: 'date >= ? AND date < ?',
      whereArgs: [
        targetDay.millisecondsSinceEpoch,
        targetDay.add(const Duration(days: 1)).millisecondsSinceEpoch,
      ],
    );
    expect(copied, hasLength(1));
    final row = copied.single;
    expect(row['id'], isNot('copy-src'));
    expect((row['workload'] as num).toDouble(), 8.0);
    expect((row['unit_price'] as num).toDouble(), 20.0);
    expect(row['remark'], '夜班转');
    expect(find.text('月/2030年').first, findsOneWidget);
    expect(find.textContaining('2月1日').first, findsOneWidget);
  });

  testWidgets('tapping the todo check toggles done and persists', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final db = await DatabaseHelper.instance.database;
    await db.insert('todo', {
      'id': 'done-toggle',
      'title': '买药',
      'remark': '',
      'date': DateTime(
        today.year,
        today.month,
        today.day,
      ).millisecondsSinceEpoch,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    Future<void> clearTodo() =>
        db.delete('todo', where: 'id = ?', whereArgs: ['done-toggle']);
    addTearDown(clearTodo);

    await tester.pumpWidget(MaterialApp(home: const ScheduleScreen()));
    await tester.pumpAndSettle();
    expectNoFlutterException(tester, '待办列表');

    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    var stored = await db.query(
      'todo',
      where: 'id = ?',
      whereArgs: ['done-toggle'],
    );
    expect(stored.single['done'], 1);

    await tester.tap(find.byIcon(Icons.check_box));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    stored = await db.query(
      'todo',
      where: 'id = ?',
      whereArgs: ['done-toggle'],
    );
    expect(stored.single['done'], 0);
  });

  testWidgets('search focuses and refreshes after deleting a result', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    final db = await DatabaseHelper.instance.database;
    const id = 'search-refresh-record';
    final date = DateTime(2042, 1, 3);
    await db.delete('record', where: 'id = ?', whereArgs: [id]);
    await db.insert('record', {
      'id': id,
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '',
      'date': date.millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: RecordScreen(now: () => date)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus, isNotNull);
    await tester.enterText(find.byType(TextField), '2042-01-03');
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '删除'));
    await tester.pumpAndSettle();

    expect(await db.query('record', where: 'id = ?', whereArgs: [id]), isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2042-01-03',
    );
    expectNoFlutterException(tester, '搜索结果刷新');
  });

  testWidgets('record database failures show user-visible errors', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsController();
    await settings.load();
    final db = await DatabaseHelper.instance.database;
    final date = DateTime(2035, 1, 2);
    await db.insert('record', {
      'id': 'failure-source',
      'workload_type': 0,
      'workload': 8.0,
      'unit_price': 20.0,
      'preset_price': 0.0,
      'remark': '',
      'date': date.millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: RecordScreen(now: () => date)),
      ),
    );
    await tester.pumpAndSettle();
    await db.close();
    DataStore.instance.bump();
    await tester.pumpAndSettle();
    expect(find.text('历史记录加载失败，请重试'), findsOneWidget);

    await tester.ensureVisible(find.text('复制'));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('工时复制失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    await tester.ensureVisible(find.text('删除').first);
    await tester.tap(find.text('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('工时删除失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('记工时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '保存'));
    await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('工时保存失败，请重试'), findsOneWidget);
    expectNoFlutterException(tester, '记录数据库失败');
  });
}

void expectNoFlutterException(WidgetTester tester, String screen) {
  final exception = tester.takeException();
  if (exception != null) {
    final details = exception is FlutterError
        ? exception.toStringDeep()
        : exception.toString();
    fail('Unexpected Flutter exception on $screen:\n$details');
  }
}
