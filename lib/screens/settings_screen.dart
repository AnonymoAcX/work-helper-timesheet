import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/screens/attendance_cycle_screen.dart';
import 'package:work_helper/screens/hourly_rate_settings_screen.dart';
import 'package:work_helper/screens/reminder_settings_screen.dart';
import 'package:work_helper/screens/theme_settings_screen.dart';
import 'package:work_helper/screens/work_color_settings_screen.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/theme/app_colors.dart';
import 'package:work_helper/screens/workload_quick_options_screen.dart';

const _blue = AppColors.blue;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 96,
              width: double.infinity,
              color: _blue,
              padding: const EdgeInsets.only(top: 44),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _MenuItem(
                    icon: Icons.bolt_outlined,
                    title: '工时设置',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkloadQuickOptionsScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.payments_outlined,
                    title: '时薪设置',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HourlyRateSettingsScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.star_border,
                    title: '主题设置',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemeSettingsScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.palette_outlined,
                    title: '工时颜色',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkColorSettingsScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.calendar_month_outlined,
                    title: '考勤周期',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AttendanceCycleScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.notifications_none,
                    title: '提醒',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReminderSettingsScreen(),
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.backup_outlined,
                    title: '备份数据',
                    onTap: _busy ? null : _backup,
                  ),
                  _MenuItem(
                    icon: Icons.settings_backup_restore,
                    title: '恢复数据',
                    onTap: _busy ? null : _restore,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backup() async {
    if (_busy) return;
    final confirmed = await _confirm(
      '备份数据',
      '将当前的本机数据（工时记录、待办、考勤设置和快捷项）生成一个备份文件，'
          '生成后可通过系统分享保存到手机文件或其他应用中。',
      '开始备份',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      await _runGuarded(() async {
        final File file;
        try {
          final data = await DatabaseHelper.instance.exportAll(
            settings: context.read<AppSettingsController>().exportSettings(),
          );
          final dir = await getApplicationDocumentsDirectory();
          file = File(
            p.join(dir.path, 'backup_${_stamp(DateTime.now())}.json'),
          );
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
          );
        } on FileSystemException {
          return '备份文件保存失败，请检查存储空间后重试';
        }
        try {
          await Share.shareXFiles([XFile(file.path)], subject: '工时数据备份');
          return '备份完成，可在分享页面中选择保存位置';
        } on FormatException {
          return '备份文件已生成，分享页面未能打开；备份仍可在「恢复数据」中使用';
        } on StateError {
          return '备份文件已生成，分享页面未能打开；备份仍可在「恢复数据」中使用';
        } on DatabaseException {
          return '备份文件已生成，分享页面未能打开；备份仍可在「恢复数据」中使用';
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      });
    });
  }

  Future<void> _restore() async {
    if (_busy) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      final backups = <({File file, DateTime modified})>[];
      for (final f in dir.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (!name.startsWith('backup_') || !name.endsWith('.json')) continue;
        try {
          backups.add((file: f, modified: f.statSync().modified));
        } on FileSystemException {
          continue; // 列举与 stat 之间文件可能已消失，跳过即可
        }
      }
      backups.sort((a, b) => b.modified.compareTo(a.modified));
      const pickFromSystem = '__pick_from_system__';
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择备份文件'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.folder_open, color: _blue),
                    title: const Text('从文件管理器选择…'),
                    subtitle: const Text('选择保存在下载、聊天工具等位置的 JSON 备份'),
                    onTap: () => Navigator.pop(context, pickFromSystem),
                  ),
                  if (backups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('应用内暂无备份，请通过上方入口选择文件。'),
                    ),
                  for (final entry in backups)
                    ListTile(
                      title: Text(
                        p.basename(entry.file.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(entry.modified),
                      ),
                      onTap: () => Navigator.pop(context, entry.file.path),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (selected == null) return;
      String backupPath = selected;
      if (selected == pickFromSystem) {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: '选择备份文件',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (!mounted) return;
        if (result == null || result.files.isEmpty) return;
        final picked = result.files.single.path;
        if (picked == null) {
          _toast('无法读取所选文件，请换一个位置保存后再试');
          return;
        }
        backupPath = picked;
      }
      final confirmed = await _confirm(
        '恢复数据',
        '恢复后会用所选备份的内容替换当前的本机数据（工时记录、待办、考勤设置和快捷项）。'
            '当前数据会在恢复前自动再备份一次，不会丢失。',
        '恢复',
      );
      if (!confirmed || !mounted) return;
      final source = File(backupPath);
      final settings = context.read<AppSettingsController>();
      final autoPath = p.join(
        dir.path,
        'backup_auto_${_stamp(DateTime.now())}.json',
      );
      await _runBusy(() async {
        await _runGuarded(() async {
          final current = await DatabaseHelper.instance.exportAll();
          await File(autoPath).writeAsString(jsonEncode(current));
          try {
            _pruneAutoBackups(dir);
          } on FileSystemException {
            // 轮转清理尽力而为，失败不影响本次恢复
          }
          final Object? decoded;
          try {
            decoded = jsonDecode(await source.readAsString());
          } on FormatException {
            throw const FormatException('所选文件不是有效的备份文件');
          }
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('所选文件不是有效的备份文件');
          }
          if (decoded['schemaVersion'] == 2 && decoded['settings'] != null) {
            settings.validateBackupSettings(decoded['settings']);
          }
          final count = await DatabaseHelper.instance.importAll(decoded);
          String message = '恢复完成，共还原 $count 条数据';
          if (decoded['schemaVersion'] == 2 && decoded['settings'] != null) {
            try {
              await settings.importSettings(decoded['settings']);
            } catch (error, stackTrace) {
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  context: ErrorDescription('恢复时部分设置导入失败'),
                ),
              );
              message = '部分恢复：数据已还原，部分设置导入失败';
            }
          }
          DataStore.instance.bump();
          return message;
        });
      });
    } on FileSystemException {
      _toast('读取备份文件失败，请重试');
    }
  }

  Future<bool> _confirm(String title, String content, String okLabel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runGuarded(Future<String> Function() task) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(width: 16),
              Text('正在处理，请稍候…'),
            ],
          ),
        ),
      ),
    );
    String message;
    try {
      message = await task();
    } on FormatException catch (e) {
      message = '操作未完成：${e.message}';
    } on StateError catch (e) {
      message = '操作未完成：${e.message}';
    } on DatabaseException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('设置备份恢复操作失败'),
        ),
      );
      message = '操作失败，请重试';
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('设置备份恢复操作失败'),
        ),
      );
      message = '操作失败，请重试';
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _stamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}'
      '_${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

/// 自动备份（backup_auto_*.json）仅保留最近 10 份，按修改时间删最旧；
/// 手动备份（backup_*.json）永不自动删除。
void _pruneAutoBackups(Directory dir) {
  const keep = 10;
  final autoBackups = <(File, DateTime)>[];
  for (final f in dir.listSync().whereType<File>()) {
    final name = p.basename(f.path);
    if (!name.startsWith('backup_auto_') || !name.endsWith('.json')) continue;
    try {
      autoBackups.add((f, f.statSync().modified));
    } on FileSystemException {
      continue;
    }
  }
  if (autoBackups.length <= keep) return;
  autoBackups.sort((a, b) => b.$2.compareTo(a.$2));
  for (final (file, _) in autoBackups.sublist(keep)) {
    file.deleteSync();
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .55 : 1,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              const SizedBox(width: 26),
              Icon(icon, size: 29, color: textColor),
              const SizedBox(width: 20),
              Text(title, style: TextStyle(fontSize: 21, color: textColor)),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 32,
                color: textColor.withValues(alpha: .45),
              ),
              const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}
