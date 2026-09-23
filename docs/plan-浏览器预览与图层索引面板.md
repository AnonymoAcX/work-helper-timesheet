# 浏览器预览与图层索引面板实施规格

本文是浏览器预览与图层索引面板的实施规格，所有技术决策均已锁定，实施时按本文执行，不增删决策。项目为 Flutter 应用（现有目标平台为 Android，iOS 平台目录已从开源仓排除；功能覆盖工时记录、待办、工资计算与提醒设置）。

## 目标与边界

三个目标：

1. **Flutter Web 浏览器预览**：应用直接在浏览器中运行，数据由内存假数据支撑，不依赖手机，也不依赖打包。
2. **可点击图层索引面板**：点击任意控件即显示组件名与层级链；源文件与行号由 DevTools 提供（见「图层索引面板」）。
3. **保留零成本 HTML 设计稿预览**：该方式已存在，见 README「界面预览方式 → HTML 设计稿预览」，本方案不改动它。

边界（硬约束）：

- 不做生产 web 版，仅服务设计预览。
- Android 行为零变化。
- 不升级任何依赖的大版本。

## 现状事实

- SDK：使用开发机上安装的 Flutter，版本为 Flutter 3.47.1 stable（Dart 3.13.1，2026-08-19）。
- 该 SDK 的 web 平台支持默认全开，无需执行 `flutter config`。
- 开发机已缓存 `flutter_web_sdk/canvaskit`，离线运行风险低。
- 工程当前没有 `web/` 目录；`.metadata` 的 `migration.platforms` 仅含 root、android、ios。
- 补平台命令只新建 `web/` 目录与 `.metadata` 条目，不改动 `lib/` 与 `android/`：

```bash
flutter create . --platforms web
```

## 依赖兼容性

版本为当前锁定版本。「编译」指能否通过 dart2js/DDC 编译，「运行」指 web 上的实际行为。

| 依赖 | 版本 | Web 编译与运行 | 处置 |
| --- | --- | --- | --- |
| shared_preferences | 2.5.5 | 直接可用，以 localStorage 实现 | `AppSettingsController` 零改动 |
| timezone、intl、lunar、uuid、provider、path、flutter_localizations | 0.10.1、0.20.3 等 | 纯 Dart 或官方支持 | 无改动 |
| sqflite | 2.4.2 | 可编译；web 运行时 `databaseFactory` 抛 `StateError`（无 web 注册实现） | 必须用假数据层隔离；禁止引入 sqflite_common_ffi_web |
| path_provider | 2.1.5 | 主库 import `dart:io`，web 编译失败 | 必须用条件导入隔离 |
| flutter_local_notifications | 18.0.1 | 可编译；web 调用抛 `MissingPluginException`。服务内 `initialize()`、`requestPermission()` 已有 `kIsWeb` 守卫；缺口：`cancelDaily()`（reminder_notification_service.dart:83-87）被 `reminder_settings_screen.dart` 的 `_setEnabled()`（:29）与 `_restoreNotification()`（:156）直调 | 补 1 行 `kIsWeb` 守卫；禁止为预览升级 v22 |
| share_plus | 10.1.4 | web 可用（`navigator.canShare`/`navigator.share`；失败回退浏览器下载；localhost 满足安全上下文要求） | 调用侧 `XFile(file.path)` 的 io 路径来源必须换成字节内容 |
| 项目自身代码 | — | salary_screen.dart:2、settings_screen.dart:2 直接 import `dart:io` 并使用 `File`/`dir.listSync`，web 编译必败 | 必须下沉到平台文件网关（见改动清单第 6 条） |

## 改动清单

### 1. 新增 `lib/data/db/app_database.dart`：数据库抽象接口

定义 `abstract class AppDatabase`，成员分两部分：`DatabaseHelper` 现有 12 个公开方法（不含 `@visibleForTesting` 测试钩子 `resetForTest`）（`calculateMonthlySalary`、`updateUserName`、`updateCalculateDay`、`getUserName`、`getCalculateDay`、`recordsForMonth`、`todosForDate`、`insertTodo`、`deleteTodo`、`updateTodoDone`、`exportAll`、`importAll`），以及本计划新增的 4 个门面方法（`allRecords`、`upsertRecord`、`insertRecord`、`deleteRecordById`），后者用于收编 `record_screen.dart` 现有 4 处绕过门面的直连调用（见改动清单第 5 条）。接口中不出现任何 sqflite 类型；另新增 `static AppDatabase instance` 可替换持有者，供全局切换实现。

### 2. 现有 `DatabaseHelper` 转为 sqflite 实现

`DatabaseHelper` 改为 `SqfliteDatabaseHelper implements AppDatabase`。内部 SQL 原样保留；公开的 `database` getter 删除，或转为仅 io 侧可见的私有成员。

### 3. 新增 `lib/data/db/memory_database.dart`：内存假数据实现

`MemoryDatabase implements AppDatabase`，纯 Dart 实现：以 `List<Map<String, dynamic>>` 行模型，与 record、todo、user 三表同构，并保持与 `importAll` 相同的 schemaVersion/校验语义。提供 `seed()` 造近 60 天示例工时、待办与用户名，让预览有真实观感。该文件不 import 任何插件。

### 4. `lib/main.dart` 条件装配

在 `WidgetsFlutterBinding.ensureInitialized()` 之后加入一行：

```dart
if (kIsWeb) AppDatabase.instance = MemoryDatabase()..seed();
```

