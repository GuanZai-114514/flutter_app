import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
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

// ── App ───────────────────────────────────────────────────────────────────────

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

// ── Root：底部導覽（3 Tab） ────────────────────────────────────────────────────

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDatabase());
  }

  // ── DB 初始化 ─────────────────────────────────────────────────────────────

  Future<void> _initDatabase() async {
    try {
      final path = p.join(await getDatabasesPath(), 'pay_helper.db');
      if (!await databaseExists(path)) {
        final copied = await _copyPrebuiltDatabase(path, 'assets/brand_name.db');
        if (!copied) {
          _db = await openDatabase(
            path,
            version: 1,
            onCreate: (db, version) async {
              final sql = await rootBundle.loadString('lib/brand_name.sql');
              await _executeSqlScript(db, sql);
            },
          );
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(dbKeywords: _dbKeywords, dbReady: _dbReady),
      const MemberTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
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

// ── 首頁 Tab ──────────────────────────────────────────────────────────────────
//
// 佈局（照設計稿）：
//   上排：全家（左）、7-ELEVEN（右）
//   中央：詳細資訊卡片（回饋、條件、行動支付）
//   下排：萊爾富（左）、OK超商（右）
//   底部：「會員 or 載具」pill（開啟條碼/載具選擇）
//
// 狀態：
//   _activeStoreId  → 目前高亮的超商圓圈 ID
//   _selectedStore  → 從附近店家清單選中的那家（定位後帶入）
//   _displayList    → 附近店家清單（定位後取得）
//   _isLoading      → 定位 / API 載入中

enum _ActiveCard { member, payment, carrier }

// 超商靜態資料
class _StoreInfo {
  final String id;
  final String name;
  final String shortName;
  final Color primaryColor;
  final Color bgColor;
  final String cashback;
  final List<_Condition> conditions;
  final List<_PayMethod> payMethods;
  final bool hasBadge;

  const _StoreInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.primaryColor,
    required this.bgColor,
    required this.cashback,
    required this.conditions,
    required this.payMethods,
    this.hasBadge = false,
  });
}

class _Condition {
  final String text;
  final bool isRed;
  const _Condition(this.text, {this.isRed = false});
}

class _PayMethod {
  final String label;
  final Color color;
  const _PayMethod(this.label, this.color);
}

const _kStores = <String, _StoreInfo>{
  'fm': _StoreInfo(
    id: 'fm',
    name: '全家便利商店',
    shortName: '全家',
    primaryColor: Color(0xFF003087),
    bgColor: Color(0xFFE8F0FF),
    cashback: '5%',
    hasBadge: true,
    conditions: [
      _Condition('消費滿 100 元享 5% 回饋', isRed: true),
      _Condition('滿 200 減 20'),
      _Condition('需使用 FamiPay 付款', isRed: true),
    ],
    payMethods: [
      _PayMethod('LINE Pay', Color(0xFF00B900)),
      _PayMethod('街口支付', Color(0xFFE53935)),
      _PayMethod('Apple Pay', Color(0xFF1C1C1E)),
      _PayMethod('Google Pay', Color(0xFF4285F4)),
    ],
  ),
  'seven': _StoreInfo(
    id: 'seven',
    name: '7-ELEVEN',
    shortName: '7-11',
    primaryColor: Color(0xFFEF6C00),
    bgColor: Color(0xFFFFF3E0),
    cashback: '3%',
    conditions: [
      _Condition('Open 錢包付款享 3%', isRed: true),
      _Condition('滿 150 減 15'),
      _Condition('每月上限 100 點', isRed: true),
    ],
    payMethods: [
      _PayMethod('Apple Pay', Color(0xFF1C1C1E)),
      _PayMethod('街口支付', Color(0xFFE53935)),
    ],
  ),
  'hilife': _StoreInfo(
    id: 'hilife',
    name: '萊爾富',
    shortName: 'Hi-Life',
    primaryColor: Color(0xFFE53935),
    bgColor: Color(0xFFFFEBEE),
    cashback: '2%',
    conditions: [
      _Condition('Hi-Life Pay 付款', isRed: true),
      _Condition('滿 50 減 5'),
      _Condition('週末加碼 +1%', isRed: true),
    ],
    payMethods: [
      _PayMethod('Google Pay', Color(0xFF4285F4)),
      _PayMethod('Apple Pay', Color(0xFF1C1C1E)),
    ],
  ),
  'ok': _StoreInfo(
    id: 'ok',
    name: 'OK超商',
    shortName: 'OK',
    primaryColor: Color(0xFFE53935),
    bgColor: Color(0xFFFFEBEE),
    cashback: '4%',
    hasBadge: true,
    conditions: [
      _Condition('OK Pay 付款享 4%', isRed: true),
      _Condition('滿 150 減 10'),
      _Condition('每筆最高回饋 20 點', isRed: true),
    ],
    payMethods: [
      _PayMethod('Apple Pay', Color(0xFF1C1C1E)),
      _PayMethod('Google Pay', Color(0xFF4285F4)),
      _PayMethod('Samsung Pay', Color(0xFF1428A0)),
    ],
  ),
};

class HomeTab extends StatefulWidget {
  final List<String> dbKeywords;
  final bool dbReady;

  const HomeTab({super.key, required this.dbKeywords, required this.dbReady});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const String _apiKey = 'AIzaSyAly-Vst9UhgyUmQTKFdaCtwNEbNBIzQu4';

  // ── 狀態 ──
  List<Map<String, String>> _displayList = [];
  bool _isLoading = false;
  String _permissionMessage = '';

  // 定位後帶入的選中店家（用來對應圓圈）
  Map<String, String>? _selectedStore;

  // 目前高亮的超商圓圈 ID（預設全家）
  String _activeStoreId = 'fm';

  // 會員 or 載具 三按鈕
  _ActiveCard _activeCard = _ActiveCard.member;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePermissionMessage());
  }

  // ── 定位相關 ──────────────────────────────────────────────────────────────

  Future<void> _updatePermissionMessage() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      if (status.isGranted) {
        _permissionMessage = '';
      } else if (status.isPermanentlyDenied) {
        _permissionMessage = '定位權限已永久拒絕，請至設定開啟';
      } else if (status.isDenied) {
        _permissionMessage = '定位權限尚未授權，請點右上角授權';
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

  /// 重新定位並取得附近店家，同時清除已選店家
  Future<void> _startDetection() async {
    if (_isLoading || !widget.dbReady) return;
    setState(() {
      _isLoading = true;
      _selectedStore = null; // 重新定位就清掉選擇
    });

    try {
      var status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) await openAppSettings();
        await _updatePermissionMessage();
        return;
      }
      await _updatePermissionMessage();

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請先啟用定位服務')),
          );
        }
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
          // 自動選取最近的那家，並高亮對應圓圈
          final nearest = matches.first;
          final nearestId = _matchStoreId(nearest['name']!);
          setState(() {
            _selectedStore = nearest;
            if (nearestId != null) _activeStoreId = nearestId;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 偵測失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('偵測失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _fetchPlaces(double lat, double lng) async {
    if (_displayList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先點右上角 ↻ 偵測附近店家')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _StorePickerSheet(
        stores: _displayList,
        selectedStore: _selectedStore,
        onSelected: (store) {
          final id = _matchStoreId(store['name']!);
          setState(() {
            _selectedStore = store;
            if (id != null) _activeStoreId = id;
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
    try {
      final res = await Dio()
          .post(
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
          )
          .timeout(const Duration(seconds: 15));

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

  // ── 選擇店家 Sheet ────────────────────────────────────────────────────────

  /// 顯示附近店家清單 Sheet，選完後更新 _selectedStore
  Future<void> _showStorePickerSheet() async {
    if (_displayList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先點右上角 ↻ 偵測附近店家')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _StorePickerSheet(
        stores: _displayList,
        selectedStore: _selectedStore,
        onSelected: (store) {
          final id = _matchStoreId(store['name']!);
          setState(() {
            _selectedStore = store;
            if (id != null) _activeStoreId = id;
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ── 根據店名對應圓圈 ID ─────────────────────────────────────────────────
  String? _matchStoreId(String name) {
    final n = name.replaceAll(' ', '').toLowerCase();
    if (n.contains('全家') || n.contains('familymart')) return 'fm';
    if (n.contains('7-eleven') || n.contains('7eleven') || n.contains('711')) return 'seven';
    if (n.contains('萊爾富') || n.contains('hilife')) return 'hilife';
    if (n.contains('ok') || n.contains('ok超商')) return 'ok';
    return null;
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('首頁', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _requestPermission,
            icon: const Icon(Icons.location_on_outlined),
            tooltip: '定位權限',
          ),
          IconButton(
            onPressed: _isLoading ? null : _startDetection,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '重新定位',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 權限提示橫幅 ──────────────────────────────────────────────────
          if (_permissionMessage.isNotEmpty)
            Material(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _permissionMessage,
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: !widget.dbReady
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _buildMainLayout(context),
          ),
        ],
      ),
    );
  }

  // ── 主佈局：四角圓圈 + 中央卡片 + 底部 pill ──────────────────────────────

  Widget _buildMainLayout(BuildContext context) {
    final store = _kStores[_activeStoreId]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // 上排：全家（左）、7-ELEVEN（右）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStoreCircle('fm'),
              _buildStoreCircle('seven'),
            ],
          ),

          const SizedBox(height: 10),

          // 中央：詳細資訊卡片（彈性填滿剩餘空間）
          Expanded(child: _buildInfoCard(store)),

          const SizedBox(height: 10),

          // 下排：萊爾富（左）、OK（右）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStoreCircle('hilife'),
              _buildStoreCircle('ok'),
            ],
          ),

          const SizedBox(height: 12),

          // 「會員 or 載具」pill + 三點
          _buildMemberPill(context),
        ],
      ),
    );
  }

  // ── 超商圓圈按鈕 ─────────────────────────────────────────────────────────

  Widget _buildStoreCircle(String id) {
    final info = _kStores[id]!;
    final isActive = _activeStoreId == id;

    return GestureDetector(
      onTap: () => setState(() => _activeStoreId = id),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? info.primaryColor : const Color(0xFFE0E0E0),
                width: isActive ? 2.5 : 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStoreLogo(id, info),
                const SizedBox(height: 3),
                Text(
                  info.shortName,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isActive ? info.primaryColor : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // 紅色 badge（有特殊回饋）
          if (info.hasBadge)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 超商 LOGO（各自色塊模擬） ─────────────────────────────────────────────

  Widget _buildStoreLogo(String id, _StoreInfo info) {
    switch (id) {
      case 'fm':
        return Column(
          children: [
            Container(
              width: 40,
              height: 13,
              decoration: const BoxDecoration(
                color: Color(0xFF00B8A9),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
              ),
              child: const Center(
                child: Text('Family',
                    style: TextStyle(
                        fontSize: 6, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
            Container(
              width: 40,
              height: 17,
              decoration: const BoxDecoration(
                color: Color(0xFF003087),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
              ),
              child: const Center(
                child: Text('FamilyMart',
                    style: TextStyle(
                        fontSize: 5, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        );

      case 'seven':
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Column(children: [
                    Expanded(child: Container(color: const Color(0xFF2E7D32))),
                    Expanded(child: Container(color: const Color(0xFFEF6C00))),
                    Expanded(child: Container(color: const Color(0xFFC62828))),
                  ]),
                ),
              ),
              const Center(
                child: Text('7',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1)),
              ),
            ],
          ),
        );

      case 'hilife':
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFE53935),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('Hi',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        );

      case 'ok':
        return Container(
          width: 40,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Center(
            child: Text('OK',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5)),
          ),
        );

      default:
        return Icon(Icons.store, color: info.primaryColor, size: 28);
    }
  }

  // ── 中央詳細資訊卡片 ──────────────────────────────────────────────────────

  Widget _buildInfoCard(_StoreInfo store) {
    // 定位後取得的門市全名（若有）
    final branchName = _selectedStore != null &&
            _selectedStore!['name']!
                .toLowerCase()
                .contains(store.id == 'fm' ? '全家' : store.shortName)
        ? _selectedStore!['fullName']!
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 上半：LOGO + 店名 + 回饋 + 條件 ───────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左欄：LOGO + LINE Pay + 街口
              Column(
                children: [
                  _buildStoreLogo(store.id, store),
                  const SizedBox(height: 8),
                  _buildPayTag('LINE Pay', const Color(0xFF00B900)),
                  const SizedBox(height: 4),
                  _buildPayTag('街口支付', const Color(0xFFE53935)),
                ],
              ),

              const SizedBox(width: 12),

              // 右欄：店名、回饋%、條件清單
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 店名列（店名 + badge 紅點）
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111111),
                                ),
                              ),
                              if (branchName != null)
                                Text(
                                  branchName,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (store.hasBadge)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 4, top: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // 回饋 XX%
                    Text(
                      '回饋 ${store.cashback}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A73E8),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 條件清單
                    ...store.conditions.map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: c.isRed
                                        ? const Color(0xFFE53935)
                                        : const Color(0xFF444444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  c.text,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: c.isRed
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: c.isRed
                                        ? const Color(0xFFE53935)
                                        : const Color(0xFF333333),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 16, thickness: 1, color: Color(0xFFF0F0F0)),

          // ── 下半：行動支付 chip 列 ────────────────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: store.payMethods
                .map((p) => _buildPayChip(p))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPayTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 8.5, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }

  Widget _buildPayChip(_PayMethod p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: p.color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
              child: Text(
                p.label[0],
                style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            p.label,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF555555)),
          ),
        ],
      ),
    );
  }

  // ── 會員 or 載具 Pill ─────────────────────────────────────────────────────

  Widget _buildMemberPill(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMemberOrCarrierSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '未完善',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE53935)),
            ),
            const SizedBox(width: 10),
            const Text(
              '會員 or 載具',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            // 三個切換點
            Row(
              children: List.generate(
                3,
                (i) => Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == 0 ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 會員 or 載具 底部 Sheet ───────────────────────────────────────────────

  void _showMemberOrCarrierSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(ctx).padding.bottom + 24,
        ),
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('選擇顯示類型',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _buildSheetItem(
              ctx,
              icon: Icons.person_outline,
              color: Colors.blue,
              title: '店家會員條碼',
              subtitle: '顯示該店家的會員條碼',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemberBarcodeScreen(
                      brandName: _kStores[_activeStoreId]!.name,
                    ),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildSheetItem(
              ctx,
              icon: Icons.receipt_long_outlined,
              color: Colors.indigo,
              title: '電子載具',
              subtitle: '顯示手機條碼載具',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CarrierInputScreen(),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetItem(
    BuildContext ctx, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 店家選擇 Sheet ─────────────────────────────────────────────────────────────

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
        20, 12, 20, MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            '選擇店家',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '選擇後將顯示對應的會員/支付條碼',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),
          ...stores.map((s) {
            final selected = selectedStore?['fullName'] == s['fullName'];
            return ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: Icon(
                Icons.store,
                color: selected ? Colors.blue : cs.onSurface.withOpacity(0.5),
              ),
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

// ── 會員 Tab ──────────────────────────────────────────────────────────────────

class MemberTab extends StatelessWidget {
  const MemberTab({super.key});

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
          // ── 行動支付 ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '行動支付',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
          ),

          // 四大超商分類（子類別各有 + 號）
          _SectionCard(
            title: '四大超商',
            icon: Icons.store_outlined,
            iconColor: Colors.orange,
            children: [
              _SubEntry(
                label: '全家',
                onAdd: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MemberBarcodeScreen(brandName: '全家便利商店'),
                    fullscreenDialog: true,
                  ),
                ),
              ),
              _SubEntry(
                label: '7-ELEVEN',
                onAdd: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MemberBarcodeScreen(brandName: '7-ELEVEN'),
                    fullscreenDialog: true,
                  ),
                ),
              ),
              _SubEntry(
                label: '萊爾富',
                onAdd: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MemberBarcodeScreen(brandName: '萊爾富'),
                    fullscreenDialog: true,
                  ),
                ),
              ),
              _SubEntry(
                label: 'OK',
                onAdd: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MemberBarcodeScreen(brandName: 'OK便利商店'),
                    fullscreenDialog: true,
                  ),
                ),
                divider: false,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 行動支付子類別
          _SectionCard(
            title: 'Pay',
            icon: Icons.payment_outlined,
            iconColor: Colors.green,
            children: [
              _SubEntry(
                label: 'Line Pay',
                onAdd: () {},
              ),
              _SubEntry(
                label: 'JKO Pay',
                onAdd: () {},
                divider: false,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ── 載具 ────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    '載具',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CarrierInputScreen(),
                    fullscreenDialog: true,
                  ),
                ),
                tooltip: '新增載具',
              ),
            ],
          ),

          _EntryCard(
            icon: Icons.receipt_long,
            iconColor: Colors.indigo,
            title: '電子載具',
            subtitle: '手機條碼 /XXXXXXX',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CarrierInputScreen(),
                fullscreenDialog: true,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── 其他 ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '其他',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
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
              children: const [
                Text('快速出示會員條碼與電子載具，方便結帳使用。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 設定 Tab ──────────────────────────────────────────────────────────────────

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
            child: Text(
              '一般',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
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
              children: const [
                Text('快速出示會員條碼與電子載具，方便結帳使用。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 區塊卡片（帶子項目，子項目有 + 號） ───────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          // 區塊標題列（無 + 號）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...children,
        ],
      ),
    );
  }
}

// ── 子項目列（各有 + 號） ─────────────────────────────────────────────────────

class _SubEntry extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;
  final bool divider;

  const _SubEntry({
    required this.label,
    required this.onAdd,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(label, style: const TextStyle(fontSize: 14)),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed: onAdd,
            tooltip: '新增 $label',
          ),
        ),
        if (divider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

// ── 通用入口卡片 ──────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
