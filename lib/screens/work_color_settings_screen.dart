import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/theme/app_colors.dart';

// 前 8 色直接引 controller 单一源 defaultWorkColors
// （重置与脏数据回落共用同一表），本屏不再维护副本；后 4 色为屏层扩展色板。
final List<Color> _colorPresets = [
  for (final argb in AppSettingsController.defaultWorkColors) Color(argb),
  const Color(0xFFFFD166),
  const Color(0xFF8EC5FF),
  const Color(0xFFB8F2E6),
  const Color(0xFFE4C1F9),
];

const _colorLabels = [
  '杏色',
  '浅灰色',
  '浅绿色',
  '浅蓝色',
  '粉紫色',
  '珊瑚红',
  '青色',
  '薄荷绿',
  '金黄色',
  '天蓝色',
  '青绿色',
  '淡紫色',
];

class WorkColorSettingsScreen extends StatefulWidget {
  const WorkColorSettingsScreen({super.key});

  @override
  State<WorkColorSettingsScreen> createState() =>
      _WorkColorSettingsScreenState();
}

class _WorkColorSettingsScreenState extends State<WorkColorSettingsScreen> {
  bool _pending = false;

  Future<void> _reset() async {
    // 重置是批量覆盖全部工时类型颜色，先二次确认再执行。
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('恢复默认颜色？'),
            content: const Text('将把所有工时类型的标注颜色恢复为默认值。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _runPending(
      () => context.read<AppSettingsController>().resetWorkTypeColors(),
    );
  }

  Future<void> _chooseColor(BuildContext context, int workTypeId) async {
    if (_pending) return;
    final selectedColor = context
        .read<AppSettingsController>()
        .colorForWorkType(workTypeId);
    setState(() => _pending = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var saving = false;
          String? error;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('选择标注颜色'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (
                          var index = 0;
                          index < _colorPresets.length;
                          index++
                        )
                          Builder(
                            builder: (context) {
                              final color = _colorPresets[index];
                              final selected = color == selectedColor;
                              final label = _colorLabels[index];
                              return Semantics(
                                button: true,
                                selected: selected,
                                label: '$label${selected ? '，已选择' : ''}',
                                child: Tooltip(
                                  message: label,
                                  child: InkWell(
                                    onTap: saving
                                        ? null
                                        : () async {
                                            setDialogState(() => saving = true);
                                            try {
                                              await context
                                                  .read<AppSettingsController>()
                                                  .updateWorkTypeColor(
                                                    workTypeId,
                                                    color,
                                                  );
                                              if (dialogContext.mounted) {
                                                Navigator.pop(dialogContext);
                                              }
                                            } catch (exception, stackTrace) {
                                              FlutterError.reportError(
                                                FlutterErrorDetails(
                                                  exception: exception,
                                                  stack: stackTrace,
                                                  context: ErrorDescription(
                                                    '工时颜色保存失败',
                                                  ),
                                                ),
                                              );
                                              if (dialogContext.mounted) {
                                                setDialogState(() {
                                                  saving = false;
                                                  error = '保存失败，请重试';
                                                });
                                              }
                                            }
                                          },
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: .16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (selected)
                                          const Icon(
                                            Icons.check,
                                            color: Colors.black54,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _runPending(Future<void> Function() action) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await action();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('工时颜色操作失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // R4-1：watch→select，仅订阅 workColors 切片（稳定缓存实例，identical
    // 成立；写点统一经 _setWorkColorValues 失效）。颜色未变的其他 notify
    // 不再重建本屏；本语句只做订阅，取色单一源仍是 colorForWorkType。
    context.select<AppSettingsController, List<Color>>((s) => s.workColors);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(onReset: _pending ? null : _reset),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                itemCount: workTypeOptions.length,
                itemBuilder: (context, index) {
                  final type = workTypeOptions[index];
                  // 重建由上方 select 触发；read 现取最新值，复用
                  // colorForWorkType 的 clamp 单一源，不复制取色逻辑。
                  final color = context
                      .read<AppSettingsController>()
                      .colorForWorkType(type.id);
                  return Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    child: ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: .12),
                          ),
                        ),
                      ),
                      title: Text(
                        type.label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('用于日历标记和历史记录'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pending
                          ? null
                          : () => _chooseColor(context, type.id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onReset});

  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      color: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 14),
      child: Row(
        children: [
          Tooltip(
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
          ),
          const SizedBox(width: 24),
          const Text(
            '工时颜色',
            style: TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onReset,
            child: const Text(
              '重置',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