默认实现仍为 sqflite 版本，Android 行为逐字节不变。不新增 `main_web.dart`，一个 `kIsWeb` 赋值即可。

### 5. `record_screen.dart` 直连改走门面

4 处绕过门面的直连数据库调用改为门面方法（行为等价重构：同表、同 where、同数据）。下列行号为当前磁盘真值，符号为主、行号为辅；因并行改动漂移时以符号定位为准：

- `_loadHistory()` 内 `:192-193`：全量 query
- `_showRecordSheet()` 内 `:735-750`：保存 update/insert（取 db 句柄起于 `:735-737`，update `:739`、insert `:746`）
- `_copyRecordToTomorrow()` 内 `:863-864`：「复制到明天」insert
- `_deleteRecord()` 内 `:889-890`：delete

### 6. 新增 `lib/services/platform_files.dart`：平台文件网关

接口包含两个成员：

- `shareBytes(String filename, Uint8List content, {text, subject})`：web 实现用 `XFile.fromData` 转字节后调 `Share.shareXFiles`。
- `listLocalBackups()`：io 实现用 path_provider 加 `File` 枚举本机备份；web 实现返回空列表，并让 UI 提示「浏览器预览不支持从本机备份恢复」。

实现选择用条件导入：

```dart
import 'platform_files_stub.dart' if (dart.library.io) 'platform_files_io.dart';
```

`settings_screen.dart` 与 `salary_screen.dart` 删除对 `dart:io`、path_provider 的直接引用，全部改调网关。

### 7. 提醒服务 web 守卫

`reminder_notification_service.dart` 的 `cancelDaily()` 开头加 `if (kIsWeb) return;`；界面上「恢复提醒/关闭提醒」操作在 web 下提示不支持。

## 图层索引面板

### SDK 源码实证（Flutter 3.47.1）

- 源文件与行号信息仅存在于编译期 `--track-widget-creation` 注入的私有 `_HasCreationLocation._location`（widget_inspector.dart:4179-4211 区域），由 `WidgetInspectorService` 序列化为 DevTools 协议字段。
- `debugGetCreatorChain`（framework.dart:5236-5247）只返回组件类型链。
- `DiagnosticsDebugCreator` 不携带位置信息，且 `debugTransformDebugCreator` 在非 debug 构建直接返回空。
- 结论：应用内自研面板拿不到源文件与行号，只能拿到组件名、祖先链与属性摘要；文件/行号必须经 DevTools 获取。

### 方案 P0（推荐，0 代码）

`flutter run -d chrome` 后打开终端打印的 DevTools URL，进入 Flutter Inspector，用审查模式点选任意控件，即显示组件名、属性与创建位置「文件:行号」。web 调试经 DWDS 桥接 VM service，机制与 Android 调试一致。

### 方案 P1（页内可见面板，可选）

自研 `LayerProbeOverlay`：

- 开关：`const bool.fromEnvironment('LAYER_PANEL') && kDebugMode && kIsWeb`。
- 挂载点：`MaterialApp.builder`。
- 交互链路：`Listener` 的 `onTapUp` → `renderView` hitTest → 命中叶 `RenderObject` 的 `debugCreator`（`DebugCreator`）对应 `.element` → 向上过滤用户组件（排除 `_` 前缀私有类型与 framework 内部类型）→ 显示 `runtimeType`、`debugGetCreatorChain` 与属性摘要。
- 面板内注明「源文件/行号请用 DevTools 查看」。
- 必须容忍 `debugCreator` 为 null，并回落到链文本显示。

### 面板双保险

渲染同时要求 `--dart-define` 与 `kDebugMode` 成立；release 或普通 `build web` 时面板不渲染。

## 运行与验收

### 一次性环境准备

```bash
flutter create . --platforms web
flutter pub get
```

### 日常命令

```bash
flutter run -d chrome                                # 预览开发
flutter run -d chrome --dart-define=LAYER_PANEL=true # 预览开发（带页内面板）
flutter build web                                    # 交付构建
```

### P0 验收

chrome 打开 `flutter run` 终端打印的 DevTools URL，在审查模式点选自定义组件，详情面板显示 `record_screen.dart` 等真实文件与行号。

### P1 验收

页面右下角出现浮动探针；点「今天工时」卡片，显示 `RecordScreen←…` 形式的祖先链与组件名；release 构建中无探针。

### 回归要求

- `flutter analyze`、`flutter test` 全绿。
- `flutter build apk --release` 仍 Exit 0，且 Android 行为零变化。
- 内存版与 sqflite 版的错误语义差异（`DatabaseException` vs `StateError`/`FormatException`）需在测试用例中锁定：界面相应分支仍可达。

## 风险与未知项

- 开发机是否已安装 Chrome 未确认；实施前先执行 `Get-Command chrome` 检查，缺失则安装或改用 Edge。
- web 会话中 DevTools「创建位置」列的实际渲染未实跑验证，当前依据为机制分析与官方文档支持。
- `flutter build web` 是否接受 `--debug`/`--profile` 参数未确认；默认 release 已满足需求。
- 依赖隔离完成后的真实 dart2js 全量编译通过性，需建 `web/` 后首跑验证。
- `navigator.share` 在非安全上下文不可用；share_plus 有浏览器下载回退，预览者需知悉导出落点为下载。
- 内存数据刷新页面即重置、备份仅支持单向导出、通知仅有 UI 形态——均属预期边界，不是缺陷。
