import 'package:lunar/lunar.dart';

class LunarFormatter {
  /// lunar 库内置的公历-农历数据表以 1900-01-31 为起点、末端覆盖到 2100 年，
  /// 越界调用 Lunar.fromDate 会抛断言/范围错误。故按日级边界判定：
  /// [1900-01-31, 2100-12-31] 之外返回占位符。
  static const String _placeholder = '—';

  static bool _outOfRange(DateTime date) =>
      date.isBefore(DateTime(1900, 1, 31)) ||
      date.isAfter(DateTime(2100, 12, 31));

  static String dayLabel(DateTime date) {
    if (_outOfRange(date)) return _placeholder;
    final lunar = Lunar.fromDate(date);
    final jieQi = lunar.getJieQi();
    if (jieQi.isNotEmpty) return jieQi;
    final festivals = lunar.getFestivals();
    if (festivals.isNotEmpty) return festivals.first;
    return lunar.getDayInChinese();
  }

  static String fullLabel(DateTime date) {
    if (_outOfRange(date)) return _placeholder;
    final lunar = Lunar.fromDate(date);
    final parts = <String>[
      '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}',
      ...lunar.getFestivals(),
    ];
    final jieQi = lunar.getJieQi();
    if (jieQi.isNotEmpty) parts.add(jieQi);
    return parts.toSet().join(' ');
  }
}
