import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:hi/features/invoice/presentation/screens/carrier_input_screen.dart';
import 'package:hi/features/invoice/presentation/screens/member_barcode_screen.dart';

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
// 全局共享狀態（ValueNotifier 跨 Tab 同步）
// ════════════════════════════════════════════════════════════════════════════

final payMethodsNotifier = ValueNotifier<List<String>>([]);

final memberSetupNotifier = ValueNotifier<Map<String, bool>>({
  'fm': false, 'seven': false, 'hilife': false, 'ok': false,
});

final carrierSetupNotifier = ValueNotifier<bool>(false);

const _kPayMethodsPrefKey = 'pay_methods_list';

Future<void> loadPayMethods() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList(_kPayMethodsPrefKey) ?? [];
  payMethodsNotifier.value = saved;
}

Future<void> savePayMethods(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kPayMethodsPrefKey, ids);
}

// ════════════════════════════════════════════════════════════════════════════
// 折扣規則
// ════════════════════════════════════════════════════════════════════════════

class DiscountRule {
  final int id;
  final String paymentSoftware;
  final String paymentMethod;
  final String userLevel;
  final double discountAmount;
  final double minSpend;
  final double equivalentRate;
  final bool isSpecial;
  final String startDate;
  final String endDate;
  final double availableDays;
  final String ruleDesc;

  const DiscountRule({
    required this.id,
    required this.paymentSoftware,
    required this.paymentMethod,
    required this.userLevel,
    required this.discountAmount,
    required this.minSpend,
    required this.equivalentRate,
    required this.isSpecial,
    required this.startDate,
    required this.endDate,
    required this.availableDays,
    required this.ruleDesc,
  });

  factory DiscountRule.fromMap(Map<String, dynamic> m) => DiscountRule(
        id: (m['id'] as num).toInt(),
        paymentSoftware: m['payment_software'] as String,
        paymentMethod: m['payment_method'] as String,
        userLevel: m['user_level'] as String,
        discountAmount: (m['discount_amount'] as num).toDouble(),
        minSpend: (m['min_spend'] as num).toDouble(),
        equivalentRate: (m['equivalent_rate'] as num).toDouble(),
        isSpecial: (m['is_special'] as num) == 1,
        startDate: m['start_date'] as String,
        endDate: m['end_date'] as String,
        availableDays: (m['available_days'] as num).toDouble(),
        ruleDesc: m['rule_desc'] as String,
      );
}

// ════════════════════════════════════════════════════════════════════════════
// 行動支付平台定義
// ════════════════════════════════════════════════════════════════════════════

class _PayPlatform {
  final String id;
  final String label;
  final Color color;
  final String iconText;
  final String? iosScheme;
  final String? androidScheme;
  final String? universalUrl;

  const _PayPlatform({
    required this.id,
    required this.label,
    required this.color,
    required this.iconText,
    this.iosScheme,
    this.androidScheme,
    this.universalUrl,
  });
}

const _kPayPlatforms = <_PayPlatform>[
  _PayPlatform(
    id: 'linepay', label: 'LINE Pay',
    color: Color(0xFF00B900), iconText: 'LINE\nPay',
    iosScheme: 'linepay://', androidScheme: 'linepay://',
    universalUrl: 'https://line.me/en/pay',
  ),
  _PayPlatform(
    id: 'jkopay', label: '街口支付',
    color: Color(0xFFE53935), iconText: '街口',
    iosScheme: 'jkos://', androidScheme: 'jkos://',
    universalUrl: 'https://www.jkopay.com',
  ),
  _PayPlatform(
    id: 'allpay', label: '全支付',
    color: Color(0xFF1565C0), iconText: '全支付',
    iosScheme: 'fampay://', androidScheme: 'fampay://',
    universalUrl: 'https://www.family.com.tw/marketing/allpay.aspx',
  ),
  _PayPlatform(
    id: 'taiwanpay', label: '台灣Pay',
    color: Color(0xFF2E7D32), iconText: '台灣\nPay',
    iosScheme: 'twpay://', androidScheme: 'twpay://',
    universalUrl: 'https://www.taiwanpay.net.tw',
  ),
  _PayPlatform(
    id: 'easycard', label: '悠遊付',
    color: Color(0xFF00838F), iconText: '悠遊付',
    iosScheme: 'easycard://', androidScheme: 'easycard://',
    universalUrl: 'https://www.easycard.com.tw/easywallet',
  ),
  _PayPlatform(
    id: 'icashpay', label: 'icash Pay',
    color: Color(0xFFEF6C00), iconText: 'icash',
    iosScheme: 'icashpay://', androidScheme: 'icashpay://',
    universalUrl: 'https://www.icashpay.com.tw',
  ),
  _PayPlatform(
    id: 'pxpay', label: 'PX Pay',
    color: Color(0xFFD32F2F), iconText: 'PX\nPay',
    iosScheme: 'pxpay://', androidScheme: 'pxpay://',
    universalUrl: 'https://www.pxmart.com.tw/px/pay.html',
  ),
  _PayPlatform(
    id: 'applepay', label: 'Apple Pay',
    color: Color(0xFF1C1C1E), iconText: ' Pay',
  ),
  _PayPlatform(
    id: 'googlepay', label: 'Google Pay',
    color: Color(0xFF4285F4), iconText: 'G\nPay',
    iosScheme: 'googlepay://', androidScheme: 'googlepay://',
    universalUrl: 'https://pay.google.com',
  ),
  _PayPlatform(
    id: 'samsungpay', label: 'Samsung Pay',
    color: Color(0xFF1428A0), iconText: 'S Pay',
    androidScheme: 'samsungpay://',
    universalUrl: 'https://www.samsung.com/tw/apps/samsung-pay/',
  ),
];

