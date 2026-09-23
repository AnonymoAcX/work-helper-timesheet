import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_helper/utils/money.dart';
import 'package:work_helper/utils/num_utils.dart';
import 'dart:convert';

class WorkloadQuickOption {
  const WorkloadQuickOption({
    required this.label,
    required this.minutes,
    required this.visible,
  });

  final String label;
  final int minutes;
  final bool visible;

  Map<String, dynamic> toJson() => {
    'label': AppSettingsController.workloadLabelForMinutes(minutes),
    'minutes': minutes,
    'visible': visible,
  };

  WorkloadQuickOption copyWith({String? label, int? minutes, bool? visible}) =>
      WorkloadQuickOption(
        label: label ?? this.label,
        minutes: minutes ?? this.minutes,
        visible: visible ?? this.visible,
      );
}

class WorkTypeOption {
  const WorkTypeOption({required this.id, required this.label});

  final int id;
  final String label;
}

const workTypeOptions = [
  WorkTypeOption(id: 0, label: '白班'),
  WorkTypeOption(id: 1, label: '夜班'),
  WorkTypeOption(id: 2, label: '早班'),
  WorkTypeOption(id: 3, label: '中班'),
  WorkTypeOption(id: 4, label: '晚班'),
  WorkTypeOption(id: 5, label: '加班'),
  WorkTypeOption(id: 6, label: '请假'),
  WorkTypeOption(id: 7, label: '休假'),
];

/// WorkType id 语义单一源：屏层禁止再写字面量 0-5 / 6 / 7 判类型。
const int kTypeIdWageStart = 0;
const int kTypeIdOvertime = 5;
const int kTypeIdLeave = 6;
const int kTypeIdRest = 7;

/// 计薪类型：白班(0)至加班(5)参与工资计算。
bool needsWage(int type) => type >= kTypeIdWageStart && type <= kTypeIdOvertime;

/// 加班类型。
bool isOvertime(int type) => type == kTypeIdOvertime;

/// 非工作类型：请假(6) / 休假(7)。
bool isNonWork(int type) => type == kTypeIdLeave || type == kTypeIdRest;

class AppSettingsController extends ChangeNotifier {
  static const _themeModeKey = 'settings.theme_mode';
  static const _defaultHourlyRateKey = 'settings.default_hourly_rate';
  static const _hourlyRatesKey = 'settings.hourly_rates';
  static const _hourlyRateVisibilityKey = 'settings.hourly_rate_visibility';
  static const _hourlyRatePresetVersionKey =
      'settings.hourly_rate_preset_version';
  static const _workColorsKey = 'settings.work_colors';
  static const _reminderEnabledKey = 'settings.reminder_enabled';
  static const _reminderHourKey = 'settings.reminder_hour';
  static const _reminderMinuteKey = 'settings.reminder_minute';
  static const workloadQuickOptionsKey = 'settings.workload_quick_options';

  static const int _hourlyRatePresetVersion = 2;
  static const List<double> _fallbackHourlyRates = [
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    25,
    30,
    35,
    40,
  ];
  /// 工时类型默认标注色单源（ARGB int，按 workType id 0-7 排序）。
  /// resetWorkTypeColors、脏数据回落与屏层预设色板共同引用本表，禁止副本。
  static const List<int> defaultWorkColors = [
    0xFFFFE4C2,
    0xFFE9E9E9,
    0xFFD9F6C4,
    0xFFCFE1FF,
    0xFFFFCFF5,
    0xFFFFBEBE,
    0xFFC9FBFF,
    0xFFB9F7CF,
  ];
  static const List<WorkloadQuickOption> defaultWorkloadQuickOptions = [
    WorkloadQuickOption(label: '1小时', minutes: 60, visible: true),
    WorkloadQuickOption(label: '2小时', minutes: 120, visible: true),
    WorkloadQuickOption(label: '3小时', minutes: 180, visible: true),
    WorkloadQuickOption(label: '4小时', minutes: 240, visible: true),
    WorkloadQuickOption(label: '8小时', minutes: 480, visible: true),
    WorkloadQuickOption(label: '10小时', minutes: 600, visible: true),
    WorkloadQuickOption(label: '11.5小时', minutes: 690, visible: true),
    WorkloadQuickOption(label: '12小时', minutes: 720, visible: true),
  ];

