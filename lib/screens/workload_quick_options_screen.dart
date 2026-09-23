import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/widgets/app_header.dart';

class WorkloadQuickOptionsScreen extends StatefulWidget {
  const WorkloadQuickOptionsScreen({super.key});

  @override
  State<WorkloadQuickOptionsScreen> createState() =>
      _WorkloadQuickOptionsScreenState();
}

class _WorkloadQuickOptionsScreenState
    extends State<WorkloadQuickOptionsScreen> {
  bool _pending = false;

  String _hoursText(int minutes) =>
      AppSettingsController.workloadLabelForMinutes(minutes);

  String _errorMessage(Object error, StackTrace stackTrace) {
    final message = switch (error) {
      FormatException exception => exception.message,
      StateError exception => exception.message,
      DatabaseException() => '操作失败，请重试',
      _ => '操作失败，请重试',
    };
    // R4-3：对齐 hourly_rate_settings_screen._runAction 双轨模式——
    // DatabaseException 显式按类型上报并携带真实栈，不再依赖文案字符串
    // 匹配挂钩；未知错误仍走原兜底上报，不丢栈。switch 文案映射形态不变。
    if (error is DatabaseException) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('工时选项操作失败'),
        ),
      );
    } else if (message == '操作失败，请重试') {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('工时设置操作失败'),
        ),
      );
    }
    return message;
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit(BuildContext context, {int? index}) async {
    if (_pending) return;
    final controller = context.read<AppSettingsController>();
    final current = index == null
        ? null
        : controller.workloadQuickOptions[index];
    await showDialog<void>(
      context: context,
      builder: (_) => _WorkloadOptionDialog(
        controller: controller,
        index: index,
        current: current,
        errorMessage: _errorMessage,
      ),
    );
  }

  Future<void> _runPending(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await action();
    } catch (error, stackTrace) {
      final message = _errorMessage(error, stackTrace);
      if (context.mounted) _showError(context, message);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final settings = context.read<AppSettingsController>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            AppHeader(
              title: '工时设置',
              actions: IconButton(
                tooltip: '添加',
                icon: const Icon(Icons.add, color: Colors.white, size: 34),
                onPressed: _pending ? null : () => _edit(context),
              ),
            ),
            Expanded(
              child: Selector<AppSettingsController, List<WorkloadQuickOption>>(
                selector: (context, controller) =>
                    controller.workloadQuickOptions,
                // L-18：仅订阅工时选项切片；getter 为缓存 unmodifiable 视图
                // （唯一写点失效），选项未变的 notify 不触发本列表重建。
                builder: (context, options, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '设置记工时页面常用的工时选项，不会修改已有记录。',
                        style: TextStyle(fontSize: 16, color: textColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            '暂无工时设置，可手动输入工时',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      )
                    else
                      ...options.asMap().entries.map((
                        entry,
                      ) {
                        final index = entry.key;
                        final option = entry.value;
                        return Card(
                          elevation: 0,
                          color: Theme.of(context).cardColor,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: FittedBox(
                                        alignment: Alignment.centerLeft,
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _hoursText(option.minutes),
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _pending
                                          ? null
                                          : () => _edit(context, index: index),
                                      child: const Text('修改'),
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                                Row(
                                  children: [
                                    const Text('显示'),
                                    Switch(
                                      value: option.visible,
                                      onChanged: _pending
                                          ? null
                                          : (value) => _runPending(
                                              context,
                                              () => settings
                                                  .updateWorkloadQuickOption(
                                                    index,
                                                    option.copyWith(
                                                      visible: value,
                                                    ),
                                                  ),
                                            ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _pending
                                          ? null
                                          : () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                    context: context,
                                                    builder: (dialogContext) =>
                                                        AlertDialog(
                                                          title: const Text(
                                                            '删除工时设置',
                                                          ),
                                                          content: const Text(
                                                            '删除后无法在记工时页面使用此工时设置。',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    dialogContext,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                '取消',
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    dialogContext,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                '删除',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                  ) ??
                                                  false;
                                              if (!confirmed) return;
                                              if (!context.mounted) return;
                                              await _runPending(
                                                context,
                                                () => settings
                                                    .removeWorkloadQuickOption(
                                                      index,
                                                    ),
                                              );
                                            },
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _pending
                            ? null
                            : () => _runPending(
                                context,
                                settings.resetWorkloadQuickOptions,
                              ),
                        child: _pending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('恢复默认'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkloadOptionDialog extends StatefulWidget {
  const _WorkloadOptionDialog({
    required this.controller,
    required this.index,
    required this.current,
    required this.errorMessage,
  });

  final AppSettingsController controller;
  final int? index;
  final WorkloadQuickOption? current;
  final String Function(Object error, StackTrace stackTrace) errorMessage;

  @override
  State<_WorkloadOptionDialog> createState() => _WorkloadOptionDialogState();
}

class _WorkloadOptionDialogState extends State<_WorkloadOptionDialog> {
  late final TextEditingController _hoursController;
  String? _hoursError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hoursController = TextEditingController(text: _hoursEcho(widget.current));
  }

  // L-34：回显沿用选项 label 的两位小数展示口径，避免 double→String 长尾。
  // 数值归一直接复用 workloadLabelForMinutes 单一源，仅去掉单位后缀。
  static String _hoursEcho(WorkloadQuickOption? current) {
    if (current == null) return '';
    final label =
        AppSettingsController.workloadLabelForMinutes(current.minutes);
    return label.substring(0, label.length - '小时'.length);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hoursValue = double.tryParse(_hoursController.text.trim());
    final value = hoursValue != null && hoursValue.isFinite
        ? (hoursValue * 60).round()
        : null;
    String? error;
    if (hoursValue == null ||
        !hoursValue.isFinite ||
        hoursValue <= 0 ||
        hoursValue > 24 ||
        value == null ||
        value <= 0 ||
        value > 1440) {
      error = '工时必须大于0且不超过24小时';
    }
    final duplicate =
        value != null &&
        widget.controller.workloadQuickOptions.asMap().entries.any(
          (entry) => entry.key != widget.index && entry.value.minutes == value,
        );
    if (error == null && duplicate) error = '工时不能重复';
    if (error != null) {
      setState(() => _hoursError = error);
      return;
    }

    final minutes = value!;
    final option = WorkloadQuickOption(
      label: AppSettingsController.workloadLabelForMinutes(minutes),
      minutes: minutes,
      visible: widget.current?.visible ?? true,
    );
    setState(() => _saving = true);
    try {
      if (widget.index == null) {
        await widget.controller.addWorkloadQuickOption(option);
      } else {
        final index = widget.index!;
        if (index >= widget.controller.workloadQuickOptions.length ||
            widget.controller.workloadQuickOptions[index].label !=
                widget.current?.label ||
            widget.controller.workloadQuickOptions[index].minutes !=
                widget.current?.minutes) {
          throw const FormatException('列表已更新，请重新编辑');
        }
        await widget.controller.updateWorkloadQuickOption(index, option);
      }
      if (mounted) Navigator.pop(context);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _saving = false;
          _hoursError = widget.errorMessage(error, stackTrace);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.index == null ? '添加工时设置' : '编辑工时设置'),
      content: TextFormField(
        controller: _hoursController,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
        style: const TextStyle(fontSize: 24),
        textAlign: TextAlign.center,
        onChanged: (_) {
          if (_hoursError != null) setState(() => _hoursError = null);
        },
        decoration: InputDecoration(
          labelText: '工时（小时）',
          errorText: _hoursError,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
