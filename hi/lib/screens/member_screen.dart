import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../notifiers.dart';
import '../models/pay_platform.dart';
import '../features/invoice/presentation/screens/carrier_input_screen.dart';
import '../features/invoice/presentation/screens/member_barcode_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// 資料模型與對應表
// ════════════════════════════════════════════════════════════════════════════

class UserPaySetting {
  final String id;
  final String platform;
  final String level;
  final List<String> methods;
  UserPaySetting({required this.id, required this.platform, required this.level, required this.methods});
}

const Map<String, String> kPlatformTableMap = {
  '悠遊付': 'Easy_wallet',
  '街口支付': 'JKOPay',
  '全支付': 'PXPay_Plus',
  '台灣Pay': 'Taiwan_Pay',
  'LINE Pay': 'Line_Pay',
};

// ════════════════════════════════════════════════════════════════════════════
// MemberScreen
// ════════════════════════════════════════════════════════════════════════════

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  String? _expandedSection; // 'pay', 'member', 'carrier'
  List<UserPaySetting> _savedPaySettings = [];
  Map<String, String> _savedMembers = {};
  String? _savedCarrier;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 行動支付設定
    final payKeys = prefs.getKeys().where((k) => k.startsWith('pay_v3_'));
    List<UserPaySetting> tempPay = [];
    for (var k in payKeys) {
      final data = prefs.getStringList(k);
      if (data != null && data.length >= 2) {
        tempPay.add(UserPaySetting(
          id: k,
          platform: data[0],
          level: data[1],
          methods: data.sublist(2),
        ));
      }
    }

    // 2. 超商會員設定
    Map<String, String> tempMem = {};
    for (var brand in ['7-ELEVEN', '全家', '萊爾富', 'OK']) {
      final code = prefs.getString('member_barcode_$brand');
      if (code != null) tempMem[brand] = code;
    }

    // 3. 載具設定
    final carrier = prefs.getString('carrier_code');

    if (mounted) {
      setState(() {
        _savedPaySettings = tempPay;
        _savedMembers = tempMem;
        _savedCarrier = carrier;
      });
    }
  }

  // ── UI 佈局 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('會員', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 方格 1: 行動支付
          _buildMainBox('行動支付', Icons.account_balance_wallet, 'pay'),
          if (_expandedSection == 'pay') _buildPayContent(),
          const SizedBox(height: 12),

          // 方格 2: 會員
          _buildMainBox('會員', Icons.card_membership, 'member'),
          if (_expandedSection == 'member') _buildMemberContent(),
          const SizedBox(height: 12),

          // 方格 3: 載具
          _buildMainBox('載具', Icons.receipt_long, 'carrier'),
          if (_expandedSection == 'carrier') _buildCarrierContent(),
        ],
      ),
    );
  }

  Widget _buildMainBox(String title, IconData icon, String section) {
    final bool isOpen = _expandedSection == section;
    return GestureDetector(
      onTap: () => setState(() => _expandedSection = isOpen ? null : section),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 28),
            const SizedBox(width: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ── 行動支付區塊內容 ────────────────────────────────────────────────────────

  Widget _buildPayContent() {
    final platforms = ['悠遊付', '街口支付', '全支付', '台灣Pay', 'LINE Pay'];
    return Column(
      children: platforms.map((p) => _buildPlatformRow(p)).toList(),
    );
  }

  Widget _buildPlatformRow(String platformName) {
    final mySettings = _savedPaySettings.where((s) => s.platform == platformName).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              Text(platformName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                onPressed: () => _showConfigDialog(platformName),
              ),
            ],
          ),
          ...mySettings.map((s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text('${s.level == "0" ? "" : s.level + " | "}${s.methods.join(", ")}', style: const TextStyle(fontSize: 13))),
                _buildModifyBox(
                  onEdit: () => _showConfigDialog(platformName, existing: s),
                  onDelete: () => _deleteSetting(s.id)
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ── 會員區塊內容 ──────────────────────────────────────────────────────────

  Widget _buildMemberContent() {
    final stores = ['7-ELEVEN', '全家', '萊爾富', 'OK'];
    return Column(
      children: stores.map((s) => Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          title: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_savedMembers[s] ?? '尚未設定'),
          trailing: _buildModifyBox(
            onEdit: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => MemberBarcodeScreen(brandName: s)));
              _loadAllData();
            },
            onDelete: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('member_barcode_$s');
              _loadAllData();
            }
          ),
        ),
      )).toList(),
    );
  }

  // ── 載具區塊內容 ──────────────────────────────────────────────────────────

  Widget _buildCarrierContent() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.receipt, color: Colors.orange),
        title: Text(_savedCarrier ?? '尚未設定'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_savedCarrier == null) IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarrierInputScreen()));
              _loadAllData();
            }),
            if (_savedCarrier != null) _buildModifyBox(
              onEdit: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarrierInputScreen()));
                _loadAllData();
              },
              onDelete: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('carrier_code');
                _loadAllData();
              }
            ),
          ],
        ),
      ),
    );
  }

  // ── 修改按鈕（方框樣式） ────────────────────────────────────────────────────

  Widget _buildModifyBox({required VoidCallback onEdit, required VoidCallback onDelete}) {
    return PopupMenuButton<String>(
      onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'edit', child: Text('修改資料')),
        const PopupMenuItem(value: 'delete', child: Text('刪除', style: TextStyle(color: Colors.red))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: Colors.blue), borderRadius: BorderRadius.circular(8)),
        child: const Text('修改', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── 設定彈窗邏輯（動態從資料庫讀取等級與支付方式） ──────────────────────────

  Future<void> _showConfigDialog(String platform, {UserPaySetting? existing}) async {
    final dbPath = p.join(await getDatabasesPath(), 'pay_helper.db');
    final db = await openDatabase(dbPath);
    final String tableName = kPlatformTableMap[platform] ?? '';

    // 從各平台專屬資料表抓取資料
    final List<Map<String, dynamic>> levelsRaw = await db.query(tableName, columns: ['user_level']);
    final List<Map<String, dynamic>> methodsRaw = await db.query(tableName, columns: ['payment_method']);
    
    final List<String> levelOptions = levelsRaw.map((e) => e['user_level'].toString()).where((e) => e != 'null').toSet().toList();
    final List<String> methodOptions = methodsRaw.map((e) => e['payment_method'].toString()).where((e) => e != 'null').toSet().toList();

    String selectedLevel = existing?.level ?? (levelOptions.isNotEmpty ? levelOptions.first : '0');
    List<String> selectedMethods = existing != null ? List.from(existing.methods) : [];

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlgState) => AlertDialog(
        title: Text('$platform 設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (levelOptions.isNotEmpty && levelOptions.first != '0') ...[
                const Text('等級 (單選)', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedLevel,
                  items: levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setDlgState(() => selectedLevel = v!),
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                ),
                const SizedBox(height: 16),
              ],
              const Text('支付方式 (可複選)', style: TextStyle(fontWeight: FontWeight.bold)),
              ...methodOptions.map((m) => CheckboxListTile(
                title: Text(m, style: const TextStyle(fontSize: 14)),
                value: selectedMethods.contains(m),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setDlgState(() {
                  v! ? selectedMethods.add(m) : selectedMethods.remove(m);
                }),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () async {
            if (selectedMethods.isEmpty) return;
            final prefs = await SharedPreferences.getInstance();
            final id = existing?.id ?? 'pay_v3_${DateTime.now().millisecondsSinceEpoch}';
            await prefs.setStringList(id, [platform, selectedLevel, ...selectedMethods]);
            Navigator.pop(ctx);
            _loadAllData();
          }, child: const Text('儲存')),
        ],
      )),
    );
  }

  Future<void> _deleteSetting(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(id);
    _loadAllData();
  }
}
