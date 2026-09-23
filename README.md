# 记工时（work_helper）

「记工时」是一款基于 Flutter 开发的单机个人工时记录应用，面向按工时、班次计薪的劳动者，提供工时登记、待办清单、薪资统计与提醒等服务。数据保存在本机，不需要登录，不提供云同步，也不会读取系统日历。

## 功能概览

- **工时记录**：登记每日上班时间、加班时长与预定时薪，支持农历日期显示，随时回溯历史记录。
- **待办清单**：按日期添加待办事项，支持备注、完成标记与删除，随手记下当天要做的事。
- **薪资统计**：按时薪与工时自动汇总应得收入，提供统计视图，辅助核对工资。
- **提醒通知**：支持本地提醒设置，每天定时提醒补记当天工时与待办。
- **本地日历**：按日期查看本地工时记录与农历日期，支持翻月和历史回溯；应用只使用自己的日期视图。
- **个性化设置**：主题明暗切换、时薪标准、考勤周期、工时颜色和提醒开关可自定义。
- **工作量快捷项**：自定义记工时页面的快捷时长，可添加、编辑、排序、隐藏和删除；只影响快捷按钮，不会修改已有记录。
- **备份与恢复**：备份工时记录、待办、昵称、考勤周期、时薪、颜色、主题、提醒和工作量快捷项；恢复支持旧版备份格式，校验通过后整体替换本地数据。

## 技术栈

- 框架：Flutter（Dart SDK ^3.9.2、Flutter >=3.27.0），当前目标平台为 Android
- 状态管理：provider（^6.1.2）
- 本地存储：sqflite（^2.4.1）SQLite 数据库 + shared_preferences（^2.5.2）+ path_provider（^2.1.5）
- 日历与农历：lunar（^1.7.8）
- 本地通知：flutter_local_notifications（^18.0.1）、timezone（^0.10.1）
- 其它：share_plus（^10.1.4）、uuid（^4.5.1）、intl（^0.20.2）、path（^1.9.1）
- 依赖来源：全部依赖按版本范围取自 pub.dev 或 Flutter SDK（flutter、flutter_localizations 等），无本地 path 依赖

## 项目结构

```text
lib/
├── main.dart                              # 应用入口、主题与底部导航（工时/待办/统计/个人）
├── controllers/
│   ├── app_settings_controller.dart       # 全局应用设置状态管理
│   └── data_store.dart                    # 业务数据变更版本号，驱动页面数据重载
├── data/
│   └── db/
│       └── database_helper.dart           # SQLite 建库建表（本机设置、工时记录、待办）与数据访问
├── models/
│   ├── record.dart                        # 工时记录模型（含预定时薪）
├── screens/
│   ├── record_screen.dart                 # 工时首页
│   ├── schedule_screen.dart               # 待办清单页（按日期管理待办）
│   ├── salary_screen.dart                 # 薪资统计
│   ├── settings_screen.dart               # 个人中心与设置入口
│   ├── attendance_cycle_screen.dart       # 考勤周期设置
│   ├── hourly_rate_settings_screen.dart   # 时薪设置
│   ├── work_color_settings_screen.dart    # 班次颜色设置
│   ├── workload_quick_options_screen.dart # 工作量快捷项设置
│   ├── theme_settings_screen.dart         # 主题设置
│   └── reminder_settings_screen.dart      # 提醒设置
├── services/
│   └── reminder_notification_service.dart # 本地通知提醒
├── theme/
│   └── app_colors.dart                    # 全局颜色常量统一源
├── utils/
│   ├── lunar_formatter.dart               # 农历日期格式化
│   ├── money.dart                         # 金额与工时精确换算（分/分钟整数口径）
│   └── num_utils.dart                     # 数值安全解析
└── widgets/
    └── app_header.dart                    # 共享页面顶栏组件
```

## 运行方式

本项目为标准 Flutter 工程。运行前需自备 Flutter SDK：本机已安装的 Flutter 满足 `pubspec.yaml` 约束（Dart ^3.9.2、Flutter >=3.27.0）即可，仓库不内置 SDK。

```bash
# 安装依赖
flutter pub get

# 连接设备或启动模拟器后运行
flutter run

# 构建发布包（以 Android 为例）
flutter build apk --release
```

运行单元测试：

```bash
flutter test
```

## 界面预览方式

改界面之前，可通过以下方式先看到效果，适用于不同场景。

### HTML 设计稿预览

用网页形式呈现界面设计稿，在电脑上即可查看，零成本，也不需要手机。

- **适合场景**：大幅改版前先确认整体方向，比如页面怎么布局、几种风格选哪种。
- **使用方式**：设计稿页面直接在浏览器中打开；候选方案可点选，点中哪个就针对哪个给出反馈。
- **局限**：设计稿是静态示意图，不是应用里的真实控件，看不到实际的点击、滑动等交互效果。

### 浏览器运行预览

Flutter Web 浏览器运行预览处于规划阶段，尚未实施，工程当前仅含 Android 平台目录；实施规格见 `docs/plan-浏览器预览与图层索引面板.md`。在此之前，界面效果以 HTML 设计稿预览和真机测试为准。

### 真机测试

界面最终效果仍以手机真机为准：安装 release APK（正式打包的安装包）到手机上实际使用。

## 发布与分发

本项目开源，安装包通过 GitHub Releases 等渠道分发。Android 要求每个应用都携带签名，签名身份决定旧版本能否直接升级：同一构建机产出的安装包签名一致，接收方可直接覆盖安装，本机数据不丢。命令均在 Windows PowerShell 中、于项目根目录执行。

### 构建正式安装包

```powershell
flutter build apk --release
```

构建成功后，安装包位于 `build\app\outputs\flutter-apk\app-release.apk`。如要生成上传应用商店用的 App Bundle，执行 `flutter build appbundle --release`，`.aab` 产物的完整路径以构建结束时终端打印的提示为准。

### 签名说明

本工程的 release 构建类型直接采用调试签名（见 `android\app\build.gradle.kts` 中 release 的 `signingConfig`），对开源个人分发足够。Android 调试签名由构建机自身固定维护，同一台机器每次构建产出的签名相同：老用户拿到新版本安装包直接覆盖安装即可升级到新版本，应用内的工时数据、待办和设置全部保留。官方发布固定在发布机上构建，即可保证所有已分发版本的签名一致。

### 发给他人安装

把 `app-release.apk` 上传到 GitHub Releases，或通过聊天文件等方式直接发给对方。接收方在手机上点开文件即可安装；首次从这类渠道安装时，系统会提示禁止安装未知来源应用，按弹窗指引授予该来源的安装权限后继续。接收方手机系统需为 Android 7.0 及以上（工程配置的最低支持版本为 API 24）。

### 升级提醒

若接收方安装过与本包签名不同的历史版本（例如早期在别的机器上构建的包），覆盖安装会被系统拒绝，需先卸载旧版再装新版。卸载会清空应用内数据，操作前先在应用内用「备份数据」导出备份，装好新版后用「恢复数据 → 从文件管理器选择…」导入该备份即可。
