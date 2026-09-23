import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/theme/app_colors.dart';

class AttendanceCycleScreen extends StatefulWidget {
  const AttendanceCycleScreen({super.key});

  @override
  State<AttendanceCycleScreen> createState() => _AttendanceCycleScreenState();
}

class _AttendanceCycleScreenState extends State<AttendanceCycleScreen> {
  int _day = 1;
  int? _rawOutOfRange; // _load 读到的越界原值，非空时 _save 回写自愈
  bool _loading = true;
  bool _pending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final raw = await DatabaseHelper.instance.getCalculateDay();
      final day = raw.clamp(1, 28);
      if (mounted) {
        setState(() {
          _day = day;
          _rawOutOfRange = raw == day ? null : raw;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('考勤周期读取失败'),
        ),
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '读取考勤周期失败，请重试';
        });
      }
    }
  }

  String _label(int day) => day == 1 ? '1号-本月底' : '$day号-下月${day - 1}号';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 120,
              color: AppColors.blue,
              padding: const EdgeInsets.fromLTRB(18, 44, 24, 14),
              child: Row(
                children: [
                  InkWell(
                    onTap: _loading || _pending
                        ? null
                        : () => Navigator.pop(context),
                    child: Tooltip(
                      message: '返回',
                      child: Semantics(
                        button: true,
                        label: '返回',
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
                  const Text(
                    '考勤周期',
                    style: TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 0),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .08),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Text('考勤周期', style: TextStyle(fontSize: 24)),
                  const Spacer(),
                  Text(_label(_day), style: const TextStyle(fontSize: 24)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.95,
                        children: List.generate(28, (i) {
                          final day = i + 1;
                          final selected = day == _day;
                          return InkWell(
                            onTap: _loading || _pending
                                ? null
                                : () => setState(() => _day = day),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.blue
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _label(day),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: selected
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 44),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _loading || _pending ? null : _save,
                  child: _pending
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              '保存中…',
                              style: TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '完 成',
                          style: TextStyle(fontSize: 24, color: Colors.white),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await DatabaseHelper.instance.updateCalculateDay(_day);
      DataStore.instance.bump();
      if (!mounted) return;
      if (_rawOutOfRange != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('原设置值（$_rawOutOfRange 日）越界，已修正为 $_day 日')),
        );
      }
      Navigator.pop(context);
    } on DatabaseException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('考勤周期保存失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('考勤周期保存失败'),
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
}
