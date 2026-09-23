import 'package:flutter/material.dart';

import 'package:work_helper/theme/app_colors.dart';

/// 共享蓝色顶栏，覆盖项目现有两级头部形态：
///
/// - 二级页形态（原 theme/workload/hourly_rate/work_color/reminder 屏内
///   `_Header`）：[showBack] 默认 true，左侧返回按钮 + [title]，
///   右侧可放单个操作按钮（[actions] 槽）。
/// - 一级页形态（原 record/schedule 屏内联蓝条头部）：`showBack: false`，
///   [title] 传月号等大字（用 [titleStyle] 放大），[subtitle] 传「月/2026年」
///   一类辅助文本，[actions] 传按钮 Row。
///
/// 已知差异（各屏替换时注意，暂不强行统一）：
/// - 原 theme 头右内边距 24、其余 18，此处统一 18；
/// - 原 subtitle 字号 record 20 / schedule 19，此处取 20；
/// - 原 salary 头是 270 高组合面板（首行同本组件结构，下方接统计区），
///   仅首行可被本组件替换；
/// - 原 settings 头是无标题纯蓝占位条（高 96），不适用本组件。
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.titleStyle,
    this.actions,
    this.height = 120,
  });

  /// 主标题文本（二级页为页面名，一级页可月号等短文本）。
  final String title;

  /// 副标题，跟在主标题右侧的半透明白小字；为空则不渲染。
  final String? subtitle;

  /// 是否显示左侧返回按钮（二级页形态为 true）。
  final bool showBack;

  /// 主标题样式覆盖；为空用默认 28 号 w600 白字（二级页形态）。
  final TextStyle? titleStyle;

  /// 右侧操作槽：任意 Widget（IconButton、按钮 Row 等）；为空不占位。
  final Widget? actions;

  /// 蓝条总高度，默认 120（二级页）；一级页原为 128~132 按需传入。
  final double height;

  static const TextStyle _defaultTitleStyle = TextStyle(
    fontSize: 28,
    color: Colors.white,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle _subtitleStyle = TextStyle(
    fontSize: 20,
    color: Color(0xCCFFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 14),
      child: Row(
        children: [
          if (showBack) ...[
            const _BackButton(),
            const SizedBox(width: 24),
          ],
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: titleStyle ?? _defaultTitleStyle),
                  if (subtitle != null) ...[
                    const SizedBox(width: 6),
                    Text(subtitle!, style: _subtitleStyle),
                  ],
                ],
              ),
            ),
          ),
          if (actions != null) ...[const SizedBox(width: 12), actions!],
        ],
      ),
    );
  }
}

/// 二级页左上返回按钮：64×64 深色半透明底块 + 白色左箭头。
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '返回',
      child: Semantics(
        button: true,
        label: '返回',
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.chevron_left,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }
}
