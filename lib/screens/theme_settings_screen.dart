import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/theme/app_colors.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  bool _pending = false;

  Future<void> _updateThemeMode(ThemeMode mode) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await context.read<AppSettingsController>().updateThemeMode(mode);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('主题设置操作失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppSettingsController, ThemeMode>(
      (controller) => controller.themeMode,
    );
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const _Header(title: '主题设置'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                children: [
                  _ThemeOption(
                    title: '亮色主题',
                    subtitle: '白色背景，适合白天使用',
                    mode: ThemeMode.light,
                    groupValue: themeMode,
                    onChanged: _pending ? null : _updateThemeMode,
                  ),
                  _ThemeOption(
                    title: '暗色主题',
                    subtitle: '深色背景，适合夜间查看',
                    mode: ThemeMode.dark,
                    groupValue: themeMode,
                    onChanged: _pending ? null : _updateThemeMode,
                  ),
                  _ThemeOption(
                    title: '跟随系统',
                    subtitle: '随手机系统主题自动切换',
                    mode: ThemeMode.system,
                    groupValue: themeMode,
                    onChanged: _pending ? null : _updateThemeMode,
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final ThemeMode mode;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = mode == groupValue;
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected
              ? AppColors.blue
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        onTap: onChanged == null ? null : () => onChanged!(mode),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      color: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(18, 44, 24, 14),
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
          const SizedBox(width: 28),
          Text(
            title,
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
