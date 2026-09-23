import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  static const int _dailyReminderId = 21001;
  static const int _previewId = 21002;
  static const String _channelId = 'work_helper_daily_reminder';
  static const String _channelName = '工时提醒';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_localTimezoneName()));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            true;
      }
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> scheduleDaily({required int hour, required int minute}) async {
    await initialize();
    final granted = await requestPermission();
    if (!granted) return false;
    await cancelDaily();
    await _plugin.zonedSchedule(
      _dailyReminderId,
      '记得记录今天工时',
      '打开记工时，补上今天的工时和待办。',
      nextTriggerAt(tz.TZDateTime.now(tz.local), hour, minute),
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  Future<void> cancelDaily() async {
    await initialize();
    await _plugin.cancel(_dailyReminderId);
    await _plugin.cancel(_previewId);
  }

  Future<bool> showReminderPreview() async {
    await initialize();
    final granted = await requestPermission();
    if (!granted) return false;
    await _plugin.show(
      _previewId,
      '提醒已启用',
      '记工时提醒：别忘了记录今天的工时。',
      _notificationDetails(),
    );
    return true;
  }

  NotificationDetails _notificationDetails() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '每天提醒记录工时',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.reminder,
    );
    const ios = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: ios);
  }

  // 按本机 UTC 偏移匹配 tz 数据库位置；未覆盖的偏移回落到上海（本产品面向国内用户）
  // DST 区的偏移会随时节变化，反查结果可能偏差 1 小时；
  // 海外用户后续接 flutter_timezone 取真实 IANA 名（面向国内已声明的权衡，不改行为）。
  static String _localTimezoneName() {
    const byOffsetMinutes = {
      -660: 'Pacific/Midway',
      -600: 'Pacific/Honolulu',
      -540: 'America/Anchorage',
      -480: 'America/Los_Angeles',
      -420: 'America/Denver',
      -360: 'America/Chicago',
      -300: 'America/New_York',
      -240: 'America/Santiago',
      -180: 'America/Sao_Paulo',
      -120: 'America/Noronha',
      -60: 'Atlantic/Azores',
      0: 'Europe/London',
      60: 'Europe/Berlin',
      120: 'Europe/Athens',
      180: 'Europe/Moscow',
      210: 'Asia/Tehran',
      240: 'Asia/Dubai',
      270: 'Asia/Kabul',
      300: 'Asia/Karachi',
      330: 'Asia/Kolkata',
      345: 'Asia/Kathmandu',
      360: 'Asia/Dhaka',
      390: 'Asia/Yangon',
      420: 'Asia/Bangkok',
      480: 'Asia/Shanghai',
      540: 'Asia/Tokyo',
      570: 'Australia/Darwin',
      600: 'Australia/Sydney',
      660: 'Pacific/Noumea',
      720: 'Pacific/Auckland',
      780: 'Pacific/Tongatapu',
      840: 'Pacific/Kiritimati',
    };
    return byOffsetMinutes[DateTime.now().timeZoneOffset.inMinutes] ??
        'Asia/Shanghai';
  }

  /// 下一次每日触发时刻：今天到点前 → 今天，否则顺延到明天。
  /// now 可注入的纯逻辑，单测不依赖真钟。返回 [tz.TZDateTime] 是因为
  /// zonedSchedule 只接受 TZDateTime；语义上即 prompt 约定的 DateTime 计算。
  @visibleForTesting
  static tz.TZDateTime nextTriggerAt(DateTime now, int hour, int minute) {
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