  static String workloadLabelForMinutes(int minutes) {
    final hours = minutes / 60;
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
    return '$text小时';
  }

  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.light;
  double _defaultHourlyRate = 20;
  List<double> _hourlyRates = List<double>.from(_fallbackHourlyRates);
  /// 与默认时薪表等长的全可见初始化：消 load() 前屏层读 [visibleHourlyRates]
  /// 时的越界（F-8e），load() 后由 [_setHourlyRates] 整体替换。
  List<bool> _hourlyRateVisibility = List<bool>.filled(
    _fallbackHourlyRates.length,
    true,
  );
  List<int> _workColorValues = List<int>.from(defaultWorkColors);
  bool _reminderEnabled = false;
  int _reminderHour = 20;
  int _reminderMinute = 30;
  List<WorkloadQuickOption> _workloadQuickOptions =
      List<WorkloadQuickOption>.from(defaultWorkloadQuickOptions);
  List<WorkloadQuickOption>? _workloadQuickOptionsView;
  List<double>? _hourlyRatesView;
  List<double>? _visibleHourlyRatesView;
  List<Color>? _workColorsView;
  bool _hourlyRatesPending = false;

  ThemeMode get themeMode => _themeMode;
  double get defaultHourlyRate => _defaultHourlyRate;
  /// 稳定实例（同 [workloadQuickOptions] 模式，F-8e/A1 先例）：时薪与可见性
  /// 写点一律经 [_setHourlyRates] 失效缓存，Selector 切片相等才真实生效。
  List<double> get hourlyRates =>
      _hourlyRatesView ??= List.unmodifiable(_hourlyRates);
  List<double> get visibleHourlyRates =>
      _visibleHourlyRatesView ??= List.unmodifiable([
        for (var i = 0; i < _hourlyRates.length; i++)
          if (_hourlyRateVisibility[i]) _hourlyRates[i],
      ]);
  List<Color> get workColors => _workColorsView ??=
      _workColorValues.map(Color.new).toList(growable: false);
  bool get reminderEnabled => _reminderEnabled;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
  /// 稳定实例：同一份数据多次读取返回同一对象，Selector 切片相等才真实生效；
  /// 所有写点必须走 [_setWorkloadQuickOptions] 以失效缓存。
  List<WorkloadQuickOption> get workloadQuickOptions =>
      _workloadQuickOptionsView ??= List.unmodifiable(_workloadQuickOptions);
  List<WorkloadQuickOption> get visibleWorkloadQuickOptions =>
      List.unmodifiable(_workloadQuickOptions.where((item) => item.visible));

  void _setWorkloadQuickOptions(List<WorkloadQuickOption> next) {
    _workloadQuickOptions = next;
    _workloadQuickOptionsView = null;
  }

  void _setHourlyRates(List<double> rates, List<bool> visibility) {
    _hourlyRates = rates;
    _hourlyRateVisibility = visibility;
    _hourlyRatesView = null;
    _visibleHourlyRatesView = null;
  }

