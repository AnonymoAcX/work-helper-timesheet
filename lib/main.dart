import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:work_helper/controllers/app_settings_controller.dart';
import 'package:work_helper/screens/record_screen.dart';
import 'package:work_helper/screens/salary_screen.dart';
import 'package:work_helper/screens/schedule_screen.dart';
import 'package:work_helper/screens/settings_screen.dart';
import 'package:work_helper/theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettingsController();
  try {
    await settings.load();
  } catch (_) {
    // 设置加载失败（如 preferences 损坏）：展示最小错误页，不裸崩。
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: Text('初始化失败，请重试或清除应用数据')),
        ),
      ),
    );
    return;
  }
  runApp(ChangeNotifierProvider.value(value: settings, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsController>(
      builder: (context, settings, _) => MaterialApp(
        title: '记工时',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF111318)
          : const Color(0xFFF7F7F7),
      cardColor: dark ? const Color(0xFF1B1E25) : Colors.white,
      useMaterial3: false,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF20242C) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF1B1E25) : Colors.white,
        selectedItemColor: dark ? Colors.white : Colors.black,
        unselectedItemColor: dark
            ? const Color(0xFF7C8494)
            : const Color(0xFFD7D7D7),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [
    const RecordScreen(),
    const ScheduleScreen(),
    const SalaryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final navTheme = Theme.of(context).bottomNavigationBarTheme;
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: navTheme.backgroundColor,
        selectedItemColor: navTheme.selectedItemColor,
        unselectedItemColor: navTheme.unselectedItemColor,
        selectedFontSize: 14,
        unselectedFontSize: 14,
        iconSize: 27,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '工时'),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart_outline),
            label: '待办',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.track_changes), label: '统计'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_pin_circle_outlined),
            label: '个人',
          ),
        ],
      ),
    );
  }
}