_PayPlatform? _platformById(String id) {
  try {
    return _kPayPlatforms.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}

String? _discountSoftwareToId(String software) {
  const map = {
    '悠遊付': 'easycard',
    '街口支付': 'jkopay',
    '全支付': 'allpay',
    '台灣Pay': 'taiwanpay',
    'Line Pay': 'linepay',
    'LINE Pay': 'linepay',
  };
  return map[software];
}

// ════════════════════════════════════════════════════════════════════════════
// 超商靜態資料
// ════════════════════════════════════════════════════════════════════════════

class _StoreInfo {
  final String id;
  final String name;
  final String shortName;
  final Color primaryColor;
  final String cashback;
  final List<_Condition> conditions;
  final bool hasBadge;

  const _StoreInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.primaryColor,
    required this.cashback,
    required this.conditions,
    this.hasBadge = false,
  });
}

class _Condition {
  final String text;
  final bool isRed;
  const _Condition(this.text, {this.isRed = false});
}

const _kStores = <String, _StoreInfo>{
  'fm': _StoreInfo(
    id: 'fm', name: '全家便利商店', shortName: '全家',
    primaryColor: Color(0xFF003087), cashback: '5%', hasBadge: true,
    conditions: [
      _Condition('消費滿 100 元享 5% 回饋', isRed: true),
      _Condition('滿 200 減 20'),
      _Condition('需使用 FamiPay 付款', isRed: true),
    ],
  ),
  'seven': _StoreInfo(
    id: 'seven', name: '7-ELEVEN', shortName: '7-11',
    primaryColor: Color(0xFFEF6C00), cashback: '3%',
    conditions: [
      _Condition('Open 錢包付款享 3%', isRed: true),
      _Condition('滿 150 減 15'),
      _Condition('每月上限 100 點', isRed: true),
    ],
  ),
  'hilife': _StoreInfo(
    id: 'hilife', name: '萊爾富', shortName: 'Hi-Life',
    primaryColor: Color(0xFFE53935), cashback: '2%',
    conditions: [
      _Condition('Hi-Life Pay 付款', isRed: true),
      _Condition('滿 50 減 5'),
      _Condition('週末加碼 +1%', isRed: true),
    ],
  ),
  'ok': _StoreInfo(
    id: 'ok', name: 'OK超商', shortName: 'OK',
    primaryColor: Color(0xFFE53935), cashback: '4%', hasBadge: true,
    conditions: [
      _Condition('OK Pay 付款享 4%', isRed: true),
      _Condition('滿 150 減 10'),
      _Condition('每筆最高回饋 20 點', isRed: true),
    ],
  ),
};

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
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
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
  Database? _db;
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
      if (!await databaseExists(path)) {
        final copied = await _copyPrebuiltDatabase(path, 'assets/brand_name.db');
        if (!copied) {
          _db = await openDatabase(path, version: 1, onCreate: (db, ver) async {
            final sql = await rootBundle.loadString('lib/brand_name.sql');
            await _executeSqlScript(db, sql);
          });
        }
      }
      _db ??= await openDatabase(path, version: 1);
      await _ensureBrandNameTable();
      final rows = await _db!.query('brand_name');
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

  Future<bool> _copyPrebuiltDatabase(String target, String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List();
      final file = File(target);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      debugPrint('⚠️ 無法複製預建 DB: $e');
      return false;
    }
  }

  Future<void> _ensureBrandNameTable() async {
    final tables = await _db!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='brand_name'",
    );
    if (tables.isEmpty) {
      final sql = await rootBundle.loadString('lib/brand_name.sql');
      await _executeSqlScript(_db!, sql);
    }
  }

  Future<void> _executeSqlScript(Database db, String script) async {
    final stmts = script.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final batch = db.batch();
    for (final s in stmts) batch.execute(s);
    await batch.commit(noResult: true);
  }

  void switchTab(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(dbKeywords: _dbKeywords, dbReady: _dbReady),
      const MemberTab(),
      const SettingsTab(),
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

// ════════════════════════════════════════════════════════════════════════════
// HomeTab
// ════════════════════════════════════════════════════════════════════════════

class HomeTab extends StatefulWidget {
  final List<String> dbKeywords;
  final bool dbReady;

  const HomeTab({super.key, required this.dbKeywords, required this.dbReady});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  static const String _apiKey = 'AIzaSyAly-Vst9UhgyUmQTKFdaCtwNEbNBIzQu4';

  List<Map<String, String>> _displayList = [];
  bool _isLoading = false;
  String _permissionMessage = '';

  Map<String, String>? _selectedStore;
  String _activeStoreId = 'fm';

  // ── 傾斜偵測 ─────────────────────────────────────────────────────────────
  StreamSubscription? _accelSub;
  bool _isTilted = false;
  DateTime? _lastTiltChange;

  // ── 折扣規則 ─────────────────────────────────────────────────────────────
  Map<int, List<DiscountRule>> _discountsByStore = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePermissionMessage();
      _loadDiscountRules();
    });
    _startAccelerometer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    super.dispose();
  }

  // ── 加速度計 ──────────────────────────────────────────────────────────────
  void _startAccelerometer() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final shouldTilt = event.y < -3.0;
      final shouldUntilt = event.y > -1.5;

      if (shouldTilt == _isTilted) return;

      final now = DateTime.now();
      if (_lastTiltChange != null &&
          now.difference(_lastTiltChange!).inMilliseconds < 300) return;
      _lastTiltChange = now;

      if (shouldTilt && !_isTilted) {
        if (mounted) setState(() => _isTilted = true);
      } else if (shouldUntilt && _isTilted) {
        if (mounted) setState(() => _isTilted = false);
      }
    });
  }

  // ── 折扣規則載入 ──────────────────────────────────────────────────────────
  Future<void> _loadDiscountRules() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), 'pay_helper.db');
      if (!await databaseExists(dbPath)) return;
      final db = await openDatabase(dbPath, readOnly: true);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='discount_rules'",
      );
      if (tables.isEmpty) {
        await db.close();
        return;
      }

      final discountRows = await db.query('discount_rules');
      final rules = discountRows.map(DiscountRule.fromMap).toList();

      final mapRows = await db.rawQuery(
        "SELECT rule_id, store_id FROM rule_store_map WHERE rule_type = 'discount'",
      );
      await db.close();

      final Map<int, List<DiscountRule>> byStore = {};
      for (final row in mapRows) {
        final ruleId = (row['rule_id'] as num).toInt();
        final storeId = (row['store_id'] as num).toInt();
        final rule = rules.where((r) => r.id == ruleId).toList();
        if (rule.isNotEmpty) {
          byStore.putIfAbsent(storeId, () => []).add(rule.first);
        }
      }

      if (mounted) setState(() => _discountsByStore = byStore);
    } catch (e) {
      debugPrint('❌ 折扣規則載入失敗: $e');
    }
  }

  int _storeIdFromActiveStore() {
    switch (_activeStoreId) {
      case 'fm':     return 1;
      case 'seven':  return 2;
      case 'hilife': return 3;
      case 'ok':     return 4;
      default:       return 1;
    }
  }

  List<DiscountRule> _getBestDiscounts() {
    final storeId = _storeIdFromActiveStore();
    final rules = _discountsByStore[storeId] ?? [];
    final sorted = List<DiscountRule>.from(rules)
      ..sort((a, b) {
        final rateCmp = b.equivalentRate.compareTo(a.equivalentRate);
        if (rateCmp != 0) return rateCmp;
        return b.discountAmount.compareTo(a.discountAmount);
      });
    return sorted;
  }

  // ── 開啟行動支付 APP ──────────────────────────────────────────────────────
  Future<void> _launchPayApp(_PayPlatform platform) async {
    final scheme = Platform.isIOS ? platform.iosScheme : platform.androidScheme;
    if (scheme != null) {
      final uri = Uri.parse(scheme);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (platform.universalUrl != null) {
      final uri = Uri.parse(platform.universalUrl!);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法開啟 ${platform.label}')),
      );
    }
  }

  Future<void> _updatePermissionMessage() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      if (status.isGranted) {
        _permissionMessage = '';
      } else if (status.isPermanentlyDenied) {
        _permissionMessage = '定位權限已永久拒絕，請至設定開啟';
      } else if (status.isDenied) {
        _permissionMessage = '尚未授權定位，請點右上角授權';
      }
    });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    await _updatePermissionMessage();
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請開啟定位權限以繼續')),
      );
    }
  }

  Future<void> _startDetection() async {
    if (_isLoading || !widget.dbReady) return;
    setState(() { _isLoading = true; _selectedStore = null; });

    try {
      var status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) await openAppSettings();
        await _updatePermissionMessage();
        return;
      }
      await _updatePermissionMessage();

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先啟用定位服務')),
        );
        return;
      }

      var gPerm = await Geolocator.checkPermission();
      if (gPerm == LocationPermission.denied) {
        gPerm = await Geolocator.requestPermission();
      }
      if (gPerm == LocationPermission.denied ||
          gPerm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );

      final names = await _fetchPlaces(pos.latitude, pos.longitude);
      if (names.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 無回應，請檢查網路或金鑰')),
        );
        return;
      }

      final matches = <Map<String, String>>[];
      for (final gName in names) {
        final normalized = gName.replaceAll(' ', '').toLowerCase();
        for (final kw in widget.dbKeywords) {
          final k = kw.replaceAll(' ', '').toLowerCase();
          if (normalized.contains(k) && !matches.any((m) => m['name'] == kw)) {
            matches.add({'name': kw, 'fullName': gName});
          }
        }
      }

      if (mounted) {
        setState(() => _displayList = matches);
        if (matches.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('偵測不到支援的便利商店')),
          );
        } else {
          final nearest = matches.first;
          final id = _matchStoreId(nearest['name']!);
          setState(() {
            _selectedStore = nearest;
            if (id != null) _activeStoreId = id;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 偵測失敗: $e');
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('偵測失敗：$e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _fetchPlaces(double lat, double lng) async {
    try {
      final res = await Dio().post(
        'https://places.googleapis.com/v1/places:searchNearby',
        options: Options(
          headers: {
            'X-Goog-Api-Key': _apiKey,
            'X-Goog-FieldMask': 'places.displayName',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
        data: {
          'includedTypes': [
            'convenience_store', 'cafe', 'restaurant', 'drugstore', 'supermarket'
          ],
          'maxResultCount': 5,
          'languageCode': 'zh-TW',
          'locationRestriction': {
            'circle': {
              'center': {'latitude': lat, 'longitude': lng},
              'radius': 1000.0,
            }
          },
          'rankPreference': 'DISTANCE',
        },
      ).timeout(const Duration(seconds: 15));

      final places = res.data['places'] as List? ?? [];
      return places.map((p) => p['displayName']['text'].toString()).toList();
    } on DioException catch (e) {
      debugPrint('❌ API 異常: ${e.response?.statusCode} ${e.response?.data}');
      return [];
    } catch (e) {
      debugPrint('❌ API 錯誤: $e');
      return [];
    }
  }

  String? _matchStoreId(String name) {
    final n = name.replaceAll(' ', '').toLowerCase();
    if (n.contains('全家') || n.contains('familymart')) return 'fm';
    if (n.contains('7-eleven') || n.contains('7eleven') || n.contains('711')) return 'seven';
    if (n.contains('萊爾富') || n.contains('hilife')) return 'hilife';
    if (n.contains('ok') || n.contains('ok超商')) return 'ok';
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // UI Build
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('發現',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: false,
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _requestPermission,
            icon: const Icon(Icons.search, size: 24),
            tooltip: '定位權限',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          if (_permissionMessage.isNotEmpty)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Material(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_permissionMessage,
                        style: const TextStyle(fontSize: 11, color: Colors.orange))),
                  ]),
                ),
              ),
            ),
          !widget.dbReady
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _buildMainLayout(context),
          if (_isTilted) _buildTiltOverlay(context),
        ],
      ),
    );
  }

  // ── 主佈局 ──────────────────────────────────────────────────────────────
  Widget _buildMainLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStoreRow(),
          const SizedBox(height: 16),
          _buildInfoCard(),
          const SizedBox(height: 12),
          _buildMemberPill(context),
        ],
      ),
    );
  }

  // ── 頂部超商圖示列 ───────────────────────────────────────────────────────
  Widget _buildStoreRow() {
    const storeOrder = ['fm', 'hilife', 'ok', 'seven'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ...storeOrder.map((id) => _buildStoreAvatar(id)),
        _buildLocateButton(),
      ],
    );
  }

  // ── 超商圓形頭像 ─────────────────────────────────────────────────────────
  Widget _buildStoreAvatar(String id) {
    final info = _kStores[id]!;
    final isActive = _activeStoreId == id;

    return GestureDetector(
      onTap: () {
        setState(() => _activeStoreId = id);
        final matched = _displayList
            .where((m) => _matchStoreId(m['name']!) == id)
            .toList();
        if (matched.isNotEmpty) setState(() => _selectedStore = matched.first);
      },
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? info.primaryColor : const Color(0xFFE0E0E0),
                width: isActive ? 2.5 : 1.5,
              ),
              boxShadow: isActive
                  ? [BoxShadow(
                      color: info.primaryColor.withOpacity(0.2),
                      blurRadius: 10, offset: const Offset(0, 3))]
                  : [const BoxShadow(
                      color: Color(0x10000000),
                      blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: ClipOval(child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildStoreLogo(id),
            )),
          ),
          const SizedBox(height: 5),
          Text(
            info.shortName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? info.primaryColor : const Color(0xFF888888),
            ),
          ),
        ],
      ),
    );
  }

  // ── 定位按鈕 ─────────────────────────────────────────────────────────────
  Widget _buildLocateButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _startDetection,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _isLoading ? const Color(0xFF388E3C) : const Color(0xFF1A73E8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isLoading ? Colors.green : Colors.blue).withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
                : const Icon(Icons.my_location, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            _isLoading ? '定位中' : '開始定位',
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF888888)),
          ),
        ],
      ),
    );
  }

  // ── 中央資訊卡 ───────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    final store = _kStores[_activeStoreId]!;
    final branchName = (_selectedStore != null &&
            _matchStoreId(_selectedStore!['name']!) == _activeStoreId)
        ? _selectedStore!['fullName']
        : null;

    final bestDiscounts = _getBestDiscounts();
    final topDiscount = bestDiscounts.isNotEmpty ? bestDiscounts.first : null;
    final otherDiscounts =
        bestDiscounts.length > 1 ? bestDiscounts.skip(1).toList() : <DiscountRule>[];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── 店名列 ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                SizedBox(width: 48, height: 48, child: _buildStoreLogo(_activeStoreId)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branchName ?? store.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700,
                            color: Color(0xFF111111)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (branchName != null)
                        Text(store.name,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF888888))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 推薦支付軟體 label ──────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('推薦支付軟體',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: Color(0xFF888888))),
          ),

          // ── 最佳折扣大卡 ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: topDiscount != null
                ? _buildTopDiscountCard(topDiscount)
                : _buildFallbackDiscountCard(store),
          ),

          // ── 分隔線 ─────────────────────────────────────────────────────
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0),
              indent: 16, endIndent: 16),

          // ── 其他可用支付 label ─────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('其他可用支付軟體',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: Color(0xFF888888))),
          ),

          // ── 其他支付 chip 列 ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildOtherPayRow(otherDiscounts),
          ),
        ],
      ),
    );
  }

  // ── 最佳折扣大卡（彩色框） ───────────────────────────────────────────────
  Widget _buildTopDiscountCard(DiscountRule rule) {
    final platformId = _discountSoftwareToId(rule.paymentSoftware);
    final platform = platformId != null ? _platformById(platformId) : null;
    final color = platform?.color ?? const Color(0xFFE53935);

    return GestureDetector(
      onTap: platform != null ? () => _launchPayApp(platform) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.03),
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  rule.paymentSoftware.length <= 2
                      ? rule.paymentSoftware
                      : '${rule.paymentSoftware[0]}${rule.paymentSoftware[1]}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.paymentSoftware,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(
                    '回饋 ${(rule.equivalentRate * 100).toStringAsFixed(0)} %',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900,
                        color: color, height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rule.ruleDesc,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF666666)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── fallback 大卡（無 DB 折扣） ──────────────────────────────────────────
  Widget _buildFallbackDiscountCard(_StoreInfo store) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: store.primaryColor, width: 1.5),
        borderRadius: BorderRadius.circular(14),
        color: store.primaryColor.withOpacity(0.03),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: store.primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: _buildStoreLogo(store.id)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.name,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: store.primaryColor)),
                Text(
                  '回饋 ${store.cashback}',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900,
                      color: store.primaryColor),
                ),
                ...store.conditions.take(2).map((c) => Text(
                      c.text,
                      style: TextStyle(
                          fontSize: 11,
                          color: c.isRed
                              ? const Color(0xFFE53935)
                              : const Color(0xFF666666)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 其他支付 chip 列 ─────────────────────────────────────────────────────
  Widget _buildOtherPayRow(List<DiscountRule> otherDiscounts) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: payMethodsNotifier,
      builder: (_, enabledIds, __) {
        final chips = <Widget>[];
        final shownIds = <String>{};

        // DB 其他折扣
        for (final rule in otherDiscounts.take(4)) {
          final id = _discountSoftwareToId(rule.paymentSoftware);
          final platform = id != null ? _platformById(id) : null;
          if (platform == null || shownIds.contains(id)) continue;
          shownIds.add(id!);
          chips.add(_buildPayChipV2(
            platform,
            badge: '${(rule.equivalentRate * 100).toStringAsFixed(0)}%',
            onTap: () => _launchPayApp(platform),
          ));
        }

        // 使用者設定的，排除已顯示的
        final bestDiscounts = _getBestDiscounts();
        if (bestDiscounts.isNotEmpty) {
          final topId = _discountSoftwareToId(bestDiscounts.first.paymentSoftware);
          if (topId != null) shownIds.add(topId);
        }

        for (final id in enabledIds) {
          if (shownIds.contains(id)) continue;
          final platform = _platformById(id);
          if (platform == null) continue;
          shownIds.add(id);
          chips.add(_buildPayChipV2(
            platform,
            onTap: () => _launchPayApp(platform),
          ));
        }

        if (chips.isEmpty) {
          return GestureDetector(
            onTap: () {
              final root = context.findAncestorStateOfType<_RootScreenState>();
              root?.switchTab(1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('+ 新增支付方式',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1A73E8))),
            ),
          );
        }

        return Wrap(spacing: 8, runSpacing: 8, children: chips);
      },
    );
  }

  // ── 支付 Chip ────────────────────────────────────────────────────────────
  Widget _buildPayChipV2(_PayPlatform p,
      {String? badge, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: p.color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  p.iconText.replaceAll('\n', '')[0],
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.label,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF222222))),
                if (badge != null)
                  Text(badge,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 會員 & 載具條碼按鈕 ──────────────────────────────────────────────────
  Widget _buildMemberPill(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: carrierSetupNotifier,
      builder: (_, carrierReady, __) {
        return ValueListenableBuilder<Map<String, bool>>(
          valueListenable: memberSetupNotifier,
          builder: (_, memberMap, __) {
            final isReady = carrierReady || memberMap.values.any((v) => v);
            return GestureDetector(
              onTap: () {
                final root = context.findAncestorStateOfType<_RootScreenState>();
                root?.switchTab(1);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isReady ? const Color(0xFF4CAF50) : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: isReady
                      ? null
                      : Border.all(color: const Color(0xFFE0E0E0)),
                  boxShadow: isReady
                      ? [const BoxShadow(
                          color: Color(0x254CAF50),
                          blurRadius: 12,
                          offset: Offset(0, 4))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isReady ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isReady ? Colors.white : const Color(0xFFCCCCCC),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '會員 & 載具條碼',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isReady ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── 超商 Logo Widget ─────────────────────────────────────────────────────
  Widget _buildStoreLogo(String id) {
    switch (id) {
      case 'fm':
        return Column(children: [
          Container(
            width: 40, height: 13,
            decoration: const BoxDecoration(
              color: Color(0xFF00B8A9),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3), topRight: Radius.circular(3)),
            ),
            child: const Center(child: Text('Family',
                style: TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: Colors.white))),
          ),
          Container(
            width: 40, height: 17,
            decoration: const BoxDecoration(
              color: Color(0xFF003087),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3)),
            ),
            child: const Center(child: Text('FamilyMart',
                style: TextStyle(fontSize: 5, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
        ]);
      case 'seven':
        return SizedBox(
          width: 36, height: 36,
          child: Stack(children: [
            Positioned.fill(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Column(children: [
                Expanded(child: Container(color: const Color(0xFF2E7D32))),
                Expanded(child: Container(color: const Color(0xFFEF6C00))),
                Expanded(child: Container(color: const Color(0xFFC62828))),
              ]),
            )),
            const Center(child: Text('7',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                    color: Colors.white, height: 1))),
          ]),
        );
      case 'hilife':
        return Container(
          width: 36, height: 36,
          decoration: const BoxDecoration(
              color: Color(0xFFE53935), shape: BoxShape.circle),
          child: const Center(child: Text('Hi',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white))),
        );
      case 'ok':
        return Container(
          width: 40, height: 26,
          decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(4)),
          child: const Center(child: Text('OK',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -0.5))),
        );
      default:
        return const Icon(Icons.store, size: 28);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 傾斜時的全螢幕條碼 Overlay
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildTiltOverlay(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isTilted ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: RotatedBox(
            quarterTurns: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.barcode_reader,
                            color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '請掃描以下條碼',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TiltBarcodeSection(
                    title: '會員條碼',
                    icon: Icons.person_outline,
                    prefKeyCode:
                        'member_barcode_${_kStores[_activeStoreId]?.name ?? "_generic"}',
                    prefKeyType:
                        'member_type_${_kStores[_activeStoreId]?.name ?? "_generic"}',
                  ),
                  const SizedBox(height: 20),
                  const _TiltCarrierSection(),
                  const SizedBox(height: 20),
                  Text(
                    '將手機收回即可返回首頁',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 傾斜 Overlay：會員條碼區塊
// ════════════════════════════════════════════════════════════════════════════

class _TiltBarcodeSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final String prefKeyCode;
  final String prefKeyType;

  const _TiltBarcodeSection({
    required this.title,
    required this.icon,
    required this.prefKeyCode,
    required this.prefKeyType,
  });

  @override
  State<_TiltBarcodeSection> createState() => _TiltBarcodeSectionState();
}

class _TiltBarcodeSectionState extends State<_TiltBarcodeSection> {
  String? _code;
  String _type = 'code128';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString(widget.prefKeyCode);
    String? type = prefs.getString(widget.prefKeyType);

    if (code == null) {
      for (final brand in ['全家便利商店', '7-ELEVEN', '萊爾富', 'OK便利商店', '_generic']) {
        code = prefs.getString('member_barcode_$brand');
        type = prefs.getString('member_type_$brand');
        if (code != null) break;
      }
    }

    if (!mounted) return;
    setState(() {
      _code = code;
      _type = type ?? 'code128';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_code == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: Colors.grey.shade400, size: 16),
            const SizedBox(width: 8),
            Text('未設定${widget.title}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    final isQR = _type == 'qrCode';
    Barcode barcode;
    switch (_type) {
      case 'ean13':
        barcode = Barcode.ean13();
        break;
      case 'qrCode':
        barcode = Barcode.qrCode();
        break;
      default:
        barcode = Barcode.code128();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 12),
          if (isQR)
            Center(
              child: BarcodeWidget(
                barcode: barcode,
                data: _code!,
                width: 150,
                height: 150,
                drawText: false,
              ),
            )
          else
            LayoutBuilder(
              builder: (ctx, constraints) => BarcodeWidget(
                barcode: barcode,
                data: _code!.trim().toUpperCase().replaceAll(RegExp(r'\s'), ''),
                width: constraints.maxWidth,
                height: 100,
                drawText: false,
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          const SizedBox(height: 8),
          Text(_code!,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 傾斜 Overlay：載具條碼區塊
// ════════════════════════════════════════════════════════════════════════════

class _TiltCarrierSection extends StatefulWidget {
  const _TiltCarrierSection();

  @override
  State<_TiltCarrierSection> createState() => _TiltCarrierSectionState();
}

class _TiltCarrierSectionState extends State<_TiltCarrierSection> {
  String? _code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('carrier_code');
    if (!mounted) return;
    setState(() {
      _code = raw?.trim().toUpperCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_code == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, color: Colors.grey.shade400, size: 16),
            const SizedBox(width: 8),
            Text('未設定電子載具',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text('電子載具',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, constraints) => BarcodeWidget(
              barcode: Barcode.code128(),
              data: _code!,
              width: constraints.maxWidth,
              height: 100,
              drawText: false,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
          ),
          const SizedBox(height: 8),
          Text(_code!,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 支付條碼畫面
// ════════════════════════════════════════════════════════════════════════════

class PaymentBarcodeScreen extends StatefulWidget {
  final String platformId;
  const PaymentBarcodeScreen({super.key, required this.platformId});

  @override
  State<PaymentBarcodeScreen> createState() => _PaymentBarcodeScreenState();
}

class _PaymentBarcodeScreenState extends State<PaymentBarcodeScreen> {
  double _originalBrightness = 0.5;
  bool _isFlipped = false;
  StreamSubscription? _accelSub;

  @override
  void initState() {
    super.initState();
    _setBrightness();
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final shouldFlip = event.y < -3;
      if (shouldFlip != _isFlipped && mounted) {
        setState(() => _isFlipped = shouldFlip);
      }
    });
  }

  Future<void> _setBrightness() async {
    try {
      _originalBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(1.0);
    } catch (e) {
      debugPrint('⚠️ 亮度設定失敗: $e');
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    ScreenBrightness()
        .setScreenBrightness(_originalBrightness)
        .catchError((_) {});
    super.dispose();
  }

  Future<void> _launchApp(_PayPlatform platform) async {
    final scheme =
        Platform.isIOS ? platform.iosScheme : platform.androidScheme;
    if (scheme != null) {
      final uri = Uri.parse(scheme);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (platform.universalUrl != null) {
      await launchUrl(Uri.parse(platform.universalUrl!),
          mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法開啟 ${platform.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platformById(widget.platformId);
    if (platform == null) {
      return const Scaffold(body: Center(child: Text('找不到支付平台')));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(platform.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: AnimatedRotation(
          duration: const Duration(milliseconds: 300),
          turns: _isFlipped ? 0.5 : 0.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: platform.color,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: platform.color.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Center(
                    child: Text(platform.iconText,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.3),
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 28),
                Text(platform.label,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  platform.universalUrl != null
                      ? '點擊下方按鈕開啟 ${platform.label} APP 進行支付'
                      : '請使用裝置內建 ${platform.label} 進行支付',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                if (platform.iosScheme != null ||
                    platform.androidScheme != null ||
                    platform.universalUrl != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _launchApp(platform),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text('開啟 ${platform.label}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: platform.color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.screen_rotation,
                        size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text('傾斜手機，畫面自動翻轉給店員看',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 店家選擇 Sheet
// ════════════════════════════════════════════════════════════════════════════

class _StorePickerSheet extends StatelessWidget {
  final List<Map<String, String>> stores;
  final Map<String, String>? selectedStore;
  final ValueChanged<Map<String, String>> onSelected;

  const _StorePickerSheet({
    required this.stores,
    required this.selectedStore,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('選擇店家',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('選擇後將顯示對應的會員/支付條碼',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(0.5))),
          const SizedBox(height: 16),
          ...stores.map((s) {
            final selected = selectedStore?['fullName'] == s['fullName'];
            return ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: Icon(Icons.store,
                  color: selected
                      ? Colors.blue
                      : cs.onSurface.withOpacity(0.5)),
              title: Text(s['name']!,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(s['fullName']!,
                  style: const TextStyle(fontSize: 11)),
              trailing: selected
                  ? const Icon(Icons.check_circle, color: Colors.blue)
                  : null,
              onTap: () => onSelected(s),
            );
          }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MemberTab
// ════════════════════════════════════════════════════════════════════════════

class MemberTab extends StatefulWidget {
  const MemberTab({super.key});

  @override
  State<MemberTab> createState() => _MemberTabState();
}

class _MemberTabState extends State<MemberTab> {

  void _togglePlatform(String id) {
    final current = List<String>.from(payMethodsNotifier.value);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    payMethodsNotifier.value = current;
    savePayMethods(current);
  }

  void _movePlatform(int oldIdx, int newIdx) {
    final current = List<String>.from(payMethodsNotifier.value);
    if (newIdx > oldIdx) newIdx--;
    final item = current.removeAt(oldIdx);
    current.insert(newIdx, item);
    payMethodsNotifier.value = current;
    savePayMethods(current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('會員', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          _sectionLabel('行動支付'),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '勾選後會顯示在首頁，並可用音量鍵快速切換開啟。長按可調整順序。',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),

          ValueListenableBuilder<List<String>>(
            valueListenable: payMethodsNotifier,
            builder: (_, enabledIds, __) {
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    if (enabledIds.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(children: [
                          const Icon(Icons.drag_indicator,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('已選擇（長按拖曳排序）',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                        ]),
                      ),
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        onReorder: _movePlatform,
                        children: enabledIds.asMap().entries.map((e) {
                          final idx = e.key;
                          final id = e.value;
                          final platform = _platformById(id);
                          if (platform == null) {
                            return const SizedBox(key: ValueKey('_'));
                          }
                          return _buildPlatformTile(
                            key: ValueKey(id),
                            platform: platform,
                            enabled: true,
                            isFirst: idx == 0,
                            showDivider: idx < enabledIds.length - 1 ||
                                _kPayPlatforms
                                    .any((p) => !enabledIds.contains(p.id)),
                          );
                        }).toList(),
                      ),
                      if (_kPayPlatforms
                          .any((p) => !enabledIds.contains(p.id)))
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                    ..._kPayPlatforms
                        .where((p) => !enabledIds.contains(p.id))
                        .toList()
                        .asMap()
                        .entries
                        .map((e) {
                      final remaining = _kPayPlatforms
                          .where((p) => !enabledIds.contains(p.id))
                          .toList();
                      return _buildPlatformTile(
                        key: ValueKey('${e.value.id}_off'),
                        platform: e.value,
                        enabled: false,
                        showDivider: e.key < remaining.length - 1,
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          _sectionLabel('超商會員'),

          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: memberSetupNotifier,
            builder: (_, memberMap, __) {
              final entries = [
                ('fm', '全家便利商店', '全家'),
                ('seven', '7-ELEVEN', '7-ELEVEN'),
                ('hilife', '萊爾富', '萊爾富'),
                ('ok', 'OK便利商店', 'OK超商'),
              ];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: entries.asMap().entries.map((e) {
                    final idx = e.key;
                    final (id, brandName, displayName) = e.value;
                    final isSetup = memberMap[id] ?? false;
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.store_outlined,
                              color: isSetup ? Colors.blue : Colors.grey[400]),
                          title: Text(displayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          trailing: isSetup
                              ? const Icon(Icons.check_circle,
                                  color: Color(0xFF43A047))
                              : const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => MemberBarcodeScreen(
                                        brandName: brandName),
                                    fullscreenDialog: true));
                            final updated = Map<String, bool>.from(
                                memberSetupNotifier.value);
                            updated[id] = true;
                            memberSetupNotifier.value = updated;
                          },
                        ),
                        if (idx < entries.length - 1)
                          const Divider(
                              height: 1, indent: 16, endIndent: 16),
                      ],
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text('電子載具',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                          letterSpacing: 0.5)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CarrierInputScreen(),
                          fullscreenDialog: true));
                  carrierSetupNotifier.value = true;
                },
                tooltip: '新增載具',
              ),
            ],
          ),

          ValueListenableBuilder<bool>(
            valueListenable: carrierSetupNotifier,
            builder: (_, isSetup, __) => _EntryCard(
              icon: Icons.receipt_long,
              iconColor: Colors.indigo,
              title: '電子載具（手機條碼）',
              subtitle: isSetup ? '已設定 ✓' : '點擊設定 /XXXXXXX',
              statusIcon: isSetup
                  ? const Icon(Icons.check_circle,
                      color: Color(0xFF43A047), size: 20)
                  : null,
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CarrierInputScreen(),
                        fullscreenDialog: true));
                carrierSetupNotifier.value = true;
              },
            ),
          ),

          const SizedBox(height: 24),

          _sectionLabel('其他'),
          _EntryCard(
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            title: '關於',
            subtitle: 'v1.1.2',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '秒付辨識器',
              applicationVersion: 'v1.1.2',
              children: const [Text('快速出示會員條碼與電子載具，方便結帳使用。')],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformTile({
    required Key key,
    required _PayPlatform platform,
    required bool enabled,
    bool isFirst = false,
    bool showDivider = true,
  }) {
    return Column(
      key: key,
      children: [
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled ? platform.color : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                platform.iconText.replaceAll('\n', ' ').trim()[0],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: enabled ? Colors.white : Colors.grey[400],
                ),
              ),
            ),
          ),
          title: Text(platform.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.black : Colors.grey[500],
              )),
          subtitle: enabled && isFirst
              ? const Text('首選（音量鍵優先開啟）',
                  style: TextStyle(fontSize: 10, color: Colors.blue))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch.adaptive(
                value: enabled,
                onChanged: (_) => _togglePlatform(platform.id),
                activeColor: platform.color,
              ),
              if (enabled)
                IconButton(
                  icon: Icon(Icons.open_in_new,
                      size: 18, color: Colors.grey[500]),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              PaymentBarcodeScreen(platformId: platform.id),
                          fullscreenDialog: true)),
                  tooltip: '測試開啟',
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                letterSpacing: 0.5)),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// SettingsTab
// ════════════════════════════════════════════════════════════════════════════

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('設定', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('一般',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 0.5)),
          ),
          _EntryCard(
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            title: '關於',
            subtitle: 'v1.1.2',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '秒付辨識器',
              applicationVersion: 'v1.1.2',
              children: const [Text('快速出示會員條碼與電子載具，方便結帳使用。')],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 通用入口卡片
// ════════════════════════════════════════════════════════════════════════════

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? statusIcon;

  const _EntryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              statusIcon ??
                  const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
