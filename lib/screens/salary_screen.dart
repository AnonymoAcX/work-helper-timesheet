import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/theme/app_colors.dart';
import 'package:work_helper/utils/money.dart';
import 'package:work_helper/utils/num_utils.dart';

const _blue = AppColors.blue;

class SalaryScreen extends StatefulWidget {
  const SalaryScreen({super.key, @visibleForTesting this.now});

  /// 可注入时钟；默认使用 DateTime.now（与 RecordScreen 同类 seam）。
  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends State<SalaryScreen> {
  final DataStore _store = DataStore.instance;
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  double _salary = 0;
  double _hours = 0;
  int _calcDay = 1;
  late DateTime _month = _now();
  int _attendanceDays = 0;
  double _overtimeHours = 0;
  int _leaveDays = 0;
  int _calculationRequest = 0;
  String? _calcError;
  bool _exporting = false;
  DateTime? _trendStart;
  List<int> _trendMinutes = const [];
  List<int> _trendCents = const [];

  @override
  void initState() {
    super.initState();
    _store.addListener(_calc);
    _calc();
  }

  @override
  void dispose() {
    _store.removeListener(_calc);
    super.dispose();
  }

  Future<void> _calc() async {
    final request = ++_calculationRequest;
    try {
      // 与 DB 读侧约束同源：DatabaseHelper.getCalculateDay 读侧 clamp 已收口，
      // 此处屏侧 clamp 为双保险。
      final calcDay = (await DatabaseHelper.instance.getCalculateDay()).clamp(
        1,
        28,
      );
      final salary = await DatabaseHelper.instance.calculateMonthlySalary(
        _month.year,
        _month.month,
      );
      final records = await DatabaseHelper.instance.recordsForMonth(
        _month.year,
        _month.month,
      );
      final hours = records.fold<double>(
        0,
        (sum, r) => sum + NumUtils.asDouble(r['workload']),
      );
      final attendanceDays = <int>{};
      final leaveDays = <int>{};
      var overtime = 0.0;
      // 趋势窗口与 recordsForMonth/calculateMonthlySalary 完全同口径：
      // [周期首日, 下周期首日) 逐日一格；工时值=当日各 record workload(时)
      // 折分钟取整后求和；收入值=当日逐行 Money.yuanToCents(工时×单价) 求和。
      final winStart = DateTime(_month.year, _month.month, calcDay);
      final winEnd = DateTime(_month.year, _month.month + 1, calcDay);
      final daySlot = <int, int>{};
      for (
        var d = winStart;
        d.isBefore(winEnd);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        daySlot[d.millisecondsSinceEpoch] = daySlot.length;
      }
      final trendMinutes = List<int>.filled(daySlot.length, 0);
      final trendCents = List<int>.filled(daySlot.length, 0);
      for (final r in records) {
        final type = NumUtils.asInt(r['workload_type']);
        final date = DateTime.fromMillisecondsSinceEpoch(
          NumUtils.asInt(r['date']),
        );
        // 本地日始毫秒键：与趋势槽键同口径，消除 DST 地区的 UTC 日索引偏桶。
        final day =
            DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
        if (isOvertime(type)) {
          overtime += NumUtils.asDouble(r['workload']);
        } else if (isNonWork(type)) {
          leaveDays.add(day);
        } else {
          attendanceDays.add(day);
        }
        if (isOvertime(type)) attendanceDays.add(day);
        final slot = daySlot[day];
        if (slot != null) {
          final workload = NumUtils.asDouble(r['workload']);
          trendMinutes[slot] += WorkMinutes.hoursToMinutes(workload);
          trendCents[slot] += Money.yuanToCents(workload * _effectivePrice(r));
        }
      }
      if (mounted && request == _calculationRequest) {
        setState(() {
          _calcError = null;
          _salary = salary;
          _hours = hours;
          _calcDay = calcDay;
          _attendanceDays = attendanceDays.length;
          _overtimeHours = overtime;
          _leaveDays = leaveDays.length;
          _trendStart = winStart;
          _trendMinutes = trendMinutes;
          _trendCents = trendCents;
        });
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('工资数据加载失败'),
        ),
      );
      if (mounted && request == _calculationRequest) {
        setState(() => _calcError = '加载工资数据失败，请重试');
      }
    }
  }

  /// 计价单价单一口径：preset>0 取预设价，否则取时薪价。
  /// 与 DatabaseHelper.calculateMonthlySalary 的取价逻辑保持一致。
  double _effectivePrice(Map<String, dynamic> r) {
    final preset = NumUtils.asDouble(r['preset_price']);
    return preset > 0 ? preset : NumUtils.asDouble(r['unit_price']);
  }

