import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/theme/app_colors.dart';

class HourlyRateSettingsScreen extends StatefulWidget {
  const HourlyRateSettingsScreen({super.key});

  @override
  State<HourlyRateSettingsScreen> createState() =>
      _HourlyRateSettingsScreenState();
}

class _HourlyRateSettingsScreenState extends State<HourlyRateSettingsScreen> {
  bool _pending = false;

  Future<void> _showAddRateDialog(BuildContext context) async {
    if (_pending) return;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? error;
        var saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('添加常用时薪'),
            content: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: '时薪金额', errorText: error),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onChanged: (_) {
                if (error != null) {
                  setDialogState(() => error = null);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final rate = double.tryParse(controller.text.trim());
                        if (rate == null ||
                            rate <= 0 ||
                            rate > 10000 ||
                            !rate.isFinite) {
                          setDialogState(() => error = '时薪需大于0且不超过10000');
                          return;
                        }
                        setDialogState(() => saving = true);
                        setState(() => _pending = true);
                        try {
                          await context
                              .read<AppSettingsController>()
                              .addHourlyRate(rate);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } on FormatException catch (exception) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = exception.message;
                            });
                          }
                        } on StateError catch (exception) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = exception.message;
                            });
                          }
                        } on DatabaseException catch (exception, stackTrace) {
                          FlutterError.reportError(
                            FlutterErrorDetails(
                              exception: exception,
                              stack: stackTrace,
                              context: ErrorDescription('常用时薪保存失败'),
                            ),
                          );
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = '保存失败，请重试';
                            });
                          }
                        } catch (error, stackTrace) {
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                          }
                          Error.throwWithStackTrace(error, stackTrace);
                        } finally {
                          if (mounted) setState(() => _pending = false);
                        }
                      },
                child: saving
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('保存中…'),
                        ],
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await action();
    } catch (error, stackTrace) {
      final message = switch (error) {
        FormatException exception => exception.message,
        StateError exception => exception.message,
        DatabaseException() => '操作失败，请重试',
        _ => null,
      };
      if (message == null) Error.throwWithStackTrace(error, stackTrace);
      if (error is DatabaseException) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            context: ErrorDescription('时薪设置操作失败'),
          ),
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // R4-2：watch→select。三个 getter 均为 ??= 缓存稳定视图（写点统一经
    // _setHourlyRates/失效，含 :356 就地可见性变更的手动失效），record 逐字段
    // 相等比较成立：仅时薪/默认值/可见性真正变化才重建。事件方法经 read 取控制器。
    final (rates, defaultRate, visibleRates) = context.select<
      AppSettingsController,
      (List<double>, double, List<double>)
    >((s) => (s.hourlyRates, s.defaultHourlyRate, s.visibleHourlyRates));
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(
              title: '时薪设置',
              action: Icons.add,
              onAction: _pending ? null : () => _showAddRateDialog(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
                children: [
                  _InfoCard(
                    title: '默认时薪',
                    value: '¥${defaultRate.toStringAsFixed(2)} / 小时',
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '常用时薪',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...rates.map((rate) {
                    final selected = rate == defaultRate;
                    Future<void> onSetDefault() => _runAction(
                      context,
                      () => context
                          .read<AppSettingsController>()
                          .setDefaultHourlyRate(rate),
                    );
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
                                IconButton(
                                  onPressed: _pending ? null : onSetDefault,
                                  tooltip: '设为默认',
                                  icon: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: selected
                                        ? AppColors.blue
                                        : textColor.withValues(alpha: .55),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '¥${rate.toStringAsFixed(2)} / 小时',
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Text(
                                    '默认时薪',
                                    style: TextStyle(color: AppColors.blue),
                                  )
                                else
                                  TextButton(
                                    onPressed: _pending ? null : onSetDefault,
                                    child: const Text('设为默认'),
                                  ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              children: [
                                const Text('显示'),
                                Switch(
                                  value: visibleRates.contains(rate),
                                  onChanged: _pending
                                      ? null
                                      : (value) => _runAction(
                                          context,
                                          () => context
                                              .read<AppSettingsController>()
                                              .updateHourlyRateVisibility(
                                                rate,
                                                value,
                                              ),
                                        ),
                                ),
                                const Spacer(),
                                if (rates.length > 1)
                                  TextButton(
                                    onPressed: _pending
                                        ? null
                                        : () => _runAction(
                                            context,
                                            () => context
                                                .read<AppSettingsController>()
                                                .removeHourlyRate(rate),
                                          ),
                                    child: const Text('删除'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.action, this.onAction});

  final String title;
  final IconData? action;
  final VoidCallback? onAction;

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (action != null)
            IconButton(
              tooltip: '添加',
              icon: Icon(action, color: Colors.white, size: 34),
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}
