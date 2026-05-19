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
// 狀態：
//   _selectedStore  → 從附近店家清單選中的那家（session 層級，APP 殺掉即清除）
//   _activeCard     → 目前三個按鈕中選中哪個（member / payment / carrier）
//   _displayList    → 附近店家清單（定位後取得）
//   _isLoading      → 定位 / API 載入中
//
// 邏輯：
//   - 點「迴轉」圖示 → 重新定位並更新清單，同時清除 _selectedStore
//   - 點清單任一行  → 底部 Sheet 選店，選完後 _selectedStore 更新
//   - 三個按鈕切換  → 顯示對應的條碼區（從 CarrierInputScreen / MemberBarcodeScreen 邏輯借用）

enum _ActiveCard { member, payment, carrier }

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

  // 當前選中店家（session 層級）
  Map<String, String>? _selectedStore;

  // 三按鈕狀態
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
      // 還沒定位過，先提示
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
          setState(() => _selectedStore = store);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ── 進入條碼 / 載具畫面 ───────────────────────────────────────────────────

  void _navigateToActiveScreen() {
    switch (_activeCard) {
      case _ActiveCard.member:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberBarcodeScreen(
              brandName: _selectedStore?['name'],
            ),
            fullscreenDialog: true,
          ),
        );
      case _ActiveCard.payment:
        // 行動支付目前導向載具畫面（未來可換成行動支付選單）
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CarrierInputScreen(),
            fullscreenDialog: true,
          ),
        );
      case _ActiveCard.carrier:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CarrierInputScreen(),
            fullscreenDialog: true,
          ),
        );
    }
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
          // 定位授權
          IconButton(
            onPressed: _requestPermission,
            icon: const Icon(Icons.location_on_outlined),
            tooltip: '定位權限',
          ),
          // 重新定位（迴轉圖示）
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
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 主卡片：店家名 + 三按鈕 + 條碼區 ──────────────
                        _buildMainCard(context),
                        const SizedBox(height: 16),

                        // ── 附近店家清單（取代原本的「店家優惠資訊」） ────
                        _buildNearbySection(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── 主卡片 ────────────────────────────────────────────────────────────────

  Widget _buildMainCard(BuildContext context) {
    final hasStore = _selectedStore != null;
    final storeName = hasStore ? _selectedStore!['name']! : '尚未選擇店家';
    final storeFullName = hasStore ? _selectedStore!['fullName']! : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 店家名稱列
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasStore ? Colors.blue.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.store,
                  color: hasStore ? Colors.blue : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: hasStore ? null : Colors.grey,
                      ),
                    ),
                    if (storeFullName.isNotEmpty)
                      Text(
                        storeFullName,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              // 切換店家按鈕
              TextButton.icon(
                onPressed: _showStorePickerSheet,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('切換'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 三按鈕列
          Row(
            children: [
              _buildToggleBtn(
                label: '店家會員',
                icon: Icons.person_outline,
                active: _activeCard == _ActiveCard.member,
                onTap: () => setState(() => _activeCard = _ActiveCard.member),
              ),
              const SizedBox(width: 8),
              _buildToggleBtn(
                label: '行動支付',
                icon: Icons.payment_outlined,
                active: _activeCard == _ActiveCard.payment,
                onTap: () => setState(() => _activeCard = _ActiveCard.payment),
              ),
              const SizedBox(width: 8),
              _buildToggleBtn(
                label: '載具',
                icon: Icons.receipt_long_outlined,
                active: _activeCard == _ActiveCard.carrier,
                onTap: () => setState(() => _activeCard = _ActiveCard.carrier),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 條碼區（根據 _activeCard 顯示對應說明 + 入口按鈕）
          _buildBarcodeArea(hasStore),
        ],
      ),
    );
  }

  Widget _buildToggleBtn({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20, color: active ? Colors.white : Colors.grey.shade600),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeArea(bool hasStore) {
    // 未選店家時顯示提示
    if (!hasStore) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.touch_app_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              '請先點右上角 ↻ 定位\n再從下方選擇店家',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 各按鈕對應的說明文字
    final String title;
    final String subtitle;
    final IconData icon;

    switch (_activeCard) {
      case _ActiveCard.member:
        // 7-11 限定提示
        final is711 = _selectedStore!['name']!.contains('7-ELEVEN') ||
            _selectedStore!['name']!.contains('7-11');
        title = is711 ? '7-ELEVEN 會員條碼' : '${_selectedStore!['name']!} 會員條碼';
        subtitle = '點擊展示條碼給店員掃描';
        icon = Icons.person_outline;
      case _ActiveCard.payment:
        title = '行動支付';
        subtitle = '點擊選擇支付方式';
        icon = Icons.payment_outlined;
      case _ActiveCard.carrier:
        title = '電子載具';
        subtitle = '點擊展示載具條碼';
        icon = Icons.receipt_long_outlined;
    }

    return GestureDetector(
      onTap: _navigateToActiveScreen,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.blue.shade400),
          ],
        ),
      ),
    );
  }

  // ── 附近店家 Section ──────────────────────────────────────────────────────

  Widget _buildNearbySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '附近店家',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (_isLoading)
          const Center(child: CircularProgressIndicator.adaptive())
        else if (_displayList.isEmpty)
          _buildEmptyStoreHint()
        else
          ..._displayList.map((m) => _buildStoreRow(m)),
      ],
    );
  }

  Widget _buildEmptyStoreHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.store_mall_directory_outlined,
              size: 48, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            '點右上角 ↻ 偵測附近店家',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreRow(Map<String, String> m) {
    final isSelected = _selectedStore?['fullName'] == m['fullName'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: Colors.blue, width: 1.5)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.store,
              color: isSelected ? Colors.blue : Colors.blue.shade300),
        ),
        title: Text(m['name']!,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(m['fullName']!,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.blue)
            : const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => setState(() => _selectedStore = m),
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