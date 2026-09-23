import 'package:flutter/foundation.dart';

/// 业务数据版本号（轻量 ChangeNotifier 单例）。
/// record 增删改、复制到明天、importAll 恢复、考勤周期变更等
/// 成功写库后调用 [bump]；IndexedStack 保活的 RecordScreen /
/// SalaryScreen 监听并在数据变化后重新加载。
/// todo 写点不 bump：ScheduleScreen 自身写入后即行内刷新待办。
/// 但 ScheduleScreen 注册了 [bump] 监听并重查当日待办，
/// 备份恢复、考勤周期变更后的待办刷新依赖该监听。
class DataStore extends ChangeNotifier {
  DataStore._();

  static final DataStore instance = DataStore._();

  int _version = 0;

  int get version => _version;

  void bump() {
    _version++;
    notifyListeners();
  }
}