  void _setWorkColorValues(List<int> next) {
    _workColorValues = next;
    _workColorsView = null;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = _decodeThemeMode(_prefs.getString(_themeModeKey));
    _defaultHourlyRate =
        _validRate(_prefs.getDouble(_defaultHourlyRateKey)) ?? 20;
    final presetVersion = _prefs.getInt(_hourlyRatePresetVersionKey) ?? 1;
    var rates = _decodeRates(_prefs.getStringList(_hourlyRatesKey));
    var visibility = _decodeRateVisibility(
      _prefs.getStringList(_hourlyRateVisibilityKey),
      rates.length,
    );
    if (presetVersion < _hourlyRatePresetVersion) {
      final prevRates = rates;
      final prevVis = visibility;
      rates = _normalizeRates([
        ..._fallbackHourlyRates,
        ...rates,
      ]);
      visibility = _visibilityForRates(prevRates, prevVis, rates);
      await _prefs.setInt(
        _hourlyRatePresetVersionKey,
        _hourlyRatePresetVersion,
      );
      await _saveHourlyRates(
        defaultRate: _defaultHourlyRate,
        rates: rates,
        visibility: visibility,
      );
    }
    if (!rates.contains(_defaultHourlyRate)) {
      final prevRates = rates;
      final prevVis = visibility;
      rates = _normalizeRates([...rates, _defaultHourlyRate]);
      visibility = _visibilityForRates(
        prevRates,
        prevVis,
        rates,
        clean: _defaultHourlyRate,
      );
      await _saveHourlyRates(
        defaultRate: _defaultHourlyRate,
        rates: rates,
        visibility: visibility,
      );
    }
    _setHourlyRates(rates, visibility);
    _setWorkColorValues(_decodeColors(_prefs.getStringList(_workColorsKey)));
    _reminderEnabled = _prefs.getBool(_reminderEnabledKey) ?? false;
    _reminderHour = (_prefs.getInt(_reminderHourKey) ?? 20).clamp(0, 23);
    _reminderMinute = (_prefs.getInt(_reminderMinuteKey) ?? 30).clamp(0, 59);
    final storedOptions = _prefs.getString(workloadQuickOptionsKey);
    if (storedOptions == null) {
      final next = _defaultWorkloadQuickOptions();
      _setWorkloadQuickOptions(next);
      await _saveWorkloadQuickOptions(next);
    } else {
      try {
        final next = _decodeWorkloadQuickOptions(storedOptions);
        _setWorkloadQuickOptions(next);
        await _saveWorkloadQuickOptions(next);
      } on FormatException {
        final next = _defaultWorkloadQuickOptions();
        _setWorkloadQuickOptions(next);
        await _saveWorkloadQuickOptions(next);
      }
    }
  }

  Color colorForWorkType(int id) {
    final index = id.clamp(0, _workColorValues.length - 1);
    return Color(_workColorValues[index]);
  }

  String labelForWorkType(int id) {
    final match = workTypeOptions.where((item) => item.id == id);
    return match.isEmpty ? workTypeOptions.first.label : match.first.label;
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeModeKey, mode.name);
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setDefaultHourlyRate(double rate) async {
    await _runHourlyRatesAction(() async {
      final clean = _validRate(rate);
      if (clean == null) {
        throw const FormatException('时薪需大于0且不超过10000');
      }
      final prevRates = _hourlyRates;
      final prevVis = _hourlyRateVisibility;
      final nextRates = _normalizeRates([...prevRates, clean]);
      final nextVis = _visibilityForRates(
        prevRates,
        prevVis,
        nextRates,
        clean: clean,
      );
      await _saveHourlyRates(
        defaultRate: clean,
        rates: nextRates,
        visibility: nextVis,
      );
      _defaultHourlyRate = clean;
      _setHourlyRates(nextRates, nextVis);
      notifyListeners();
    });
  }

  Future<void> addHourlyRate(double rate) async {
    await _runHourlyRatesAction(() async {
      final clean = _validRate(rate);
      if (clean == null) {
        throw const FormatException('时薪需大于0且不超过10000');
      }
      final prevRates = _hourlyRates;
      final prevVis = _hourlyRateVisibility;
      final nextRates = _normalizeRates([...prevRates, clean]);
      final nextVis = _visibilityForRates(
        prevRates,
        prevVis,
        nextRates,
        clean: clean,
      );
      final nextDefault = _defaultHourlyRate <= 0 ? clean : _defaultHourlyRate;
      await _saveHourlyRates(
        defaultRate: nextDefault,
        rates: nextRates,
        visibility: nextVis,
      );
      _defaultHourlyRate = nextDefault;
      _setHourlyRates(nextRates, nextVis);
      notifyListeners();
    });
  }