  Future<void> _exportMonth() async {
    final month = _month;
    if (_exporting) return;
    _exporting = true;
    try {
      final settings = context.read<AppSettingsController>();
      final records = await DatabaseHelper.instance.recordsForMonth(
        month.year,
        month.month,
      );
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本周期没有可导出的工时')));
        return;
      }
      final buffer = StringBuffer('日期,班次,工时,时薪,小计,备注\n');
      for (final r in records) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          NumUtils.asInt(r['date']),
        );
        final workload = NumUtils.asDouble(r['workload']);
        final price = _effectivePrice(r);
        final type = NumUtils.asInt(r['workload_type']);
        final subtotal = Money.formatYuan(Money.yuanToCents(workload * price));
        buffer.writeln(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')},${_csvCell(settings.labelForWorkType(type))},${workload.toStringAsFixed(1)},${price.toStringAsFixed(2)},$subtotal,${_csvCell(r['remark'] ?? '')}',
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/work_helper_${month.year}_${month.month.toString().padLeft(2, '0')}.csv',
      );
      await file.writeAsString('\uFEFF$buffer');
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(file.path),
      ], text: '记工时 ${month.year}年${month.month}月统计');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('工时导出失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('工时导出失败，请重试')));
      }
    } finally {
      _exporting = false;
    }
  }

  String _csvCell(Object value) {
    var text = value.toString();
    // 中和 CSV 公式注入：以 = + - @ 或制表符开头的单元格前置单引号。
    if (text.startsWith(RegExp(r'^[=+\-@\t]'))) {
      text = "'$text";
    }
    if (text.contains(RegExp(r'[",\n]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  void _moveMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _calc();
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime(_month.year, _month.month, _calcDay);
    final end = DateTime(
      _month.year,
      _month.month + 1,
      _calcDay,
    ).subtract(const Duration(days: 1));
    final err = _calcError != null;
    final salaryText = err ? '--' : _salary.toStringAsFixed(2);
    final hoursText = err ? '--' : _hours.toStringAsFixed(1);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 270,
              color: _blue,
              padding: const EdgeInsets.fromLTRB(18, 40, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SquareButton(
                        icon: Icons.chevron_left,
                        label: '上月',
                        onTap: () => _moveMonth(-1),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${start.month}/${start.day}-${end.month}/${end.day}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_month.year}年',
                                style: const TextStyle(
                                  fontSize: 19,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SquareButton(
                        icon: Icons.chevron_right,
                        label: '下月',
                        onTap: () => _moveMonth(1),
                      ),
                      const SizedBox(width: 8),
                      _SquareButton(
                        icon: Icons.file_upload_outlined,
                        label: '导出',
                        onTap: _exportMonth,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '本周期工资',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    err ? '--' : '¥$salaryText',
                    style: const TextStyle(fontSize: 42, color: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _Metric(
                          value: salaryText,
                          label: '收入(元)',
                        ),
                        _Metric(
                          value: hoursText,
                          label: '工时(时)',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: err
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_calcError!),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _calc,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _TrendCard(
                          title: '收入趋势',
                          startDate: start,
                          values: _trendStart == start ? _trendCents : const [],
                          valueText: (v) => '¥${Money.formatYuan(v)}',
                        ),
                        const SizedBox(height: 18),
                        _TrendCard(
                          title: '工时趋势',
                          startDate: start,
                          values:
                              _trendStart == start ? _trendMinutes : const [],
                          valueText: WorkMinutes.hoursTextFromMinutes,
                        ),
                        const SizedBox(height: 18),
                        _StatsCard(
                          attendanceDays: _attendanceDays,
                          overtimeHours: _overtimeHours,
                          leaveDays: _leaveDays,
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

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 24, color: Colors.white),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.attendanceDays,
    required this.overtimeHours,
    required this.leaveDays,
  });
  final int attendanceDays;
  final double overtimeHours;
  final int leaveDays;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          _stat(context, '$attendanceDays', '出勤天数', colors.primary),
          _stat(
            context,
            overtimeHours.toStringAsFixed(1),
            '加班小时',
            colors.secondary,
          ),
          _stat(context, '$leaveDays', '请假天数', colors.tertiary),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.startDate,
    required this.values,
    required this.valueText,
  });

  final String title;

  /// 考勤周期首日（calculate_day 对应日），与 values 逐格对齐。
  final DateTime startDate;

  /// 每日一条：工时卡为「分钟」，收入卡为「分」，空日为 0。
  final List<int> values;

  /// 数值展示文本：如「7小时5分」「¥88.00」。
  final String Function(int value) valueText;

  DateTime _day(int index) =>
      DateTime(startDate.year, startDate.month, startDate.day + index);

  @override
  Widget build(BuildContext context) {
    var max = 0;
    for (final v in values) {
      if (v > max) max = v;
    }
    final n = values.length;
    return Container(
      height: 236,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          if (n == 0 || max == 0)
            const Expanded(
              child: Center(child: Text('本周期暂无数据')),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                '峰值 ${valueText(max)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          label:
                              '${_day(i).month}月${_day(i).day}日 ${valueText(values[i])}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 1,
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: values[i] > 0
                                    ? 120 * values[i] / max
                                    : 0.0,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [_blue, Color(0xFFB1F489)],
                                  ),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final i in {
                    0,
                    n ~/ 4,
                    n ~/ 2,
                    n * 3 ~/ 4,
                    n - 1,
                  })
                    Text(
                      '${i == 0 ? '起 ' : ''}${_day(i).month}/${_day(i).day}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
