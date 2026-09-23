/// 金额与工时的精确换算工具。
///
/// 精度口径：double 只允许出现在 UI 输入/展示边界；存储、聚合与展示换算
/// 一律走整数——金额以「分」为源、工时以「分钟」为源，避免浮点累计误差。
/// 禁止任何「先 toStringAsFixed(n) 格式化再 parse 回数值」的往返写法。
library;

/// 金额工具：以「分」(int) 为唯一权威单位。
class Money {
  /// 元 → 分。四舍五入到整分；输入须为有限值（NaN/Infinity 会抛
  /// UnsupportedError，属刻意 fast-fail，上游应先经 NumUtils 清洗）。
  static int yuanToCents(double yuan) => (yuan * 100).round();

  /// 分 → 元。仅供输入控件回填等展示边界使用，不得再参与聚合。
  static double centsToYuan(int cents) => cents / 100;

  /// 分 → 两位小数「元」文本，不带货币符号。
  /// 纯整数运算无精度损失：12345 → "123.45"、5 → "0.05"、-50 → "-0.50"。
  static String formatYuan(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '$sign${abs ~/ 100}.$frac';
  }
}

/// 工时工具：以「分钟」(int) 为唯一权威单位。
class WorkMinutes {
  /// 小时 → 分钟。四舍五入到整分钟；NaN/Infinity 输入抛错（同 [Money.yuanToCents]）。
  static int hoursToMinutes(double hours) => (hours * 60).round();

  /// 分钟 → 小时。仅供输入控件回填等展示边界使用，不得再参与聚合。
  static double minutesToHours(int minutes) => minutes / 60;

  /// 分钟 → 「X小时Y分」文本。
  ///
  /// 选「小时+分钟」拆分口径而非十进制小时：如 425 分钟 = 7.0833… 小时是
  /// 无限循环小数，十进制口径必然截断丢精度；本口径任意整数分钟无损还原。
  /// 60 → "1小时"、90 → "1小时30分"、425 → "7小时5分"、45 → "45分"。
  static String hoursTextFromMinutes(int minutes) {
    if (minutes == 0) return '0分';
    final sign = minutes < 0 ? '-' : '';
    final m = minutes.abs();
    final h = m ~/ 60;
    final rest = m % 60;
    if (h == 0) return '$sign$rest分';
    if (rest == 0) return '$sign$h小时';
    return '$sign$h小时$rest分';
  }
}
