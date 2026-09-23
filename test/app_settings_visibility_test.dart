import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/utils/money.dart';

/// 可见性对齐、舍入口径、
/// 未 load 越界与稳定缓存视图，经 controller 公开面构造。
void main() {
  test('load 前可见时薪可安全读取（不越界）', () {
    // 钉桩：旧实现 visibility=[] 时逐下标读会 RangeError。
    final settings = AppSettingsController();
    expect(settings.visibleHourlyRates, hasLength(15));
    expect(settings.visibleHourlyRates, settings.hourlyRates);
  });

  test('新增时薪后隐藏项不错位（30 保持隐藏、25 默认可见）', () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rate_preset_version': 2,
      'settings.hourly_rates': ['10.00', '20.00', '30.00'],
      'settings.hourly_rate_visibility': ['1', '0', '0'],
    });
    final settings = AppSettingsController();
    await settings.load();
    expect(settings.hourlyRates, [10.0, 20.0, 30.0]);
    expect(settings.visibleHourlyRates, [10.0]);

    await settings.addHourlyRate(25);
    // 旧按下标配对实现会产出 [T,F,F,T]：30 泄露、25 误隐。
    expect(settings.hourlyRates, [10.0, 20.0, 25.0, 30.0]);
    expect(settings.visibleHourlyRates, [10.0, 25.0]);

    final reloaded = AppSettingsController();
    await reloaded.load();
    expect(reloaded.visibleHourlyRates, [10.0, 25.0]);
  });

  test('删除时薪后隐藏项不错位（30 前移仍隐藏）', () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rate_preset_version': 2,
      'settings.hourly_rates': ['10.00', '20.00', '30.00'],
      'settings.hourly_rate_visibility': ['1', '1', '0'],
    });
    final settings = AppSettingsController();
    await settings.load();

    await settings.removeHourlyRate(20);
    // 30 从下标 2 前移到 1：可见性必须跟随值而非位置。
    expect(settings.hourlyRates, [10.0, 30.0]);
    expect(settings.visibleHourlyRates, [10.0]);
    expect(settings.defaultHourlyRate, 10.0);

    final reloaded = AppSettingsController();
    await reloaded.load();
    expect(reloaded.visibleHourlyRates, [10.0]);
  });

  test('26.555 经保存归一为 Money 分口径 2656（非 toStringAsFixed 的 2655）',
      () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rate_preset_version': 2,
    });
    final settings = AppSettingsController();
    await settings.load();

    await settings.addHourlyRate(26.555);
    final stored = settings.hourlyRates
        .singleWhere((rate) => rate > 26 && rate < 27);
    expect(Money.yuanToCents(stored), 2656);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('settings.hourly_rates'), contains('26.56'));

    final reloaded = AppSettingsController();
    await reloaded.load();
    final reread = reloaded.hourlyRates
        .singleWhere((rate) => rate > 26 && rate < 27);
    expect(Money.yuanToCents(reread), 2656);
  });

  test('时薪与颜色列表 getter 返回稳定实例，写点换新', () async {
    SharedPreferences.setMockInitialValues({
      'settings.hourly_rate_preset_version': 2,
    });
    final settings = AppSettingsController();
    await settings.load();

    final rates = settings.hourlyRates;
    final visible = settings.visibleHourlyRates;
    final colors = settings.workColors;
    expect(identical(rates, settings.hourlyRates), isTrue);
    expect(identical(visible, settings.visibleHourlyRates), isTrue);
    expect(identical(colors, settings.workColors), isTrue);

    await settings.addHourlyRate(27);
    expect(identical(rates, settings.hourlyRates), isFalse);
    expect(identical(visible, settings.visibleHourlyRates), isFalse);
    final ratesAfterAdd = settings.hourlyRates;
    expect(
      identical(ratesAfterAdd, settings.hourlyRates),
      isTrue,
      reason: '数据未变时实例必须稳定',
    );

    await settings.updateHourlyRateVisibility(10, false);
    expect(identical(visible, settings.visibleHourlyRates), isFalse);
    expect(
      identical(ratesAfterAdd, settings.hourlyRates),
      isTrue,
      reason: '仅可见性变化不得波及全量时薪视图',
    );

    await settings.updateWorkTypeColor(0, const Color(0xFF010203));
    expect(identical(colors, settings.workColors), isFalse);
    expect(
      identical(settings.workColors, settings.workColors),
      isTrue,
      reason: '颜色写点后新视图同样须稳定',
    );
  });
}
