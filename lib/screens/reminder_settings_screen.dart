import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/services/reminder_notification_service.dart';
import 'package:work_helper/theme/app_colors.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _pending = false;

  String _timeText(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<void> _setEnabled(BuildContext context, bool enabled) async {
    await _runPending(context, () async {
      final settings = context.read<AppSettingsController>();
      final oldEnabled = settings.reminderEnabled;
      final oldHour = settings.reminderHour;
      final oldMinute = settings.reminderMinute;
      try {
        if (!enabled) {
          await ReminderNotificationService.instance.cancelDaily();
          await settings.updateReminderEnabled(false);
          return;
        }
        final ok = await ReminderNotificationService.instance.scheduleDaily(
          hour: oldHour,
          minute: oldMinute,
        );
        if (!ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('通知权限未开启，无法启用提醒')));
          }
          return;
        }
        await settings.updateReminderEnabled(true);
      } catch (error, stackTrace) {
        await _restoreNotification(oldEnabled, oldHour, oldMinute);
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _pickTime(BuildContext context) async {
    await _runPending(context, () async {
      final settings = context.read<AppSettingsController>();
      final messenger = ScaffoldMessenger.of(context);
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: settings.reminderHour,
          minute: settings.reminderMinute,
        ),
        helpText: '选择提醒时间',
        cancelText: '取消',
        confirmText: '确定',
      );
      if (picked == null || !context.mounted) return;
      final oldHour = settings.reminderHour;
      final oldMinute = settings.reminderMinute;
      final oldEnabled = settings.reminderEnabled;
      var timeSaved = false;
      try {
        await settings.updateReminderTime(
          hour: picked.hour,
          minute: picked.minute,
        );
        timeSaved = true;
        if (oldEnabled) {
          final ok = await ReminderNotificationService.instance.scheduleDaily(
            hour: picked.hour,
            minute: picked.minute,
          );
          if (!ok) {
            await _restoreReminderPreferences(
              settings,
              oldEnabled,
              oldHour,
              oldMinute,
            );
            messenger.showSnackBar(
              const SnackBar(content: Text('通知权限未开启，提醒时间未更改')),
            );
          }
        }
      } catch (error, stackTrace) {
        if (timeSaved) {
          var restoreFailed = false;
          try {
            await _restoreReminderPreferences(
              settings,
              oldEnabled,
              oldHour,
              oldMinute,
            );
          } catch (restoreError, restoreStack) {
            restoreFailed = true;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: restoreError,
                stack: restoreStack,
                context: ErrorDescription('恢复提醒设置失败'),
              ),
            );
          }
          try {
            await _restoreNotification(oldEnabled, oldHour, oldMinute);
          } catch (restoreError, restoreStack) {
            restoreFailed = true;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: restoreError,
                stack: restoreStack,
                context: ErrorDescription('恢复提醒通知失败'),
              ),
            );
          }
          if (restoreFailed) {
            messenger.showSnackBar(
              const SnackBar(content: Text('恢复失败，请重试或重新开启权限')),
            );
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _restoreReminderPreferences(
    AppSettingsController settings,
    bool enabled,
    int hour,
    int minute,
  ) async {
    await settings.updateReminderTime(hour: hour, minute: minute);
    await settings.updateReminderEnabled(enabled);
  }

  Future<void> _restoreNotification(bool enabled, int hour, int minute) async {
    if (enabled) {
      final ok = await ReminderNotificationService.instance.scheduleDaily(
        hour: hour,
        minute: minute,
      );
      if (!ok) throw StateError('无法恢复提醒通知');
    } else {
      await ReminderNotificationService.instance.cancelDaily();
    }
  }

  Future<void> _sendReminderPreview(BuildContext context) async {
    await _runPending(context, () async {
      final ok = await ReminderNotificationService.instance
          .showReminderPreview();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ok ? '提醒已发送' : '通知权限未开启')));
    });
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('提醒设置操作失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (reminderEnabled, reminderHour, reminderMinute) = context.select<
        AppSettingsController,
        (bool, int, int)
    >((s) => (s.reminderEnabled, s.reminderHour, s.reminderMinute));
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(pending: _pending),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: Colors.white,
                          size: 36,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '通知栏提醒',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reminderEnabled
                                    ? '每天 ${_timeText(reminderHour, reminderMinute)} 提醒记录工时'
                                    : '关闭后不会主动打扰',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Color(0xDDFFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: reminderEnabled,
                          activeThumbColor: Colors.white,
                          activeTrackColor: Colors.white.withValues(alpha: .42),
                          onChanged: _pending
                              ? null
                              : (value) => _setEnabled(context, value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    child: ListTile(
                      leading: Icon(Icons.schedule, color: textColor),
                      title: const Text(
                        '提醒时间',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('每天一次，使用通知栏提示'),
                      trailing: Text(
                        _timeText(reminderHour, reminderMinute),
                        style: TextStyle(
                          fontSize: 22,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _pending ? null : () => _pickTime(context),
                    ),
                  ),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    child: ListTile(
                      leading: Icon(
                        Icons.notification_important,
                        color: textColor,
                      ),
                      title: const Text(
                        '立即提醒',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('立即发送一条通知，检查系统权限和显示效果'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pending
                          ? null
                          : () => _sendReminderPreview(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      color: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(14, 38, 18, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 38),
            tooltip: '返回',
            onPressed: pending ? null : () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          const Text(
            '提醒',
            style: TextStyle(
              fontSize: 27,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
