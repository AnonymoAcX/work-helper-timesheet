import 'package:work_helper/utils/num_utils.dart';

class Record {
  final String id;
  final int workloadType;
  final double workload;
  final double unitPrice;
  final double presetPrice; // 预定时薪
  final String remark;
  final DateTime date;

  Record({
    required this.id,
    required this.workloadType,
    required this.workload,
    required this.unitPrice,
    this.presetPrice = 0.0,
    this.remark = '',
    required this.date,
  });

  /// DB 行 → 模型：缺失/病态值一律经 NumUtils 兜底 0，字段与 [toMap] 对称。
  factory Record.fromMap(Map<String, dynamic> map) {
    return Record(
      id: map['id']?.toString() ?? '',
      workloadType: NumUtils.asInt(map['workload_type']),
      workload: NumUtils.asDouble(map['workload']),
      unitPrice: NumUtils.asDouble(map['unit_price']),
      presetPrice: NumUtils.asDouble(map['preset_price']),
      remark: map['remark']?.toString() ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(NumUtils.asInt(map['date'])),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workload_type': workloadType,
      'workload': workload,
      'unit_price': unitPrice,
      'preset_price': presetPrice,
      'remark': remark,
      'date': date.millisecondsSinceEpoch,
    };
  }
}
