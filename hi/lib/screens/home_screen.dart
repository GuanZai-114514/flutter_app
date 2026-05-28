import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_widget/barcode_widget.dart';

import '../notifiers.dart';
import '../models/discount_rule.dart';
import '../models/pay_platform.dart';
import '../models/store_info.dart';

// ════════════════════════════════════════════════════════════════════════════
// HomeScreen
// ════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  final List<String> dbKeywords;
  final bool dbReady;
  final VoidCallback onGoToMember;

  const HomeScreen({
    super.key,
    required this.dbKeywords,
    required this.dbReady,
    required this.onGoToMember,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const String _apiKey = 'AIzaSyAly-Vst9UhgyUmQTKFdaCtwNEbNBIzQu4';

  // ── 4 個圓圈槽（初始預設順序） ───────────────────────────────────────────
  // index 0 = 最左 = 當前選中（active）
  List<String> _slotOrder = ['fm', 'seven', 'hilife', 'ok'];
  String get _activeStoreId => _slotOrder.first;

  // 定位結果 storeId → fullName
  Map<String, String> _detectedFullNames = {};

  bool _isLoading = false;
  String _permissionMessage = '';

  // ── 傾斜偵測 ─────────────────────────────────────────────────────────────
  StreamSubscription? _accelSub;
  bool _isTilted = false;
  DateTime? _lastTiltChange;

  // ── 折扣規則 ─────────────────────────────────────────────────────────────
  Map<int, List<DiscountRule>> _discountsByStore = {};

  // ── 旋轉動畫 ─────────────────────────────────────────────────────────────
  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
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
    _spinCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // 加速度計：傾斜偵測
  // ════════════════════════════════════════════════════════════════════════

  void _startAccelerometer() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final shouldTilt   = event.y < -3.0;
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

  // ════════════════════════════════════════════════════════════════════════
  // 折扣規則
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _loadDiscountRules() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), 'pay_helper.db');
      if (!await databaseExists(dbPath)) return;
      final db = await openDatabase(dbPath, readOnly: true);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='discount_rules'",
      );
      if (tables.isEmpty) { await db.close(); return; }
      final discountRows = await db.query('discount_rules');
      final rules = discountRows.map(DiscountRule.fromMap).toList();
      final mapRows = await db.rawQuery(
        "SELECT rule_id, store_id FROM rule_store_map WHERE rule_type = 'discount'",
      );
      await db.close();
      final Map<int, List<DiscountRule>> byStore = {};
      for (final row in mapRows) {
        final ruleId  = (row['rule_id']  as num).toInt();
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

  int _storeDbId(String storeId) {
    switch (storeId) {
      case 'fm':     return 1;
      case 'seven':  return 2;
      case 'hilife': return 3;
      case 'ok':     return 4;
      default:       return 1;
    }
  }

  List<DiscountRule> _getBestDiscountsFor(String storeId) {
    final rules = _discountsByStore[_storeDbId(storeId)] ?? [];
    return List<DiscountRule>.from(rules)
      ..sort((a, b) {
        final r = b.equivalentRate.compareTo(a.equivalentRate);
        return r != 0 ? r : b.discountAmount.compareTo(a.discountAmount);
      });
  }

  bool _hasSpecialDiscount(String storeId) =>
      _getBestDiscountsFor(storeId).any((d) => d.isSpecial);

  // ════════════════════════════════════════════════════════════════════════
  // 行動支付開啟
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _launchPayApp(PayPlatform platform) async {
    final scheme = Platform.isIOS ? platform.iosScheme : platform.androidScheme;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('無法開啟 ${platform.label}')));
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 定位
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _updatePermissionMessage() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      _permissionMessage = status.isGranted
          ? ''
          : status.isPermanentlyDenied
              ? '定位權限已永久拒絕，請至設定開啟'
              : '尚未授權定位，請點右上角授權';
    });
  }

  Future<void> _startDetection() async {
    if (_isLoading || !widget.dbReady) return;
    setState(() => _isLoading = true);
    _spinCtrl.repeat();

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

      // 依距離順序匹配，最多 4 個不重複超商
      final newSlot = <String>[];
      final newFullNames = <String, String>{};

      for (final gName in names) {
        if (newSlot.length >= 4) break;
        final normalized = gName.replaceAll(' ', '').toLowerCase();
        for (final kw in widget.dbKeywords) {
          final k = kw.replaceAll(' ', '').toLowerCase();
          if (normalized.contains(k)) {
            final sid = _matchStoreId(kw);
            if (sid != null && !newSlot.contains(sid)) {
              newSlot.add(sid);
              newFullNames[sid] = gName;
              break;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          if (newSlot.isNotEmpty) {
            // 補齊到 4 個（用原有槽裡沒出現的補）
            for (final s in _slotOrder) {
              if (!newSlot.contains(s) && newSlot.length < 4) newSlot.add(s);
            }
            _slotOrder = newSlot.take(4).toList();
            _detectedFullNames = newFullNames;
          }
        });
        if (newSlot.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('偵測不到支援的便利商店')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ 偵測失敗: $e');
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('偵測失敗：$e')));
    } finally {
      if (mounted) {
        _spinCtrl.stop();
        _spinCtrl.reset();
        setState(() => _isLoading = false);
      }
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
          'maxResultCount': 10,
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
  // 圓圈點擊：點到的移到 index 0，其餘依序右移（循環）
  // ════════════════════════════════════════════════════════════════════════

  void _onSlotTap(int index) {
    if (index == 0) return; // 已是第一個，不動
    setState(() {
      final tapped = _slotOrder[index];
      _slotOrder.removeAt(index);
      _slotOrder.insert(0, tapped);
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
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
          // 旋轉定位圖標
          GestureDetector(
            onTap: _isLoading ? null : _startDetection,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: RotationTransition(
                turns: _spinCtrl,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 28,
                  color: _isLoading ? Colors.blue : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 權限提示橫幅
          if (_permissionMessage.isNotEmpty)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Material(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_permissionMessage,
                        style: const TextStyle(fontSize: 11, color: Colors.orange))),
                  ]),
                ),
              ),
            ),

          !widget.dbReady
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _buildBody(),

          // 傾斜 Overlay
          if (_isTilted) _buildTiltOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // ── 4 個圓圈 ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: _buildStoreSlots(),
        ),

        // ── 中央資訊卡 + 其他支付（可捲動）────────────────────────────
        Expanded(child: _buildInfoSection()),

        // ── 底部「會員 & 載具條碼」按鈕 ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: _buildMemberPill(),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // 4 個超商圓圈
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildStoreSlots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, _buildSlotCircle),
    );
  }

  Widget _buildSlotCircle(int index) {
    if (index >= _slotOrder.length) return const SizedBox(width: 72);

    final storeId  = _slotOrder[index];
    final isActive = index == 0;
    final hasSpecial = _hasSpecialDiscount(storeId);

    // 藍色漸層 = 平時回饋，紅色漸層 = 特殊回饋
    final gradColors = hasSpecial
        ? [const Color(0xFFFF6B6B), const Color(0xFFD32F2F)]
        : [const Color(0xFF64B5F6), const Color(0xFF1565C0)];

    final size = isActive ? 72.0 : 60.0;

    return GestureDetector(
      onTap: () => _onSlotTap(index),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isActive
                    ? gradColors
                    : [
                        gradColors[0].withOpacity(0.40),
                        gradColors[1].withOpacity(0.40),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: Colors.white, width: isActive ? 3.0 : 2.0),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: gradColors[1].withOpacity(0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [],
            ),
            child: Center(child: _slotLabel(storeId, isActive)),
          ),
          const SizedBox(height: 5),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: isActive ? 11 : 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive
                  ? const Color(0xFF111111)
                  : const Color(0xFF888888),
            ),
            child: Text(kStores[storeId]?.shortName ?? storeId),
          ),
        ],
      ),
    );
  }

  Widget _slotLabel(String id, bool isActive) {
    final size = isActive ? 42.0 : 34.0;
    String assetPath;
    switch (id) {
      case 'fm':
        assetPath = 'assets/images/fm.png';
        break;
      case 'seven':
        assetPath = 'assets/images/7-11.png';
        break;
      case 'hilife':
        assetPath = 'assets/images/hl.png';
        break;
      case 'ok':
        assetPath = 'assets/images/ok.png';
        break;
      default:
        return Icon(Icons.store, color: Colors.white, size: isActive ? 22 : 18);
    }
    return Image.asset(assetPath, width: size, height: size, fit: BoxFit.contain);
  }

  // ════════════════════════════════════════════════════════════════════════
  // 中央資訊區（可捲動）
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildInfoSection() {
    final storeId     = _activeStoreId;
    final store       = kStores[storeId]!;
    final discounts   = _getBestDiscountsFor(storeId);
    final topDiscount = discounts.isNotEmpty ? discounts.first : null;
    // 其他支付：最多 4 個，比第 1 名回饋低的
    final otherDiscounts = discounts.length > 1
        ? discounts.sublist(1, discounts.length > 5 ? 5 : discounts.length)
        : <DiscountRule>[];

    final branchName = _detectedFullNames[storeId];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── 主資訊框（店名 + 推薦支付）────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 12,
                    offset: Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // 店名列
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 46, height: 46,
                          child: _buildStoreLogo(storeId)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              branchName ?? store.name,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
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

                // 推薦支付標題
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text('推薦支付軟體',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF888888))),
                ),

                // 最佳折扣卡
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: topDiscount != null
                      ? _buildTopDiscountCard(topDiscount)
                      : _buildFallbackCard(store),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 其他可用支付（橫向捲動，最多 4 個）────────────────────────
          const Text('其他可用支付軟體',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF888888))),
          const SizedBox(height: 8),
          _buildOtherPayRow(otherDiscounts),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── 最佳折扣大卡 ──────────────────────────────────────────────────────────

  Widget _buildTopDiscountCard(DiscountRule rule) {
    final platformId = discountSoftwareToId(rule.paymentSoftware);
    final platform   = platformId != null ? platformById(platformId) : null;
    final isSpecial  = rule.isSpecial;
    final accent = isSpecial ? const Color(0xFFD32F2F) : const Color(0xFF1565C0);
    final bgColors = isSpecial
        ? [const Color(0xFFFFF5F5), const Color(0xFFFFEBEB)]
        : [const Color(0xFFF0F7FF), const Color(0xFFE3EEFF)];

    return GestureDetector(
      onTap: platform != null ? () => _launchPayApp(platform) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: bgColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          border: Border.all(color: accent, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // 平台色塊
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: Text(
                  rule.paymentSoftware.length <= 2
                      ? rule.paymentSoftware
                      : rule.paymentSoftware.substring(0, 2),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(rule.paymentSoftware,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: accent)),
                    if (isSpecial) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('限時特惠',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '回饋 ${(rule.equivalentRate * 100).toStringAsFixed(0)} %',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(rule.ruleDesc,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF666666)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── fallback 大卡（無 DB 折扣）────────────────────────────────────────────

  Widget _buildFallbackCard(StoreInfo store) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1565C0), width: 1.5),
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF0F7FF),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
                color: store.primaryColor,
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: _buildStoreLogo(store.id)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0))),
                Text('回饋 ${store.cashback}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1565C0))),
                ...store.conditions.take(2).map((c) => Text(c.text,
                    style: TextStyle(
                        fontSize: 11,
                        color: c.isRed
                            ? const Color(0xFFE53935)
                            : const Color(0xFF666666)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // 其他支付：橫向捲軸（比第 1 名低，最多 4 個）
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildOtherPayRow(List<DiscountRule> otherDiscounts) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: payMethodsNotifier,
      builder: (_, enabledIds, __) {
        final chips    = <_OtherChip>[];
        final shownIds = <String>{};

        // 排除已在第 1 名的平台
        final allDiscounts = _getBestDiscountsFor(_activeStoreId);
        if (allDiscounts.isNotEmpty) {
          final topId = discountSoftwareToId(allDiscounts.first.paymentSoftware);
          if (topId != null) shownIds.add(topId);
        }

        // DB 次優折扣（最多 4）
        for (final rule in otherDiscounts) {
          if (chips.length >= 4) break;
          final id       = discountSoftwareToId(rule.paymentSoftware);
          final platform = id != null ? platformById(id) : null;
          if (platform == null || shownIds.contains(id)) continue;
          shownIds.add(id!);
          chips.add(_OtherChip(
            platform:  platform,
            badge:     '${(rule.equivalentRate * 100).toStringAsFixed(0)}%',
            isSpecial: rule.isSpecial,
          ));
        }

        // 使用者設定的（補足名額）
        for (final id in enabledIds) {
          if (chips.length >= 4) break;
          if (shownIds.contains(id)) continue;
          final platform = platformById(id);
          if (platform == null) continue;
          shownIds.add(id);
          chips.add(_OtherChip(platform: platform));
        }

        // 全空時顯示引導
        if (chips.isEmpty) {
          return GestureDetector(
            onTap: widget.onGoToMember,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('+ 前往「會員」設定行動支付',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1A73E8))),
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: chips
                .map((chip) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _buildOtherChipWidget(chip),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildOtherChipWidget(_OtherChip chip) {
    final accent = chip.isSpecial
        ? const Color(0xFFD32F2F)
        : const Color(0xFF1565C0);
    final hasBadge = chip.badge != null;

    return GestureDetector(
      onTap: () => _launchPayApp(chip.platform),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: hasBadge ? accent : const Color(0xFFE8E8E8),
              width: hasBadge ? 1.5 : 1.0),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0x07000000),
                blurRadius: 4,
                offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: chip.platform.color,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                child: Text(
                  chip.platform.iconText.replaceAll('\n', '')[0],
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chip.platform.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF222222))),
                if (hasBadge)
                  Text('回饋 ${chip.badge}',
                      style: TextStyle(
                          fontSize: 10,
                          color: accent,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // 超商 Logo（卡片內）
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildStoreLogo(String id) {
    String assetPath;
    switch (id) {
      case 'fm':
        assetPath = 'assets/images/fm.png';
        break;
      case 'seven':
        assetPath = 'assets/images/7-11.png';
        break;
      case 'hilife':
        assetPath = 'assets/images/hl.png';
        break;
      case 'ok':
        assetPath = 'assets/images/ok.png';
        break;
      default:
        return const Icon(Icons.store, size: 28);
    }
    return Image.asset(assetPath, fit: BoxFit.contain);
  }

  // ════════════════════════════════════════════════════════════════════════
  // 底部「會員 & 載具條碼」膠囊按鈕
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildMemberPill() {
    return ValueListenableBuilder<bool>(
      valueListenable: carrierSetupNotifier,
      builder: (_, carrierReady, __) {
        return ValueListenableBuilder<Map<String, bool>>(
          valueListenable: memberSetupNotifier,
          builder: (_, memberMap, __) {
            final isReady = carrierReady || memberMap.values.any((v) => v);
            return GestureDetector(
              onTap: widget.onGoToMember,
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
                      isReady
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isReady ? Colors.white : const Color(0xFFCCCCCC),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '會員 & 載具條碼',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isReady
                            ? Colors.white
                            : const Color(0xFF333333),
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

  // ════════════════════════════════════════════════════════════════════════
  // 傾斜 Overlay
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildTiltOverlay() {
    return AnimatedOpacity(
      opacity: _isTilted ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: RotatedBox(
            quarterTurns: 2,
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
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
                        Text('請掃描以下條碼',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TiltBarcodeSection(
                    title: '會員條碼',
                    icon: Icons.person_outline,
                    prefKeyCode:
                        'member_barcode_${kStores[_activeStoreId]?.name ?? "_generic"}',
                    prefKeyType:
                        'member_type_${kStores[_activeStoreId]?.name ?? "_generic"}',
                  ),
                  const SizedBox(height: 20),
                  const _TiltCarrierSection(),
                  const SizedBox(height: 20),
                  Text('將手機收回即可返回首頁',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
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
// 其他支付 chip 資料模型
// ════════════════════════════════════════════════════════════════════════════

class _OtherChip {
  final PayPlatform platform;
  final String? badge;
  final bool isSpecial;
  const _OtherChip({
    required this.platform,
    this.badge,
    this.isSpecial = false,
  });
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
  String  _type = 'code128';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString(widget.prefKeyCode);
    String? type = prefs.getString(widget.prefKeyType);
    if (code == null) {
      for (final brand in [
        '全家便利商店', '7-ELEVEN', '萊爾富', 'OK便利商店', '_generic'
      ]) {
        code = prefs.getString('member_barcode_$brand');
        type = prefs.getString('member_type_$brand');
        if (code != null) break;
      }
    }
    if (!mounted) return;
    setState(() { _code = code; _type = type ?? 'code128'; });
  }

  @override
  Widget build(BuildContext context) {
    if (_code == null) {
      return _emptyBox(context, Icons.person_outline, '未設定${widget.title}');
    }
    Barcode barcode;
    switch (_type) {
      case 'ean13':  barcode = Barcode.ean13(); break;
      case 'qrCode': barcode = Barcode.qrCode(); break;
      default:       barcode = Barcode.code128();
    }
    final isQR = _type == 'qrCode';
    return _barcodeBox(
      label: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(widget.icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(widget.title,
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      ]),
      barcode: isQR
          ? Center(child: BarcodeWidget(
              barcode: barcode, data: _code!,
              width: 150, height: 150, drawText: false))
          : LayoutBuilder(builder: (ctx, c) => BarcodeWidget(
              barcode: barcode,
              data: _code!.trim().toUpperCase().replaceAll(RegExp(r'\s'), ''),
              width: c.maxWidth, height: 100, drawText: false,
              padding: const EdgeInsets.symmetric(horizontal: 24))),
      code: _code!,
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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('carrier_code');
    if (!mounted) return;
    setState(() { _code = raw?.trim().toUpperCase(); });
  }

  @override
  Widget build(BuildContext context) {
    if (_code == null) {
      return _emptyBox(context, Icons.receipt_long, '未設定電子載具');
    }
    return _barcodeBox(
      label: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text('電子載具', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      ]),
      barcode: LayoutBuilder(builder: (ctx, c) => BarcodeWidget(
        barcode: Barcode.code128(), data: _code!,
        width: c.maxWidth, height: 100, drawText: false,
        padding: const EdgeInsets.symmetric(horizontal: 24))),
      code: _code!,
    );
  }
}

// ── 共用工具 ──────────────────────────────────────────────────────────────────

Widget _emptyBox(BuildContext context, IconData icon, String text) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: Colors.grey.shade400, size: 16),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );
}

Widget _barcodeBox({
  required Widget label,
  required Widget barcode,
  required String code,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))
      ],
    ),
    child: Column(children: [
      label,
      const SizedBox(height: 12),
      barcode,
      const SizedBox(height: 8),
      Text(code,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 13, letterSpacing: 1.5)),
    ]),
  );
}
