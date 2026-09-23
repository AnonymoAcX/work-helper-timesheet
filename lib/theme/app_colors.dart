import 'package:flutter/material.dart';

/// 全局颜色常量统一源。
///
/// [blue] 即原项目散落 5+ 处的 `_blue = Color(0xFF4C86F7)`
/// （record/schedule/salary/settings/theme/hourly_rate/work_color/
/// workload_quick_options/reminder 各屏顶部常量与 main.dart 的 seedColor），
/// 后续统一替换时以本类为唯一定义点。
class AppColors {
  /// 主品牌蓝，各屏顶栏、强调色。
  static const Color blue = Color(0xFF4C86F7);

  /// 浅蓝，原 record_screen 的 `_lightBlue`，用于选中/悬浮等次强调。
  static const Color lightBlue = Color(0xFF78A4F7);
}