  Future<void> removeHourlyRate(double rate) async {
    await _runHourlyRatesAction(() async {
      if (_hourlyRates.length <= 1) return;
      final prevRates = _hourlyRates;
      final prevVis = _hourlyRateVisibility;
      final nextRates = prevRates
          .where((item) => item != rate)
          .toList(growable: false);
      final nextVis = _visibilityForRates(prevRates, prevVis, nextRates);
      final nextDefault = nextRates.contains(_defaultHourlyRate)
          ? _defaultHourlyRate
          : nextRates.first;
      await _saveHourlyRates(
        defaultRate: nextDefault,
        rates: nextRates,
        visibility: nextVis,
      );
      _defaultHourlyRate = nextDefault;
      _setHourlyRates(nextRates, nextVis);
      notifyListeners();
    });
  }

  Future<void> updateHourlyRateVisibility(double rate, bool visible) async {
    await _runHourlyRatesAction(() async {
      final index = _hourlyRates.indexOf(rate);
      if (index < 0) throw StateError('时薪不存在');
      _hourlyRateVisibility[index] = visible;
      // 就地变更不经过 [_setHourlyRates]，手动失效可见视图缓存。
      _visibleHourlyRatesView = null;
      await _saveHourlyRateVisibility(_hourlyRateVisibility);
      notifyListeners();
    });
  }

  Future<void> updateWorkTypeColor(int workTypeId, Color color) async {
    if (workTypeId < 0 || workTypeId >= _workColorValues.length) return;
    final next = [..._workColorValues]..[workTypeId] = color.toARGB32();
    await _prefs.setStringList(
      _workColorsKey,
      next.map((value) => value.toString()).toList(),
    );
    _setWorkColorValues(next);
    notifyListeners();
  }

  Future<void> resetWorkTypeColors() async {
    final next = List<int>.from(defaultWorkColors);
    await _prefs.setStringList(
      _workColorsKey,
      next.map((value) => value.toString()).toList(),
    );
    _setWorkColorValues(next);
    notifyListeners();
  }

  Future<void> updateReminderEnabled(bool enabled) async {
    await _prefs.setBool(_reminderEnabledKey, enabled);
    _reminderEnabled = enabled;
    notifyListeners();
  }

  Future<void> updateReminderTime({
    required int hour,
    required int minute,
  }) async {
    final nextHour = hour.clamp(0, 23);
    final nextMinute = minute.clamp(0, 59);
    await _prefs.setInt(_reminderHourKey, nextHour);
    try {
      await _prefs.setInt(_reminderMinuteKey, nextMinute);
    } catch (_) {
      await _prefs.setInt(_reminderHourKey, _reminderHour);
      rethrow;
    }
    _reminderHour = nextHour;
    _reminderMinute = nextMinute;
    notifyListeners();
  }

  Future<void> addWorkloadQuickOption(WorkloadQuickOption option) async {
    final clean = _canonicalWorkloadOption(option);
    _validateWorkloadOption(clean, _workloadQuickOptions);
    final next = [..._workloadQuickOptions, clean];
    await _saveWorkloadQuickOptions(next);
    _setWorkloadQuickOptions(next);
    notifyListeners();
  }

  Future<void> updateWorkloadQuickOption(
    int index,
    WorkloadQuickOption option,
  ) async {
    if (index < 0 || index >= _workloadQuickOptions.length) {
      throw const FormatException('快捷项位置无效');
    }
    final clean = _canonicalWorkloadOption(option);
    final next = [..._workloadQuickOptions]..removeAt(index);
    _validateWorkloadOption(clean, next);
    next.insert(index, clean);
    await _saveWorkloadQuickOptions(next);
    _setWorkloadQuickOptions(next);
    notifyListeners();
  }

  Future<void> removeWorkloadQuickOption(int index) async {
    if (index < 0 || index >= _workloadQuickOptions.length) {
      throw const FormatException('快捷项位置无效');
    }
    final next = [..._workloadQuickOptions]..removeAt(index);
    await _saveWorkloadQuickOptions(next);
    _setWorkloadQuickOptions(next);
    notifyListeners();
  }

