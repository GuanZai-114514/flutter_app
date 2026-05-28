import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'notifiers.dart';
import 'screens/home_screen.dart';
import 'screens/member_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('💥 Flutter 錯誤: ${details.exception}');
    debugPrint('堆疊追蹤: ${details.stack}');
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('💥 未捕獲異常: $error');
    debugPrint('堆疊追蹤: $stack');
    return true;
  };

  runApp(const MyApp());
}

// ════════════════════════════════════════════════════════════════════════════
// MyApp
// ════════════════════════════════════════════════════════════════════════════

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.light,
      home: const RootScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RootScreen — 底部導覽 3 Tab
// ════════════════════════════════════════════════════════════════════════════

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;
  List<String> _dbKeywords = [];
  bool _dbReady = false;

  @override
  void initState() {
    super.initState();
    loadPayMethods();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDatabase());
  }

  Future<void> _initDatabase() async {
    try {
      final path = p.join(await getDatabasesPath(), 'pay_helper.db');
      Database? db;

      // 如果資料庫不存在，則進行初始化
      if (!await databaseExists(path)) {
        final copied = await _copyPrebuiltDatabase(path, 'lib/assets/brand_name.db');
        if (!copied) {
          db = await openDatabase(path, version: 1, onCreate: (db, ver) async {
            // 執行基礎品牌資料
            await _loadAndExecuteSql(db, 'lib/assets/brand_name.sql');
            // 執行您提供的所有支付與規則資料
            await _loadAndExecuteSql(db, 'lib/assets/Payment/reward_rules.sql');
            await _loadAndExecuteSql(db, 'lib/assets/Payment/discount_rules.sql');
            await _loadAndExecuteSql(db, 'lib/assets/Payment/rule_store_map.sql');
            await _loadAndExecuteSql(db, 'lib/assets/Payment/payment_options.sql');
          });
        }
      }
      
      db ??= await openDatabase(path, version: 1);
      
      // 確保必要的表都存在
      await _ensureTables(db);
      
      final rows = await db.query('brand_name');

      if (mounted) {
        setState(() {
          _dbKeywords = rows.map((r) => r['brand_name'].toString()).toList();
          _dbReady = true;
        });
      }
    } catch (e) {
      debugPrint('❌ DB 初始化失敗: $e');
    }
  }

  Future<void> _loadAndExecuteSql(Database db, String assetPath) async {
    try {
      final sql = await rootBundle.loadString(assetPath);
      await _executeSqlScript(db, sql);
    } catch (e) {
      debugPrint('⚠️ 無法執行 SQL 腳本 ($assetPath): $e');
    }
  }

  Future<bool> _copyPrebuiltDatabase(String target, String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List();
      final file = File(target);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      debugPrint('⚠️ 無法複製預建 DB ($asset): $e');
      return false;
    }
  }

  Future<void> _ensureTables(Database db) async {
    // 檢查 brand_name 表
    final brandTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='brand_name'",
    );
    if (brandTable.isEmpty) {
      await _loadAndExecuteSql(db, 'lib/assets/brand_name.sql');
    }

    // 檢查 discount_rules 表（HomeScreen 需要）
    final discountTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='discount_rules'",
    );
    if (discountTable.isEmpty) {
      await _loadAndExecuteSql(db, 'lib/assets/Payment/discount_rules.sql');
      await _loadAndExecuteSql(db, 'lib/assets/Payment/rule_store_map.sql');
    }
  }

  Future<void> _executeSqlScript(Database db, String script) async {
    final stmts = script
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final batch = db.batch();
    for (final s in stmts) {
      batch.execute(s);
    }
    await batch.commit(noResult: true);
  }

  void _goToMember() => setState(() => _currentIndex = 1);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        dbKeywords: _dbKeywords,
        dbReady: _dbReady,
        onGoToMember: _goToMember,
      ),
      const MemberScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black12,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首頁',
          ),
          NavigationDestination(
            icon: Icon(Icons.wallet_outlined),
            selectedIcon: Icon(Icons.wallet),
            label: '會員',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
