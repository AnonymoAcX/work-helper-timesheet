/// 数值安全解析工具。
///
/// 统一语义（原项目 4 处 `_asDouble`/`_asInt` 失败语义不一：0.0 / NaN / -1）：
/// - 解析失败一律返回 `fallback`（默认 0 / 0.0），**绝不返回 NaN**；
/// - 输入为 `num` 直接取值；`bool` 按 true=1 / false=0 解析；
///   其余类型转字符串后 trim 再 tryParse，字符串小数可按截断取整；
/// - NaN / Infinity 等病态值视同解析失败，走 fallback。
class NumUtils {
  /// 把任意值解析为 double，失败返回 [fallback]（默认 0.0，不产生 NaN）。
  static double asDouble(Object? v, {double fallback = 0.0}) {
    double? parsed;
    if (v is num) {
      parsed = v.toDouble();
    } else if (v is bool) {
      parsed = v ? 1.0 : 0.0;
    } else if (v != null) {
      parsed = double.tryParse(v.toString().trim());
    }
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return fallback;
    }
    return parsed;
  }

  /// 把任意值解析为 int，失败返回 [fallback]（默认 0）。
  /// 小数（如 `1.9`、`"2.5"`）向零截断，与 `num.toInt()` 行为一致。
  static int asInt(Object? v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) {
      final d = v.toDouble();
      return (d.isNaN || d.isInfinite) ? fallback : d.toInt();
    }
    if (v is bool) return v ? 1 : 0;
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return fallback;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d == null || d.isNaN || d.isInfinite) return fallback;
    return d.toInt();
  }
}
