import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/models/record.dart';
import 'package:work_helper/theme/app_colors.dart';
import 'package:work_helper/utils/lunar_formatter.dart';
import 'package:work_helper/utils/money.dart';
import 'package:work_helper/utils/num_utils.dart';

const _blue = AppColors.blue;
const _lightBlue = AppColors.lightBlue;

double _asDouble(Object? value) => NumUtils.asDouble(value);

int _asInt(Object? value) => NumUtils.asInt(value);

bool _isLeaveType(int id) => id == kTypeIdLeave;

bool _isRestType(int id) => id == kTypeIdRest;

/// 记录生效时薪单一口径：预定价优先，否则单价。
double _effectiveRate(Map<String, dynamic> record) {
  final preset = _asDouble(record['preset_price']);
  return preset > 0 ? preset : _asDouble(record['unit_price']);
}

/// 时薪统一归一到两位小数（Money 分口径），消除种子/保存两侧舍入漂移。
double _normalizeRate(double value) =>
    Money.centsToYuan(Money.yuanToCents(value));

String _compactNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatWorkload(double hours) {
  final minutes = (hours * 60).round();
  final hourPart = minutes ~/ 60;
  final minutePart = minutes % 60;
  if (minutes <= 0) return '';
  if (minutePart == 0) return '$hourPart小时';
  if (hourPart == 0) return '$minutePart分钟';
  return '$hourPart时$minutePart分';
}

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, @visibleForTesting this.now});

  /// 可注入时钟；默认使用 DateTime.now（与 DatabaseHelper
  /// .databasePathOverrideForTest 同类 seam）。
  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final DataStore _store = DataStore.instance;
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  late DateTime _focusedMonth = _now();
  late DateTime _selectedDate = _now();
  List<Map<String, dynamic>> _history = [];
  String? _historyError;
  int _historyRequest = 0;

  /// 日期键 → 当日记录分组缓存，随 [_loadHistory] 重建。
  Map<String, List<Map<String, dynamic>>> _recordsByDay = const {};

  /// 记录 id → 搜索标签缓存，避免每次 setState/按键重复算农历标签。
  Map<String, List<String>> _searchLabelsById = const {};

  static const int _reminderStartHour = 18;

  DateTime get _datePickerFirstDate {
    if (_history.isEmpty) return DateTime(_now().year - 1);
    final oldest = _history
        .map(
          (record) =>
              DateTime.fromMillisecondsSinceEpoch(_asInt(record['date'])),
        )
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return _dateOnly(oldest);
  }

  DateTime get _datePickerLastDate {
    final now = _dateOnly(_now());
    if (_history.isEmpty) return now;
    final newest = _history
        .map(
          (record) =>
              DateTime.fromMillisecondsSinceEpoch(_asInt(record['date'])),
        )
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return newest.isAfter(now) ? _dateOnly(newest) : now;
  }

  Future<void> _pickDate() async {
    final firstDate = _datePickerFirstDate;
    final lastDate = _datePickerLastDate;
    final initialDate = _selectedDate.isBefore(firstDate)
        ? firstDate
        : (_selectedDate.isAfter(lastDate) ? lastDate : _selectedDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _focusedMonth = DateTime(picked.year, picked.month);
      _selectedDate = picked;
    });
  }

  @override
  void dispose() {
    _store.removeListener(_reloadHistory);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _store.addListener(_reloadHistory);
    _loadHistoryGuarded();
  }

  void _reloadHistory() {
    _loadHistoryGuarded();
  }

  /// 丢弃式/await 调用点的统一入口：预期错误已在 [_loadHistory] 内收口，
  /// 逃逸到此的均为非预期错误，转为错误态显示并保留调试日志，不再裸丢弃。
  Future<List<Map<String, dynamic>>?> _loadHistoryGuarded() {
    final future = _loadHistory();
    final request = _historyRequest;
    return future.catchError((Object error, StackTrace stackTrace) {
      debugPrint('历史记录加载意外错误: $error\n$stackTrace');
      if (!mounted || request != _historyRequest) return null;
      setState(() => _historyError = '历史记录加载失败，请重试');
      return null;
    });
  }

  void _handleExpectedError(
    Object error,
    StackTrace stackTrace,
    String fallback, {
    int? historyRequest,
    bool rethrowUnexpected = true,
  }) {
    if (error is FormatException) {
      // 内部详情只进调试日志，不直接展示给用户。
      debugPrint('FormatException（内部详情）: ${error.message}');
    }
    var message = switch (error) {
      DatabaseException() => fallback,
      StateError() => fallback,
      FormatException() => fallback,
      _ => null,
    };
    if (message == null) {
      if (rethrowUnexpected) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      // 丢弃式调用终点（复制/删除按钮）不重抛：非预期错误转 SnackBar
      // 兜底提示用户，原始错误保留调试日志。
      debugPrint('意外错误: $error\n$stackTrace');
      message = fallback;
    }
    if (!mounted) return;
    if (historyRequest != null) {
      if (historyRequest != _historyRequest) return;
      setState(() => _historyError = message);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<Map<String, dynamic>>?> _loadHistory() async {
    final request = ++_historyRequest;
    try {
      final db = await DatabaseHelper.instance.database;
      final records = await db.query('record', orderBy: 'date DESC');
      if (mounted && request == _historyRequest) {
        setState(() {
          _history = records;
          _rebuildHistoryCaches();
          _historyError = null;
        });
      }
      return records;
    } catch (error, stackTrace) {
      _handleExpectedError(
        error,
        stackTrace,
        '历史记录加载失败，请重试',
        historyRequest: request,
      );
      return null;
    }
  }

  /// 重建按日期分组缓存与搜索标签缓存；随每次成功加载整体替换。
  void _rebuildHistoryCaches() {
    final byDay = <String, List<Map<String, dynamic>>>{};
    final labels = <String, List<String>>{};
    for (final record in _history) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        _asInt(record['date']),
      );
      byDay.putIfAbsent(_dateText(date), () => []).add(record);
      labels['${record['id']}'] = _searchLabelsFor(record);
    }
    _recordsByDay = byDay;
    _searchLabelsById = labels;
  }

  List<DateTime?> _monthCells() {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final days = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = <DateTime?>[...List<DateTime?>.filled(leading, null)];
    for (var i = 1; i <= days; i++) {
      cells.add(DateTime(_focusedMonth.year, _focusedMonth.month, i));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _recordsForDate(DateTime date) =>
      _recordsByDay[_dateText(date)] ?? const [];

  List<String> _searchLabelsFor(Map<String, dynamic> record) {
    final date = DateTime.fromMillisecondsSinceEpoch(_asInt(record['date']));
    return [
      _dateText(date),
      '${date.month}月${date.day}日',
      LunarFormatter.fullLabel(date),
    ];
  }

  List<Map<String, dynamic>> _searchResults(
    String keyword, {
    List<Map<String, dynamic>>? history,
  }) {
    final normalized = keyword.trim();
    final source = history ?? _history;
    if (normalized.isEmpty) return List<Map<String, dynamic>>.from(source);
    return source
        .where((record) {
          final labels =
              _searchLabelsById['${record['id']}'] ??
              _searchLabelsFor(record);
          return labels.any((label) => label.contains(normalized));
        })
        .toList(growable: false);
  }

  DateTime _selectedDateInMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = _selectedDate.day > lastDay ? lastDay : _selectedDate.day;
    return DateTime(year, month, day);
  }

  bool get _needsTodayReminder {
    final now = _now();
    return now.hour >= _reminderStartHour && _recordsForDate(now).isEmpty;
  }

  Future<void> _recordToday() async {
    final now = _now();
    setState(() {
      _selectedDate = now;
      _focusedMonth = DateTime(now.year, now.month);
    });
    await _showRecordSheet();
  }

  /// 快捷选择器以整数分钟为返回源，避免「小时文本→reparse」漂移。
  /// sourceMinutes 为调用点的分钟权威源（编辑回填/快捷选择），优先使用；
  /// 文本反推仅在无权威源时兜底。
  Future<int?> _showWorkloadPicker(
    TextEditingController workload, {
    int? sourceMinutes,
  }) async {
    final initialMinutes =
        sourceMinutes ??
        WorkMinutes.hoursToMinutes(
          double.tryParse(workload.text.trim()) ?? 0,
        );
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _WorkloadQuickPicker(initialMinutes: initialMinutes),
    );
  }

  Future<void> _showRecordSheet([Map<String, dynamic>? editingRecord]) async {
    final settings = context.read<AppSettingsController>();
    final editing = editingRecord != null;
    final recordDate = editing
        ? DateTime.fromMillisecondsSinceEpoch(_asInt(editingRecord['date']))
        : _selectedDate;
    final initialWorkload = editing
        ? _asDouble(editingRecord['workload'])
        : 0.0;
    final initialType = editing ? _asInt(editingRecord['workload_type']) : 0;
    final initialRate = _normalizeRate(
      editing ? _effectiveRate(editingRecord) : settings.defaultHourlyRate,
    );
    // 分钟权威源：编辑回填/快捷选择时以整数分钟为准，保存不经小时文本往返；
    // 用户手动编辑工时文本后置空，改以文本解析为准。
    int? workloadSourceMinutes = editing
        ? WorkMinutes.hoursToMinutes(initialWorkload)
        : null;
    final workload = TextEditingController(
      text: initialWorkload > 0 ? _compactNumber(initialWorkload) : '',
    );
    final remark = TextEditingController(
      text: editingRecord?['remark']?.toString() ?? '',
    );
    final customPrice = TextEditingController(
      text: initialRate > 0
          ? initialRate.toStringAsFixed(2)
          : settings.defaultHourlyRate.toStringAsFixed(2),
    );
    final today = _dateOnly(_now());
    final selectedDay = _dateOnly(recordDate);
    final sheetTitle = editing
        ? '修改工时'
        : (selectedDay.isBefore(today) ? '补录工时' : '记工时');
    var selectedRate = initialRate > 0
        ? initialRate
        : settings.defaultHourlyRate;
    var customRate =
        initialRate > 0 && !settings.hourlyRates.contains(initialRate);
    var selectedWorkType = initialType;
    var isSaving = false;
    var sheetActive = true;
    String? workloadError;
    String? rateError;
    String? saveError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      barrierColor: Colors.black.withValues(alpha: .38),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return _DisposeOnUnmount(
          onDispose: () {
            sheetActive = false;
            workload.dispose();
            remark.dispose();
            customPrice.dispose();
          },
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final restType = _isRestType(selectedWorkType);
              final leaveType = _isLeaveType(selectedWorkType);
              final wageVisible = needsWage(selectedWorkType);
              return PopScope(
                canPop: !isSaving,
                child: SafeArea(
                  top: false,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * .88,
                    ),
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              left: 18,
                              right: 18,
                              top: 18,
                              bottom:
                                  MediaQuery.of(context).viewInsets.bottom + 12,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$sheetTitle  ${_dateText(recordDate)}',
                                        style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭',
                                      onPressed: isSaving
                                          ? null
                                          : () => Navigator.pop(context),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _RecordSection(
                                  title: '班次',
                                  child: _WorkTypeGrid(
                                    selectedId: selectedWorkType,
                                    onChanged: (id) => setSheetState(() {
                                      selectedWorkType = id;
                                      workloadError = null;
                                      rateError = null;
                                      saveError = null;
                                      if (_isRestType(id)) {
                                        workload.clear();
                                        workloadSourceMinutes = null;
                                      }
                                    }),
                                  ),
                                ),
                                if (!restType) ...[
                                  const SizedBox(height: 12),
                                  _RecordSection(
                                    title: leaveType ? '时长' : '工作量',
                                    child: Column(
                                      children: [
                                        TextField(
                                          controller: workload,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: leaveType
                                                ? '时长（小时）'
                                                : '工时（小时）',
                                            errorText: workloadError,
                                            suffixIcon: IconButton(
                                              tooltip: '快捷填写',
                                              onPressed: () async {
                                                final value =
                                                    await _showWorkloadPicker(
                                                      workload,
                                                      sourceMinutes:
                                                          workloadSourceMinutes,
                                                    );
                                                if (!context.mounted ||
                                                    !sheetActive) {
                                                  return;
                                                }
                                                if (value != null) {
                                                  workloadSourceMinutes = value;
                                                  workload.text = _compactNumber(
                                                    WorkMinutes.minutesToHours(
                                                      value,
                                                    ),
                                                  );
                                                }
                                                setSheetState(() {});
                                              },
                                              icon: const Icon(
                                                Icons.border_color,
                                              ),
                                            ),
                                          ),
                                          onChanged: (_) {
                                            workloadSourceMinutes = null;
                                            if (workloadError != null ||
                                                saveError != null) {
                                              setSheetState(() {
                                                workloadError = null;
                                                saveError = null;
                                              });
                                            }
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        _QuickWorkloadChips(
                                          onSelected: (minutes) =>
                                              setSheetState(() {
                                                workloadSourceMinutes = minutes;
                                                workload.text = _compactNumber(
                                                  WorkMinutes.minutesToHours(
                                                    minutes,
                                                  ),
                                                );
                                                workloadError = null;
                                                saveError = null;
                                              }),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (wageVisible) ...[
                                  const SizedBox(height: 12),
                                  _RecordSection(
                                    title: '预定时薪',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              ...settings.visibleHourlyRates.map(
                                                (rate) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8,
                                                      ),
                                                  child: ChoiceChip(
                                                    label: Text(
                                                      '¥${rate.toStringAsFixed(2)}',
                                                    ),
                                                    selected:
                                                        !customRate &&
                                                        selectedRate == rate,
                                                    selectedColor: _lightBlue,
                                                    onSelected: (_) =>
                                                        setSheetState(() {
                                                          customRate = false;
                                                          selectedRate = rate;
                                                          rateError = null;
                                                          saveError = null;
                                                        }),
                                                  ),
                                                ),
                                              ),
                                              ChoiceChip(
                                                label: const Text('自定义'),
                                                selected: customRate,
                                                selectedColor: _lightBlue,
                                                onSelected: (_) =>
                                                    setSheetState(() {
                                                      customRate = true;
                                                      rateError = null;
                                                      saveError = null;
                                                    }),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (customRate) ...[
                                          const SizedBox(height: 10),
                                          TextField(
                                            controller: customPrice,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: InputDecoration(
                                              labelText: '自定义时薪',
                                              errorText: rateError,
                                            ),
                                            onChanged: (_) {
                                              if (rateError != null ||
                                                  saveError != null) {
                                                setSheetState(() {
                                                  rateError = null;
                                                  saveError = null;
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _RecordSection(
                                  title: '备注',
                                  child: TextField(
                                    controller: remark,
                                    maxLines: 1,
                                    decoration: const InputDecoration(
                                      hintText: '请输入文本(选填)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.fromLTRB(
                            18,
                            10,
                            18,
                            MediaQuery.of(context).viewInsets.bottom + 18,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: .06),
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (saveError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    saveError!,
                                    semanticsLabel: saveError,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _blue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          final hours = restType
                                              ? 0.0
                                              : workloadSourceMinutes != null
                                              ? WorkMinutes.minutesToHours(
                                                  workloadSourceMinutes!,
                                                )
                                              : double.tryParse(
                                                  workload.text.trim(),
                                                );
                                          final rate = wageVisible
                                              ? (customRate
                                                    ? double.tryParse(
                                                        customPrice.text.trim(),
                                                      )
                                                    : selectedRate)
                                              : 0.0;
                                          final cleanRate = rate == null
                                              ? null
                                              : _normalizeRate(rate);
                                          final invalidWorkload =
                                              !restType &&
                                              (hours == null ||
                                                  !hours.isFinite ||
                                                  hours <= 0 ||
                                                  hours > 24);
                                          final invalidRate =
                                              wageVisible &&
                                              (rate == null ||
                                                  !rate.isFinite ||
                                                  rate <= 0);
                                          if (invalidWorkload || invalidRate) {
                                            setSheetState(() {
                                              workloadError = invalidWorkload
                                                  ? (leaveType
                                                        ? '时长填错了'
                                                        : '工时填错了')
                                                  : null;
                                              rateError = invalidRate
                                                  ? '时薪填错了'
                                                  : null;
                                              saveError = null;
                                            });
                                            return;
                                          }
                                          setSheetState(() {
                                            isSaving = true;
                                            workloadError = null;
                                            rateError = null;
                                            saveError = null;
                                          });
                                          final record = Record(
                                            id: editing
                                                ? editingRecord['id'].toString()
                                                : const Uuid().v4(),
                                            workloadType: selectedWorkType,
                                            workload: hours ?? 0.0,
                                            // unit_price 记本次基准时薪；preset_price 仅在覆盖默认时薪时写入，
                                            // 使读取侧 preset > 0 ? preset : unit 的 fallback 真实可达
                                            unitPrice: cleanRate ?? 0.0,
                                            presetPrice:
                                                (cleanRate ?? 0.0) ==
                                                    settings.defaultHourlyRate
                                                ? 0.0
                                                : cleanRate ?? 0.0,
                                            remark: remark.text.trim(),
                                            date: recordDate,
                                          );
                                          try {
                                            final db = await DatabaseHelper
                                                .instance
                                                .database;
                                            if (editing) {
                                              await db.update(
                                                'record',
                                                record.toMap(),
                                                where: 'id = ?',
                                                whereArgs: [record.id],
                                              );
                                            } else {
                                              await db.insert(
                                                'record',
                                                record.toMap(),
                                              );
                                            }
                                            _store.bump();
                                          } catch (error, stackTrace) {
                                            if (error is FormatException) {
                                              debugPrint(
                                                '保存 FormatException（内部详情）: '
                                                '${error.message}',
                                              );
                                            }
                                            final message = switch (error) {
                                              DatabaseException() =>
                                                '工时保存失败，请重试',
                                              StateError() => '工时保存失败，请重试',
                                              FormatException() =>
                                                '工时保存失败，请重试',
                                              _ => null,
                                            };
                                            if (message == null) {
                                              // 非预期错误：收口为可见错误态+调试日志，
                                              // 不再裸抛进被丢弃的 onPressed Future。
                                              debugPrint(
                                                '工时保存意外错误: '
                                                '$error\n$stackTrace',
                                              );
                                            }
                                            if (!context.mounted ||
                                                !sheetActive) {
                                              return;
                                            }
                                            setSheetState(() {
                                              isSaving = false;
                                              saveError =
                                                  message ?? '工时保存失败，请重试';
                                            });
                                            return;
                                          }
                                          if (!context.mounted ||
                                              !sheetActive) {
                                            return;
                                          }
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          Navigator.pop(context);
                                          if (mounted) {
                                            setState(() {
                                              _selectedDate = recordDate;
                                              _focusedMonth = DateTime(
                                                recordDate.year,
                                                recordDate.month,
                                              );
                                            });
                                          }
                                        },
                                  child: isSaving
                                      ? const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              '正在保存...',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Text(
                                          '保存',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _copyRecordToTomorrow(Map<String, dynamic> record) async {
    final recordDate = DateTime.fromMillisecondsSinceEpoch(
      _asInt(record['date']),
    );
    final target = _dateOnly(recordDate).add(const Duration(days: 1));
    // DB 行→模型统一走 Record.fromMap（NumUtils null→0 兜底、与 toMap 对称），
    // 仅覆写 id（新副本）与 date（目标日）。
    final copy = Record.fromMap({
      ...record,
      'id': const Uuid().v4(),
      'date': target.millisecondsSinceEpoch,
    });
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert('record', copy.toMap());
    } catch (error, stackTrace) {
      _handleExpectedError(
        error,
        stackTrace,
        '工时复制失败，请重试',
        rethrowUnexpected: false,
      );
      return;
    }
    _store.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制到${target.year}年${target.month}月${target.day}日'),
      ),
    );
    setState(() {
      _selectedDate = target;
      _focusedMonth = DateTime(target.year, target.month);
    });
  }

  Future<void> _deleteRecord(String id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('record', where: 'id = ?', whereArgs: [id]);
    } catch (error, stackTrace) {
      _handleExpectedError(
        error,
        stackTrace,
        '工时删除失败，请重试',
        rethrowUnexpected: false,
      );
      return;
    }
    _store.bump();
  }

  Future<void> _confirmDeleteRecord(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除工时'),
        content: const Text('确定删除这条工时记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteRecord(id);
  }

  Future<void> _showSearchSheet() async {
    final query = TextEditingController();
    final searchFocus = FocusNode();
    var results = _searchResults('');
    var sheetActive = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _DisposeOnUnmount(
        onDispose: () {
          sheetActive = false;
          query.dispose();
          searchFocus.dispose();
        },
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '搜索工时',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: query,
                    focusNode: searchFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '输入日期，如 7月3日 或 2026-07-03',
                    ),
                    onChanged: (text) {
                      setSheetState(() {
                        results = _searchResults(text);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '共 ${results.length} 条',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _HistoryList(
                      history: results,
                      onEdit: (record) async {
                        await _showRecordSheet(record);
                        if (!mounted || !context.mounted || !sheetActive) {
                          return;
                        }
                        final history = await _loadHistoryGuarded();
                        if (!mounted ||
                            !context.mounted ||
                            !sheetActive ||
                            history == null) {
                          return;
                        }
                        setSheetState(() {
                          results = _searchResults(
                            query.text,
                            history: history,
                          );
                        });
                      },
                      onDelete: (id) async {
                        await _confirmDeleteRecord(id);
                        if (!mounted || !context.mounted || !sheetActive) {
                          return;
                        }
                        final history = await _loadHistoryGuarded();
                        if (!mounted ||
                            !context.mounted ||
                            !sheetActive ||
                            history == null) {
                          return;
                        }
                        setSheetState(() {
                          results = _searchResults(
                            query.text,
                            history: history,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final cells = _monthCells();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  month: _focusedMonth,
                  onPreviousMonth: () {
                    setState(() {
                      final month = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                      );
                      _focusedMonth = month;
                      _selectedDate = _selectedDateInMonth(
                        month.year,
                        month.month,
                      );
                    });
                  },
                  onNextMonth: () {
                    setState(() {
                      final month = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                      );
                      _focusedMonth = month;
                      _selectedDate = _selectedDateInMonth(
                        month.year,
                        month.month,
                      );
                    });
                  },
                  onSearch: _showSearchSheet,
                  onToday: () {
                    setState(() {
                      _focusedMonth = _now();
                      _selectedDate = _now();
                    });
                  },
                  onMonthTap: _pickDate,
                ),
                const _WeekRow(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 110),
                    child: Column(
                      children: [
                        if (_historyError != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(
                              _historyError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_needsTodayReminder)
                          _TodayReminderBanner(onTap: _recordToday),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: .58,
                              ),
                          itemCount: cells.length,
                          itemBuilder: (context, i) {
                            final date = cells[i];
                            if (date == null) return const SizedBox.shrink();
                            final selected = _sameDay(date, _selectedDate);
                            final weekend = date.weekday >= 6;
                            final records = _recordsForDate(date);
                            return _CalendarDayCell(
                              date: date,
                              selected: selected,
                              weekend: weekend,
                              records: records,
                              settings: settings,
                              onTap: () => setState(() => _selectedDate = date),
                            );
                          },
                        ),
                        Divider(
                          height: 28,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .08),
                        ),
                        _SelectedDatePanel(
                          date: _selectedDate,
                          records: _recordsForDate(_selectedDate),
                          onEdit: _showRecordSheet,
                          onDelete: _confirmDeleteRecord,
                          onCopy: _copyRecordToTomorrow,
                        ),
                        const SizedBox(height: 14),
                        const _ShiftLegend(),
                        if (_history.isNotEmpty)
                          _HistoryList(
                            history: _history,
                            maxItems: 8,
                            onEdit: _showRecordSheet,
                            onDelete: _confirmDeleteRecord,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                            child: Text(
                              '点击下方「记工时」，开始记录今天的工作',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: .6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 40,
              bottom: 32,
              child: SizedBox(
                width: 128,
                height: 64,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _showRecordSheet,
                  child: const Text(
                    '记工时',
                    style: TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSearch,
    required this.onToday,
    required this.onMonthTap,
  });

  final DateTime month;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onSearch;
  final VoidCallback onToday;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      color: _blue,
      padding: const EdgeInsets.fromLTRB(18, 42, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onMonthTap,
              borderRadius: BorderRadius.circular(8),
              child: Semantics(
                button: true,
                label: '${month.year}年${month.month}月，点击选择日期',
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${month.month}',
                        key: const Key('recordMonthTitle'),
                        style: const TextStyle(
                          fontSize: 44,
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '月/${month.year}年',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _HeaderButton(
            icon: Icons.chevron_left,
            tooltip: '上个月',
            onTap: onPreviousMonth,
          ),
          const SizedBox(width: 12),
          _HeaderButton(
            icon: Icons.chevron_right,
            tooltip: '下个月',
            onTap: onNextMonth,
          ),
          const SizedBox(width: 12),
          _HeaderButton(icon: Icons.search, tooltip: '搜索', onTap: onSearch),
          const SizedBox(width: 12),
          _HeaderButton(text: '今', tooltip: '回到今天', onTap: onToday),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    this.icon,
    this.text,
    required this.tooltip,
    required this.onTap,
  });

  final IconData? icon;
  final String? text;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 25)
                : Center(
                    child: Text(
                      text!,
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TodayReminderBanner extends StatelessWidget {
  const _TodayReminderBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.edit_calendar,
                  color: scheme.onTertiaryContainer,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今天还没记录工时',
                    style: TextStyle(
                      fontSize: 16,
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '去记工时',
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow();

  @override
  Widget build(BuildContext context) {
    const items = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      height: 48,
      color: _blue.withValues(alpha: .9),
      child: Row(
        children: items
            .map(
              (e) => Expanded(
                child: Center(
                  child: Text(
                    e,
                    style: TextStyle(
                      fontSize: 20,
                      color: (e == '六' || e == '日')
                          ? const Color(0xFFD32F2F)
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.selected,
    required this.weekend,
    required this.records,
    required this.settings,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool weekend;
  final List<Map<String, dynamic>> records;
  final AppSettingsController settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final dayColor = weekend ? const Color(0xFFD32F2F) : textColor;
    final hasRecords = records.isNotEmpty;
    return Semantics(
      button: true,
      selected: selected,
      label: '${date.month}月${date.day}日',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: selected ? _lightBlue.withValues(alpha: .10) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? _lightBlue
                  : (hasRecords
                        ? Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .08)
                        : Colors.transparent),
              width: selected || hasRecords ? 1.6 : 1,
            ),
          ),
          child: Stack(
            children: [
              if (hasRecords)
                Positioned.fill(
                  child: _RecordRatioSegments(
                    records: records,
                    settings: settings,
                    alpha: selected ? .86 : .76,
                  ),
                ),
              Positioned(
                top: 2,
                left: 3,
                right: 2,
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 25,
                          height: 1,
                          color: dayColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 1),
                      Container(
                        width: 1,
                        height: 27,
                        color: dayColor.withValues(alpha: .5),
                      ),
                      const SizedBox(width: 1),
                      SizedBox(
                        width: 16,
                        child: Text(
                          LunarFormatter.dayLabel(date),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.05,
                            color: dayColor.withValues(alpha: .76),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 2,
                right: 2,
                bottom: 2,
                height: 44,
                child: _DayWorkBlocks(records: records, settings: settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayWorkBlocks extends StatelessWidget {
  const _DayWorkBlocks({required this.records, required this.settings});

  final List<Map<String, dynamic>> records;
  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final totalHours = records.fold<double>(
      0,
      (sum, record) => sum + _asDouble(record['workload']),
    );
    final label = totalHours > 0
        ? _formatWorkload(totalHours)
        : settings.labelForWorkType(_asInt(records.first['workload_type']));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (records.isNotEmpty)
            _RecordRatioSegments(
              records: records,
              settings: settings,
              alpha: .98,
            ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRatioSegments extends StatelessWidget {
  const _RecordRatioSegments({
    required this.records,
    required this.settings,
    required this.alpha,
  });

  final List<Map<String, dynamic>> records;
  final AppSettingsController settings;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: records
          .map((record) {
            final hours = _asDouble(record['workload']);
            final flex = hours > 0 ? (hours * 20).round().clamp(1, 240) : 1;
            return Expanded(
              flex: flex,
              child: ColoredBox(
                color: settings
                    .colorForWorkType(_asInt(record['workload_type']))
                    .withValues(alpha: alpha),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Divider(height: 18),
          child,
        ],
      ),
    );
  }
}

class _WorkTypeGrid extends StatelessWidget {
  const _WorkTypeGrid({required this.selectedId, required this.onChanged});

  final int selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: workTypeOptions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 2.15,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final type = workTypeOptions[index];
        final selected = selectedId == type.id;
        return InkWell(
          onTap: () => onChanged(type.id),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? _lightBlue : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? _lightBlue
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .08),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _lightBlue.withValues(alpha: .28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ShiftIcon(typeId: type.id, selected: selected),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      type.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 17,
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShiftIcon extends StatelessWidget {
  const _ShiftIcon({required this.typeId, required this.selected});

  final int typeId;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final iconColor = switch (typeId) {
      0 => const Color(0xFFFFC64A),
      1 => const Color(0xFF5F48D6),
      2 => const Color(0xFFFFB43D),
      3 => const Color(0xFFFFC45F),
      4 => const Color(0xFFFF5742),
      5 => const Color(0xFF33207E),
      6 => const Color(0xFF27CDC2),
      7 => const Color(0xFF16BE73),
      _ => _blue,
    };
    if (isNonWork(typeId)) {
      return Container(
        width: 25,
        height: 25,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
        child: Text(
          typeId == kTypeIdLeave ? '请' : '休',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    final icon = switch (typeId) {
      0 => Icons.wb_sunny,
      1 => Icons.nightlight_round,
      2 => Icons.wb_twilight,
      3 => Icons.wb_sunny_outlined,
      4 => Icons.brightness_3,
      5 => Icons.more_time,
      _ => Icons.circle,
    };
    return Icon(
      icon,
      size: typeId == 0 ? 28 : 25,
      color: selected ? Colors.white : iconColor,
    );
  }
}

class _QuickWorkloadChips extends StatelessWidget {
  const _QuickWorkloadChips({required this.onSelected});

  /// 回调直接透出选项的整数分钟源，不在屏层做分钟→小时截断。
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final presets = context
        .watch<AppSettingsController>()
        .visibleWorkloadQuickOptions;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets
            .map(
              (option) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(option.label),
                  onPressed: () => onSelected(option.minutes),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WorkloadQuickPicker extends StatefulWidget {
  const _WorkloadQuickPicker({required this.initialMinutes});

  /// 回填与确认均以整数分钟为源。
  final int initialMinutes;

  @override
  State<_WorkloadQuickPicker> createState() => _WorkloadQuickPickerState();
}

class _WorkloadQuickPickerState extends State<_WorkloadQuickPicker> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = (widget.initialMinutes ~/ 60).clamp(0, 23);
    _minute = (widget.initialMinutes % 60 ~/ 5 * 5).clamp(0, 55);
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _hour * 60 + _minute;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '工时：${WorkMinutes.hoursTextFromMinutes(minutes)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('时', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            _NumberPickerGrid(
              values: List<int>.generate(24, (index) => index),
              selected: _hour,
              onSelected: (value) => setState(() => _hour = value),
            ),
            const SizedBox(height: 12),
            const Text('分', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            _NumberPickerGrid(
              values: List<int>.generate(12, (index) => index * 5),
              selected: _minute,
              onSelected: (value) => setState(() => _minute = value),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _blue),
                  onPressed: () => Navigator.pop(context, minutes),
                  child: const Text(
                    '确认',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberPickerGrid extends StatelessWidget {
  const _NumberPickerGrid({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<int> values;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        childAspectRatio: 1.55,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final value = values[index];
        final picked = value == selected;
        return InkWell(
          onTap: () => onSelected(value),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: picked ? _blue : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .05),
              ),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(
                fontSize: 17,
                color: picked ? Colors.white : null,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectedDatePanel extends StatelessWidget {
  const _SelectedDatePanel({
    required this.date,
    required this.records,
    required this.onEdit,
    required this.onDelete,
    this.onCopy,
  });

  final DateTime date;
  final List<Map<String, dynamic>> records;
  final Future<void> Function(Map<String, dynamic> record) onEdit;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function(Map<String, dynamic> record)? onCopy;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final settings = context.watch<AppSettingsController>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${date.month}月${date.day}日  ${LunarFormatter.fullLabel(date)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            Text(
              '暂无工时记录',
              style: TextStyle(
                fontSize: 16,
                color: textColor.withValues(alpha: .6),
              ),
            )
          else
            ...records.map((record) {
              final type = _asInt(record['workload_type']);
              final price = _effectiveRate(record);
              final hours = _asDouble(record['workload']);
              final remark = record['remark']?.toString().trim() ?? '';
              final workloadText = hours > 0
                  ? '  ${_formatWorkload(hours)}'
                  : '';
              final priceText = price > 0
                  ? '时薪 ${price.toStringAsFixed(1)}'
                  : '不计工资';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 10,
                  height: 34,
                  color: settings.colorForWorkType(type),
                ),
                title: Text('${settings.labelForWorkType(type)}$workloadText'),
                subtitle: Text(
                  remark.isEmpty ? priceText : '$priceText  $remark',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _RecordActions(
                  onEdit: () => onEdit(record),
                  onDelete: () => onDelete(record['id'].toString()),
                  onCopy: onCopy == null ? null : () => onCopy!(record),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _RecordActions extends StatelessWidget {
  const _RecordActions({
    required this.onEdit,
    required this.onDelete,
    this.onCopy,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
          ),
          onPressed: onEdit,
          child: const Text('修改'),
        ),
        const SizedBox(width: 12),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFD32F2F),
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
          ),
          onPressed: onDelete,
          child: const Text('删除'),
        ),
        if (onCopy != null) ...[
          const SizedBox(width: 12),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
            ),
            onPressed: onCopy,
            child: const Text('复制'),
          ),
        ],
      ],
    );
  }
}

class _ShiftLegend extends StatelessWidget {
  const _ShiftLegend();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          ...workTypeOptions.map(
            (type) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 18,
                  color: settings.colorForWorkType(type.id),
                ),
                const SizedBox(width: 4),
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.onEdit,
    required this.onDelete,
    this.maxItems,
  });

  final List<Map<String, dynamic>> history;
  final Future<void> Function(Map<String, dynamic> record) onEdit;
  final Future<void> Function(String id) onDelete;

  /// 展示条数上限；null 表示全部展示（搜索弹层用，避免结果丢数据）。
  final int? maxItems;

  Iterable<Map<String, dynamic>> get _visibleItems =>
      maxItems == null ? history : history.take(maxItems!);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '历史打卡',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ..._visibleItems.map((r) {
            final d = DateTime.fromMillisecondsSinceEpoch(_asInt(r['date']));
            final price = _effectiveRate(r);
            final total = _asDouble(r['workload']) * price;
            final type = _asInt(r['workload_type']);
            final remark = r['remark']?.toString().trim() ?? '';
            final hours = _asDouble(r['workload']);
            final workloadText = hours > 0 ? _formatWorkload(hours) : '不计时';
            return Card(
              elevation: 0,
              color: Theme.of(context).cardColor,
              child: ListTile(
                leading: Container(
                  width: 8,
                  height: 42,
                  color: settings.colorForWorkType(type),
                ),
                title: Text(
                  '${d.month}月${d.day}日  ${settings.labelForWorkType(type)}  $workloadText',
                ),
                subtitle: Text(
                  remark.isEmpty
                      ? '时薪 ${price.toStringAsFixed(1)}  小计 ${total.toStringAsFixed(1)}'
                      : '时薪 ${price.toStringAsFixed(1)}  小计 ${total.toStringAsFixed(1)}  $remark',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _RecordActions(
                  onEdit: () => onEdit(r),
                  onDelete: () => onDelete(r['id'].toString()),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 弹层退出动画期间仍会被重建，controller 必须等到弹层子树
/// 真正卸载时才销毁；await showModalBottomSheet 返回时动画尚未结束。
class _DisposeOnUnmount extends StatefulWidget {
  const _DisposeOnUnmount({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<_DisposeOnUnmount> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
