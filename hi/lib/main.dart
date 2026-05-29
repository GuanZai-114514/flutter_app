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

      // 如果需要強制重置資料庫進行測試，請取消註解下一行
      // await deleteDatabase(path);

      if (!await databaseExists(path)) {
        final copied = await _copyPrebuiltDatabase(path, 'assets/brand_name.db');
        if (!copied) {
          db = await openDatabase(path, version: 1, onCreate: (db, ver) async {
            await _loadAndExecuteSql(db, 'lib/brand_name.sql');
            await _loadAndExecuteSql(db, 'lib/Payment/reward_rules.sql');
            await _loadAndExecuteSql(db, 'lib/Payment/discount_rules.sql');
            await _loadAndExecuteSql(db, 'lib/Payment/rule_store_map.sql');
            await _loadAndExecuteSql(db, 'lib/Payment/payment_options.sql');
            await _loadAndExecuteSql(db, 'lib/assets/payment/等級.sql');
            await _loadAndExecuteSql(db, 'lib/assets/payment/支付方式.sql');
            await _loadAndExecuteSql(db, 'lib/assets/members/會員.sql');
          });
        }
      }
      
      db ??= await openDatabase(path, version: 1);

      // 若剛複製預建 DB，或預建 DB 只包含部分表，確保其他 SQL 資料表也被載入
      await _ensureSqlAssets(db);

      // 確保欄位完整
      await _fixTableSchemas(db);
      
      // 確保必要資料表存在
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
      // 即便失敗也嘗試開啟，避免無限轉圈，或者在此處理錯誤 UI
    }
  }

  // 修正資料表欄位，確保同時具備 user_level 與 payment_method
  Future<void> _fixTableSchemas(Database db) async {
    final tables = ['Easy_wallet', 'JKOPay', 'Line_Pay', 'PXPay_Plus', 'Taiwan_Pay'];
    for (var table in tables) {
      await db.execute('CREATE TABLE IF NOT EXISTS "$table" (id INTEGER PRIMARY KEY, user_level TEXT, payment_method TEXT)');
      
      var columns = await db.rawQuery('PRAGMA table_info("$table")');
      if (!columns.any((c) => c['name'] == 'user_level')) {
        await db.execute('ALTER TABLE "$table" ADD COLUMN user_level TEXT');
      }
      if (!columns.any((c) => c['name'] == 'payment_method')) {
        await db.execute('ALTER TABLE "$table" ADD COLUMN payment_method TEXT');
      }
    }
  }

  // 確保必要的 SQL 資料表（若複製了預建 DB 但缺少其他表）
  Future<void> _ensureSqlAssets(Database db) async {
    try {
      final checks = {
        'brand_name': 'lib/brand_name.sql',
        'payment_options': 'lib/Payment/payment_options.sql',
        'discount_rules': 'lib/Payment/discount_rules.sql',
        'rule_store_map': 'lib/Payment/rule_store_map.sql',
        'reward_rules': 'lib/Payment/reward_rules.sql',
      };
      for (final e in checks.entries) {
        final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='${e.key}'");
        if (rows.isEmpty) await _loadAndExecuteSql(db, e.value);
      }

      // 若平台等級 / 支付方式表尚未建立，載入兩個 SQL
      final plat = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='Easy_wallet'");
      if (plat.isEmpty) {
        await _loadAndExecuteSql(db, 'lib/assets/payment/等級.sql');
        await _loadAndExecuteSql(db, 'lib/assets/payment/支付方式.sql');
      }

      // 若會員相關表尚未建立，載入會員 SQL
      final mem = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payment_software'");
      if (mem.isEmpty) {
        await _loadAndExecuteSql(db, 'lib/assets/members/會員.sql');
      }
    } catch (e) {
      debugPrint('⚠️ 確保 SQL 資產時發生錯誤: $e');
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
    final brandTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='brand_name'",
    );
    if (brandTable.isEmpty) {
      await _loadAndExecuteSql(db, 'lib/brand_name.sql');
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
