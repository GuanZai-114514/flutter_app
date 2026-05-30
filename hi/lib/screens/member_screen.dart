import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifiers.dart';
import '../models/pay_platform.dart';
import '../features/invoice/presentation/screens/carrier_input_screen.dart';
import '../features/invoice/presentation/screens/member_barcode_screen.dart';
import 'payment_setting_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════════════════

class UserPaySetting {
  final String id;
  final String platform;
  final String level;
  final List<String> methods;

  UserPaySetting({
    required this.id,
    required this.platform,
    required this.level,
    required this.methods,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// MemberScreen
// ════════════════════════════════════════════════════════════════════════════

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  String? _expandedSection; // 'member', 'carrier'
  Map<String, String> _savedMembers = {};
  String? _savedCarrier;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();

    // ── 1. 加載超商會員設定 ──────────────────────────────────────
    Map<String, String> tempMem = {};
    final storeBrands = ['7-ELEVEN', '全家', '萊爾富', 'OK'];
    
    for (var brand in storeBrands) {
      final code = prefs.getString('member_barcode_$brand');
      if (code != null) {
        tempMem[brand] = code;
      }
    }

    // ── 2. 加載載具設定 ──────────────────────────────────────────
    final carrier = prefs.getString('carrier_code');

    if (mounted) {
      setState(() {
        _savedMembers = tempMem;
        _savedCarrier = carrier;
      });
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          '會員',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 方格 1: 行動支付 (跳轉型) ──────────────────────────
          _buildActionBox(
            title: '行動支付',
            icon: Icons.account_balance_wallet,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PaymentSettingScreen(),
                ),
              );
              _loadAllData();
            },
          ),
          
          const SizedBox(height: 12),

          // ── 方格 2: 會員 (展開型) ──────────────────────────────
          _buildExpandableBox(
            title: '會員',
            icon: Icons.card_membership,
            section: 'member',
          ),
          if (_expandedSection == 'member') _buildMemberContent(),
          
          const SizedBox(height: 12),

          // ── 方格 3: 載具 (展開型) ──────────────────────────────
          _buildExpandableBox(
            title: '載具',
            icon: Icons.receipt_long,
            section: 'carrier',
          ),
          if (_expandedSection == 'carrier') _buildCarrierContent(),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── 組件：跳轉型方格 ──────────────────────────────────────────────────

  Widget _buildActionBox({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // ── 組件：展開型方格 ──────────────────────────────────────────────────

  Widget _buildExpandableBox({
    required String title,
    required IconData icon,
    required String section,
  }) {
    final bool isOpen = _expandedSection == section;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isOpen) {
            _expandedSection = null;
          } else {
            _expandedSection = section;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // ── 內容：超商會員列表 ───────────────────────────────────────────────

  Widget _buildMemberContent() {
    final stores = ['7-ELEVEN', '全家', '萊爾富', 'OK'];
    
    return Column(
      children: stores.map((s) {
        return Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            title: Text(
              s,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(_savedMembers[s] ?? '尚未設定條碼'),
            trailing: _buildModifyBox(
              onEdit: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MemberBarcodeScreen(brandName: s),
                  ),
                );
                _loadAllData();
              },
              onDelete: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('member_barcode_$s');
                await prefs.remove('member_type_$s');
                _loadAllData();
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 內容：載具管理區塊 ───────────────────────────────────────────────

  Widget _buildCarrierContent() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.receipt, color: Colors.orange),
        title: Text(_savedCarrier ?? '尚未設定載具號碼'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_savedCarrier == null)
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.blue),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CarrierInputScreen(),
                    ),
                  );
                  _loadAllData();
                },
              ),
            if (_savedCarrier != null)
              _buildModifyBox(
                onEdit: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CarrierInputScreen(),
                    ),
                  );
                  _loadAllData();
                },
                onDelete: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('carrier_code');
                  _loadAllData();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── 組件：共用修改按鈕方框 ────────────────────────────────────────────

  Widget _buildModifyBox({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Text('修改資料'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Text(
            '刪除',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '修改',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