  Future<void> reorderWorkloadQuickOption(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _workloadQuickOptions.length ||
        newIndex >= _workloadQuickOptions.length) {
      throw const FormatException('快捷项位置无效');
    }
    final next = [..._workloadQuickOptions];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    await _saveWorkloadQuickOptions(next);
    _setWorkloadQuickOptions(next);
    notifyListeners();
  }

  Future<void> resetWorkloadQuickOptions() async {
    final next = List<WorkloadQuickOption>.from(defaultWorkloadQuickOptions);
    await _saveWorkloadQuickOptions(next);
    _setWorkloadQuickOptions(next);
    notifyListeners();
  }

  Map<String, dynamic> exportSettings() => {
    'themeMode': _themeMode.name,
    'defaultHourlyRate': _defaultHourlyRate,
    'hourlyRates': [..._hourlyRates],
    'hourlyRateVisibility': _hourlyRateVisibility
        .map((visible) => visible ? '1' : '0')
        .toList(growable: false),
    'workColors': [..._workColorValues],
    'reminderEnabled': _reminderEnabled,
    'reminderHour': _reminderHour,
    'reminderMinute': _reminderMinute,
    'workloadQuickOptions': _workloadQuickOptions
        .map((e) => _canonicalWorkloadOption(e).toJson())
        .toList(),
  };

  Map<String, dynamic> validateBackupSettings(Object? raw) {
    if (raw is! Map) throw const FormatException('备份缺少应用设置');
    final map = Map<String, dynamic>.from(raw);
    final options = _decodeWorkloadQuickOptions(
      jsonEncode(map['workloadQuickOptions']),
    );
    final rates = (map['hourlyRates'] as List?)
        ?.map((e) => _validRate(_asDouble(e)))
        .whereType<double>()
        .toList();
    final defaultRate = _validRate(_asDouble(map['defaultHourlyRate']));
    if (rates == null ||
        rates.isEmpty ||
        defaultRate == null ||
        !rates.contains(defaultRate)) {
      throw const FormatException('备份中的时薪数据无效');
    }
    // hourlyRateVisibility 宽松校验：非 '0'/'1' 列表或与 rates 长度不符 → 降级为全可见缺省。
    final rawVisibility = map['hourlyRateVisibility'];
    final hourlyRateVisibility =
        rawVisibility is List &&
            rawVisibility.length == rates.length &&
            rawVisibility.every((e) => e == '1' || e == '0')
        ? rawVisibility.map((e) => '$e').toList(growable: false)
        : List<String>.filled(rates.length, '1', growable: false);
    final colors = (map['workColors'] as List?)?.map((e) => _asInt(e)).toList();
    final hour = _asInt(map['reminderHour']);
    final minute = _asInt(map['reminderMinute']);
    if (colors == null ||
        colors.length != workTypeOptions.length ||
        hour > 23 ||
        minute > 59 ||
        hour < 0 ||
        minute < 0) {
      throw const FormatException('备份中的提醒或颜色设置无效');
    }
    final theme = map['themeMode'];
    if (theme is! String || !['light', 'dark', 'system'].contains(theme)) {
      throw const FormatException('备份中的主题设置无效');
    }
    return {
      ...map,
      'workloadQuickOptions': options.map((e) => e.toJson()).toList(),
      'hourlyRates': rates,
      'hourlyRateVisibility': hourlyRateVisibility,
    };
  }

  Future<void> importSettings(Object? raw) async {
    final map = validateBackupSettings(raw);
    final themeMode = _decodeThemeMode(map['themeMode'] as String);
    final defaultHourlyRate = _validRate(_asDouble(map['defaultHourlyRate']))!;
    final hourlyRates = (map['hourlyRates'] as List)
        .map((e) => _validRate(_asDouble(e))!)
        .toList();
    final rateVisibility = _decodeRateVisibility(
      map['hourlyRateVisibility'],
      hourlyRates.length,
    );
    final workColors = (map['workColors'] as List).map(_asInt).toList();
    final reminderEnabled = map['reminderEnabled'] == true;
    final reminderHour = _asInt(map['reminderHour']);
    final reminderMinute = _asInt(map['reminderMinute']);
    final workloadQuickOptions = _decodeWorkloadQuickOptions(
      jsonEncode(map['workloadQuickOptions']),
    );
    // 写序与 updateWorkTypeColor 等合规组一致：算 next → 写盘 → 改内存 → notify。
    await _prefs.setString(_themeModeKey, themeMode.name);
    await _saveHourlyRates(
      defaultRate: defaultHourlyRate,
      rates: hourlyRates,
      visibility: rateVisibility,
    );
    await _prefs.setStringList(
      _workColorsKey,
      workColors.map((e) => '$e').toList(),
    );
    await _prefs.setBool(_reminderEnabledKey, reminderEnabled);
    await _prefs.setInt(_reminderHourKey, reminderHour);
    await _prefs.setInt(_reminderMinuteKey, reminderMinute);
    await _saveWorkloadQuickOptions(workloadQuickOptions);
    _themeMode = themeMode;
    _defaultHourlyRate = defaultHourlyRate;
    _setHourlyRates(hourlyRates, rateVisibility);
    _setWorkColorValues(workColors);
    _reminderEnabled = reminderEnabled;
    _reminderHour = reminderHour;
    _reminderMinute = reminderMinute;
    _setWorkloadQuickOptions(workloadQuickOptions);
    notifyListeners();
  }

  /// 显式参数化（不读字段）：各 action 按「算 next → 写盘 → 改内存 → notify」
  /// 顺序执行，写盘失败时内存保持旧值。
  Future<void> _saveHourlyRates({
    required double defaultRate,
    required List<double> rates,
    required List<bool> visibility,
  }) async {
    await _prefs.setDouble(_defaultHourlyRateKey, defaultRate);
    await _prefs.setStringList(
      _hourlyRatesKey,
      rates.map((rate) => rate.toStringAsFixed(2)).toList(),
    );
    await _saveHourlyRateVisibility(visibility);
  }

  Future<void> _runHourlyRatesAction(Future<void> Function() action) async {
    if (_hourlyRatesPending) throw StateError('时薪设置正在更新');
    _hourlyRatesPending = true;
    try {
      await action();
    } finally {
      _hourlyRatesPending = false;
    }
  }

  /// 参数化（不读字段）：与 [_saveHourlyRates] 同口径，供写盘先于改内存的
  /// 写序使用；就地变更路径传当前字段引用即可。
  Future<void> _saveHourlyRateVisibility(List<bool> visibility) =>
      _prefs.setStringList(
        _hourlyRateVisibilityKey,
        visibility.map((visible) => visible ? '1' : '0').toList(),
      );

  /// 参数化：入参为「算 next → 写盘 → 改内存 → notify」写序中的 next 快照。
  Future<void> _saveWorkloadQuickOptions(
    List<WorkloadQuickOption> options,
  ) async {
    await _prefs.setString(
      workloadQuickOptionsKey,
      jsonEncode(options.map((e) => e.toJson()).toList()),
    );
  }

  ThemeMode _decodeThemeMode(String? value) {
    return switch (value) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  List<double> _decodeRates(List<String>? values) {
    if (values == null || values.isEmpty) {
      return List<double>.from(_fallbackHourlyRates);
    }
    return _normalizeRates(
      values.map((item) => double.tryParse(item)).whereType<double>(),
    );
  }

  /// 还原时薪可见性：接受 SharedPreferences 或备份中的字符串列表原始值。
  /// 缺省、长度与时薪表不符或含非 '0'/'1' 项时降级为全可见。
  List<bool> _decodeRateVisibility(Object? raw, int rateCount) {
    if (raw is! List ||
        raw.length != rateCount ||
        !raw.every((value) => value == '1' || value == '0')) {
      return List.filled(rateCount, true);
    }
    return raw.map((value) => value == '1').toList(growable: false);
  }

  /// 旧→新可见性映射只读快照参数（F-1 根修）：调用方必须在替换
  /// [_hourlyRates]/[_hourlyRateVisibility] 字段**前**捕获 prevRates/prevVis
  /// 传入；旧实现读已被替换的字段按下标与旧可见性配对，加/删时薪后错位
  /// （rates[10,20,30]+vis[T,F,F] 加 25 → 30 泄露、25 误隐）。
  List<bool> _visibilityForRates(
    List<double> prevRates,
    List<bool> prevVis,
    Iterable<double> rates, {
    double? clean,
  }) {
    final old = <String, bool>{};
    for (var i = 0; i < prevRates.length; i++) {
      old[prevRates[i].toStringAsFixed(2)] =
          i < prevVis.length ? prevVis[i] : true;
    }
    return rates
        .map(
          (rate) =>
              old[rate.toStringAsFixed(2)] ?? (clean == null || rate == clean),
        )
        .toList(growable: false);
  }

  List<int> _decodeColors(List<String>? values) {
    final decoded = values
        ?.map((item) => int.tryParse(item))
        .whereType<int>()
        .toList();
    if (decoded == null || decoded.length != workTypeOptions.length) {
      return List<int>.from(defaultWorkColors);
    }
    return decoded;
  }

  double? _validRate(double? rate) {
    // 正向判断：NaN 对 <=0 与 >10000 均为 false，必须走 !(rate > 0 && ...) 才能排除。
    if (rate == null || !(rate > 0 && rate <= 10000)) return null;
    // 舍入归一与 Money 分聚合口径合一（F-2）：26.555 → 2656 分 → 26.56；
    // 旧 toStringAsFixed(2) 往返得 26.55（2655 分），与分单位口径分叉。
    return Money.centsToYuan(Money.yuanToCents(rate));
  }

  List<double> _normalizeRates(Iterable<double> values) {
    final cleaned = values.map(_validRate).whereType<double>().toSet().toList()
      ..sort();
    return cleaned.isEmpty ? List<double>.from(_fallbackHourlyRates) : cleaned;
  }

  List<WorkloadQuickOption> _decodeWorkloadQuickOptions(String? value) {
    if (value == null) throw const FormatException('快捷项配置缺失');
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('快捷项配置格式无效');
    final result = <WorkloadQuickOption>[];
    for (final item in decoded) {
      if (item is! Map ||
          item.keys.length != 3 ||
          item.keys.toSet().difference({
            'label',
            'minutes',
            'visible',
          }).isNotEmpty ||
          item['minutes'] is! int ||
          item['visible'] is! bool) {
        throw const FormatException('快捷项配置格式无效');
      }
      final option = WorkloadQuickOption(
        label: workloadLabelForMinutes(item['minutes'] as int),
        minutes: item['minutes'] as int,
        visible: item['visible'] as bool,
      );
      _validateWorkloadOption(option, result);
      result.add(option);
    }
    return result;
  }

  List<WorkloadQuickOption> _defaultWorkloadQuickOptions() =>
      defaultWorkloadQuickOptions
          .map((option) => option.copyWith())
          .toList(growable: false);

  WorkloadQuickOption _canonicalWorkloadOption(WorkloadQuickOption option) =>
      option.copyWith(label: workloadLabelForMinutes(option.minutes));

  void _validateWorkloadOption(
    WorkloadQuickOption option,
    List<WorkloadQuickOption> existing,
  ) {
    if (option.minutes <= 0 || option.minutes > 24 * 60) {
      throw const FormatException('工时必须大于0且不超过24小时');
    }
    if (existing.any((item) => item.minutes == option.minutes)) {
      throw const FormatException('工时不能重复');
    }
  }

  /// 解析口径委托 NumUtils，但保留 -1/NaN 哨兵：这是与下游的守卫契约——
  /// _asInt 失败 -1 被 validateBackupSettings 的 hour/minute <0 拒绝，
  /// _asDouble 失败 NaN 被 _validRate 排除。勿改回 NumUtils 默认 0/0.0，
  /// 否则畸形备份值会被当成合法的 0 点 / 0 元静默放行。
  double _asDouble(Object? value) =>
      NumUtils.asDouble(value, fallback: double.nan);
  int _asInt(Object? value) => NumUtils.asInt(value, fallback: -1);
}
