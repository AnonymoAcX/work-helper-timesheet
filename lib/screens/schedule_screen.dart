import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:work_helper/data/db/database_helper.dart';
import 'package:work_helper/controllers/data_store.dart';
import 'package:work_helper/theme/app_colors.dart';
import 'package:work_helper/utils/lunar_formatter.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, @visibleForTesting this.initialDate});

  @visibleForTesting
  final DateTime? initialDate;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _selectedDate;
  List<Map<String, dynamic>> _todos = [];
  int _todoRequest = 0;
  final Set<String> _todoPendingIds = {};
  bool _todoLoading = false;
  String? _todoError;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    DataStore.instance.addListener(_reloadAfterRestore);
    _loadTodos();
  }

  @override
  void dispose() {
    DataStore.instance.removeListener(_reloadAfterRestore);
    super.dispose();
  }

  void _reloadAfterRestore() => _loadTodos();

  Future<bool> _loadTodos({bool showError = true}) async {
    final request = ++_todoRequest;
    if (mounted) {
      setState(() {
        _todoLoading = true;
        if (showError) _todoError = null;
      });
    }
    try {
      final todos = await DatabaseHelper.instance.todosForDate(_selectedDate);
      if (!mounted || request != _todoRequest) return false;
      setState(() {
        _todos = todos;
        _todoLoading = false;
        _todoError = null;
      });
      return true;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('待办加载失败'),
        ),
      );
      if (mounted && request == _todoRequest) {
        setState(() {
          _todoLoading = false;
          if (showError) _todoError = '加载待办失败，请重试';
        });
      }
      return false;
    }
  }

  Future<void> _showAddTodoSheet() async {
    final title = TextEditingController();
    final remark = TextEditingController();
    final titleFocus = FocusNode();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (dialogContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 22,
              bottom: MediaQuery.of(context).viewInsets.bottom + 22,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加待办  ${_selectedDate.month}月${_selectedDate.day}日',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: title,
                  focusNode: titleFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  onChanged: (_) {
                    if (error != null) setDialogState(() => error = null);
                  },
                  decoration: InputDecoration(
                    labelText: '待办内容',
                    errorText: error,
                  ),
                ),
                TextField(
                  controller: remark,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: const InputDecoration(labelText: '备注（可选）'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final text = title.text.trim();
                            if (text.isEmpty) {
                              setDialogState(() => error = '待办内容不能为空');
                              titleFocus.requestFocus();
                              return;
                            }
                            setDialogState(() => saving = true);
                            try {
                              await DatabaseHelper.instance.insertTodo({
                                'id': const Uuid().v4(),
                                'title': text,
                                'remark': remark.text.trim(),
                                'date': DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day,
                                ).millisecondsSinceEpoch,
                                'created_at':
                                    DateTime.now().millisecondsSinceEpoch,
                              });
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              await _loadTodos();
                            } on DatabaseException catch (exception, stackTrace) {
                              FlutterError.reportError(
                                FlutterErrorDetails(
                                  exception: exception,
                                  stack: stackTrace,
                                  context: ErrorDescription('日程待办保存失败'),
                                ),
                              );
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  saving = false;
                                  error = '保存失败，请重试';
                                });
                                titleFocus.requestFocus();
                              }
                            } catch (error, stackTrace) {
                              if (dialogContext.mounted) {
                                setDialogState(() => saving = false);
                              }
                              Error.throwWithStackTrace(error, stackTrace);
                            }
                          },
                    child: saving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                '保存中…',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            '保存',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    title.dispose();
    remark.dispose();
    titleFocus.dispose();
  }

  Future<void> _deleteTodo(String id) async {
    if (!_todoPendingIds.add(id)) return;
    setState(() {});
    try {
      await DatabaseHelper.instance.deleteTodo(id);
      if (!await _loadTodos(showError: false) && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除已完成，但列表刷新失败，请重试')));
      }
    } on DatabaseException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('日程待办删除失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除待办失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _todoPendingIds.remove(id));
    }
  }

  Future<void> _toggleTodoDone(String id, bool done) async {
    if (!_todoPendingIds.add(id)) return;
    setState(() {});
    try {
      await DatabaseHelper.instance.updateTodoDone(id, done);
      if (!await _loadTodos(showError: false) && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新已完成，但列表刷新失败，请重试')));
      }
    } on DatabaseException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('日程待办更新失败'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新待办失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _todoPendingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = _shiftDays(_selectedDate, 1 - _selectedDate.weekday);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 128,
                  color: AppColors.blue,
                  padding: const EdgeInsets.fromLTRB(18, 42, 18, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_selectedDate.month}',
                                key: const Key('scheduleMonthTitle'),
                                style: const TextStyle(
                                  fontSize: 42,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '月/${_selectedDate.year}年',
                                style: const TextStyle(
                                  fontSize: 19,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 76,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '待 办',
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '回到今天',
                        child: Semantics(
                          button: true,
                          label: '回到今天',
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedDate = DateTime.now());
                              _loadTodos();
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '今',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 44,
                  color: AppColors.blue.withValues(alpha: .9),
                  child: const Row(
                    children: [
                      _Week('一'),
                      _Week('二'),
                      _Week('三'),
                      _Week('四'),
                      _Week('五'),
                      _Week('六', red: true),
                      _Week('日', red: true),
                    ],
                  ),
                ),
                SizedBox(
                  height: 76,
                  child: Row(
                    children: List.generate(7, (i) {
                      final date = _shiftDays(weekStart, i);
                      final selected =
                          date.year == _selectedDate.year &&
                          date.month == _selectedDate.month &&
                          date.day == _selectedDate.day;
                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedDate = date);
                            _loadTodos();
                          },
                          child: Container(
                            height: selected ? 68 : 58,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.lightBlue
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 21,
                                    color: selected
                                        ? Colors.white
                                        : (date.weekday >= 6
                                              ? const Color(0xFFD32F2F)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  LunarFormatter.dayLabel(date),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? Colors.white
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: .62),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: _todoLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _todoError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_todoError!),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loadTodos,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : _todos.isEmpty
                      ? Center(
                          child: Text(
                            '没有待办事项',
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: .55),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                          itemCount: _todos.length,
                          itemBuilder: (context, index) {
                            final todo = _todos[index];
                            final id = todo['id'].toString();
                            final pending = _todoPendingIds.contains(id);
                            final done = todo['done'] == 1;
                            final textColor = Theme.of(
                              context,
                            ).colorScheme.onSurface;
                            return Card(
                              elevation: 0,
                              color: Theme.of(context).cardColor,
                              child: ListTile(
                                leading: Semantics(
                                  button: true,
                                  label: done ? '取消完成' : '标记完成',
                                  child: InkWell(
                                    onTap: pending
                                        ? null
                                        : () => _toggleTodoDone(id, !done),
                                    customBorder: const CircleBorder(),
                                    child: SizedBox.square(
                                      dimension: 48,
                                      child: Icon(
                                        pending
                                            ? Icons.hourglass_top
                                            : done
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        size: 26,
                                        color: done
                                            ? AppColors.blue
                                            : textColor.withValues(alpha: .55),
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  todo['title']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: done
                                        ? textColor.withValues(alpha: .45)
                                        : null,
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle:
                                    (todo['remark']?.toString().isNotEmpty ??
                                        false)
                                    ? Text(
                                        todo['remark'].toString(),
                                        style: TextStyle(
                                          color: done
                                              ? textColor.withValues(alpha: .45)
                                              : null,
                                        ),
                                      )
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除待办',
                                  onPressed: pending
                                      ? null
                                      : () => _deleteTodo(id),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            Positioned(
              right: 40,
              bottom: 24,
              child: SizedBox(
                width: 118,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _showAddTodoSheet,
                  child: const Text(
                    '添加待办',
                    style: TextStyle(fontSize: 18, color: Colors.white),
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

/// 日历分量制天偏移（L-24）：`Duration(days: n)` 按 24h 定步长，DST 跳零时
/// 会偏一天；`DateTime` 分量构造跨月自动归一且不受夏令时影响。
DateTime _shiftDays(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day + days);

class _Week extends StatelessWidget {
  const _Week(this.text, {this.red = false});
  final String text;
  final bool red;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          height: 1.0,
          color: red ? const Color(0xFFD32F2F) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
