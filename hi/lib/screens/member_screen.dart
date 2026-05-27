import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifiers.dart';
import '../models/pay_platform.dart';
import 'package:hi/features/invoice/presentation/screens/carrier_input_screen.dart';
import 'package:hi/features/invoice/presentation/screens/member_barcode_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════════════════

class PayMethodEntry {
  final String id;
  final String platformId;
  final String level;
  final List<String> methods;

  PayMethodEntry({
    required this.id,
    required this.platformId,
    required this.level,
    required this.methods,
  });
}

class CarrierEntry {
  final String id;
  final String code;
  CarrierEntry({required this.id, required this.code});
}

const _kLevels = ['一般', '銀卡', '金卡', '白金卡', 'VIP'];
const _kPayMethods = ['QR Code', '感應付款', '條碼', '綁定信用卡', '綁定金融卡'];

// ════════════════════════════════════════════════════════════════════════════
// MemberScreen
// ════════════════════════════════════════════════════════════════════════════

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  final Map<String, List<PayMethodEntry>> _payEntries = {};
  final List<CarrierEntry> _carriers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final platform in kPayPlatforms) {
      final raw = prefs.getStringList('pay_entries_${platform.id}') ?? [];
      final entries = raw.map((s) {
        final parts = s.split('||');
        if (parts.length < 3) return null;
        return PayMethodEntry(
          id: parts[0], platformId: platform.id, level: parts[1],
          methods: parts[2].split(',').where((e) => e.isNotEmpty).toList(),
        );
      }).whereType<PayMethodEntry>().toList();
      if (entries.isNotEmpty) _payEntries[platform.id] = entries;
    }
    final carrierRaw = prefs.getStringList('carrier_entries') ?? [];
    for (final s in carrierRaw) {
      final parts = s.split('||');
      if (parts.length >= 2) _carriers.add(CarrierEntry(id: parts[0], code: parts[1]));
    }
    if (mounted) setState(() {});
  }

  Future<void> _savePayEntries(String platformId) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _payEntries[platformId] ?? [];
    await prefs.setStringList('pay_entries_$platformId',
        entries.map((e) => '${e.id}||${e.level}||${e.methods.join(',')}').toList());
  }

  Future<void> _saveCarriers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('carrier_entries',
        _carriers.map((c) => '${c.id}||${c.code}').toList());
    if (_carriers.isNotEmpty) {
      await prefs.setString('carrier_code', _carriers.first.code);
    } else {
      await prefs.remove('carrier_code');
    }
    carrierSetupNotifier.value = _carriers.isNotEmpty;
  }

  // ── 行動支付 CRUD ─────────────────────────────────────────────────────────

  Future<void> _addPayEntry(String platformId) async {
    final result = await showModalBottomSheet<PayMethodEntry?>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayEntrySheet(platformId: platformId),
    );
    if (result == null) return;
    setState(() => _payEntries.putIfAbsent(platformId, () => []).add(result));
    await _savePayEntries(platformId);
    final current = List<String>.from(payMethodsNotifier.value);
    if (!current.contains(platformId)) {
      current.add(platformId);
      payMethodsNotifier.value = current;
      savePayMethods(current);
    }
  }

  Future<void> _editPayEntry(String platformId, PayMethodEntry entry) async {
    final result = await showModalBottomSheet<PayMethodEntry?>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayEntrySheet(platformId: platformId, existing: entry),
    );
    if (result == null) return;
    setState(() {
      final list = _payEntries[platformId]!;
      final idx = list.indexWhere((e) => e.id == entry.id);
      if (idx != -1) list[idx] = result;
    });
    await _savePayEntries(platformId);
  }

  Future<void> _deletePayEntry(String platformId, String entryId) async {
    setState(() {
      _payEntries[platformId]?.removeWhere((e) => e.id == entryId);
      if (_payEntries[platformId]?.isEmpty ?? false) {
        _payEntries.remove(platformId);
        final current = List<String>.from(payMethodsNotifier.value);
        current.remove(platformId);
        payMethodsNotifier.value = current;
        savePayMethods(current);
      }
    });
    await _savePayEntries(platformId);
  }

  // ── 載具 CRUD ─────────────────────────────────────────────────────────────

  Future<void> _addCarrier() async {
    final code = await _showCarrierDialog(null);
    if (code == null || code.trim().isEmpty) return;
    setState(() => _carriers.add(CarrierEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      code: code.trim().toUpperCase(),
    )));
    await _saveCarriers();
  }

  Future<void> _editCarrier(CarrierEntry carrier) async {
    final code = await _showCarrierDialog(carrier.code);
    if (code == null) return;
    if (code.trim().isEmpty) { await _deleteCarrier(carrier.id); return; }
    setState(() {
      final idx = _carriers.indexWhere((c) => c.id == carrier.id);
      if (idx != -1) _carriers[idx] = CarrierEntry(id: carrier.id, code: code.trim().toUpperCase());
    });
    await _saveCarriers();
  }

  Future<void> _deleteCarrier(String id) async {
    setState(() => _carriers.removeWhere((c) => c.id == id));
    await _saveCarriers();
  }

  Future<String?> _showCarrierDialog(String? initial) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? '新增載具' : '修改載具'),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: const InputDecoration(
              hintText: '/XXXXXXX', border: OutlineInputBorder()),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          if (initial != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('刪除', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('儲存')),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('會員', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── 行動支付 ──────────────────────────────────────────────────
          _SectionHeader(title: '行動支付', subtitle: '點選平台右側 + 新增設定'),
          const SizedBox(height: 8),
          ...kPayPlatforms.map((platform) => _PlatformGroup(
            platform: platform,
            entries: _payEntries[platform.id] ?? [],
            onAdd: () => _addPayEntry(platform.id),
            onEdit: (e) => _editPayEntry(platform.id, e),
            onDelete: (e) => _deletePayEntry(platform.id, e.id),
          )),

          const SizedBox(height: 24),

          // ── 超商會員 ──────────────────────────────────────────────────
          _SectionHeader(title: '會員'),
          const SizedBox(height: 8),
          _buildMemberSection(),

          const SizedBox(height: 24),

          // ── 電子載具 ──────────────────────────────────────────────────
          _SectionHeader(title: '電子載具', actionLabel: '+ 新增', onAction: _addCarrier),
          const SizedBox(height: 8),
          _buildCarrierSection(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── 超商會員區塊 ──────────────────────────────────────────────────────────

  Widget _buildMemberSection() {
    const stores = [
      ('fm',     '全家便利商店', '全家',    Color(0xFF003087)),
      ('seven',  '7-ELEVEN',   '7-11',    Color(0xFFEF6C00)),
      ('hilife', '萊爾富',      'Hi-Life', Color(0xFFE53935)),
      ('ok',     'OK便利商店',  'OK',      Color(0xFFE53935)),
    ];
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: memberSetupNotifier,
      builder: (_, memberMap, __) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            children: stores.asMap().entries.map((e) {
              final idx = e.key;
              final (id, brandName, shortName, color) = e.value;
              final isSetup = memberMap[id] ?? false;
              return Column(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(shortName[0],
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))),
                  ),
                  title: Text(shortName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(isSetup ? '已設定 ✓' : '點擊設定',
                      style: TextStyle(fontSize: 12,
                          color: isSetup ? const Color(0xFF43A047) : Colors.grey[400])),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isSetup) const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 20),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                  ]),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => MemberBarcodeScreen(brandName: brandName),
                        fullscreenDialog: true));
                    final updated = Map<String, bool>.from(memberSetupNotifier.value);
                    updated[id] = true;
                    memberSetupNotifier.value = updated;
                  },
                ),
                if (idx < stores.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }

  // ── 電子載具區塊 ──────────────────────────────────────────────────────────

  Widget _buildCarrierSection() {
    if (_carriers.isEmpty) {
      return GestureDetector(
        onTap: _addCarrier,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_circle_outline, color: Colors.grey[400], size: 20),
            const SizedBox(width: 8),
            Text('點此新增電子載具', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ]),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: _carriers.asMap().entries.map((e) {
          final idx = e.key;
          final carrier = e.value;
          return Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long, color: Colors.indigo, size: 20),
              ),
              title: Text(carrier.code, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1)),
              subtitle: const Text('手機條碼載具', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: _EditButton(
                onEdit: () => _editCarrier(carrier),
                onDelete: () => _deleteCarrier(carrier.id),
              ),
            ),
            if (idx < _carriers.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ]);
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 行動支付平台群組
// ════════════════════════════════════════════════════════════════════════════

class _PlatformGroup extends StatelessWidget {
  final PayPlatform platform;
  final List<PayMethodEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<PayMethodEntry> onEdit;
  final ValueChanged<PayMethodEntry> onDelete;

  const _PlatformGroup({
    required this.platform, required this.entries,
    required this.onAdd, required this.onEdit, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(children: [
        // 平台標頭
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: platform.color, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(platform.iconText.replaceAll('\n', '')[0],
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(platform.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新增', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: platform.color,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ]),
        ),
        // 條目列表
        if (entries.isNotEmpty) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...entries.asMap().entries.map((e) {
            final idx = e.key;
            final entry = e.value;
            return Column(children: [
              _PayEntryTile(
                entry: entry, platformColor: platform.color,
                onEdit: () => onEdit(entry), onDelete: () => onDelete(entry),
              ),
              if (idx < entries.length - 1) const Divider(height: 1, indent: 56, endIndent: 16),
            ]);
          }),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 行動支付條目 Tile
// ════════════════════════════════════════════════════════════════════════════

class _PayEntryTile extends StatelessWidget {
  final PayMethodEntry entry;
  final Color platformColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PayEntryTile({
    required this.entry, required this.platformColor,
    required this.onEdit, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: platformColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: platformColor.withOpacity(0.3)),
          ),
          child: Text(entry.level, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w700, color: platformColor)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(spacing: 4, runSpacing: 4,
            children: entry.methods.map((m) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(m, style: const TextStyle(fontSize: 10, color: Color(0xFF555555))),
            )).toList(),
          ),
        ),
        const SizedBox(width: 4),
        _EditButton(onEdit: onEdit, onDelete: onDelete),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 新增 / 修改 BottomSheet
// ════════════════════════════════════════════════════════════════════════════

class _PayEntrySheet extends StatefulWidget {
  final String platformId;
  final PayMethodEntry? existing;
  const _PayEntrySheet({required this.platformId, this.existing});

  @override
  State<_PayEntrySheet> createState() => _PayEntrySheetState();
}

class _PayEntrySheetState extends State<_PayEntrySheet> {
  String? _selectedLevel;
  final Set<String> _selectedMethods = {};
  bool _levelOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedLevel = widget.existing!.level;
      _selectedMethods.addAll(widget.existing!.methods);
    }
  }

  void _save() {
    if (_selectedLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請選擇等級'), behavior: SnackBarBehavior.floating));
      return;
    }
    if (_selectedMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請至少選擇一種支付方式'), behavior: SnackBarBehavior.floating));
      return;
    }
    Navigator.pop(context, PayMethodEntry(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      platformId: widget.platformId,
      level: _selectedLevel!,
      methods: _selectedMethods.toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final platform = platformById(widget.platformId);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            // 標題
            Row(children: [
              if (platform != null)
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: platform.color, borderRadius: BorderRadius.circular(7)),
                  child: Center(child: Text(platform.iconText.replaceAll('\n', '')[0],
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white))),
                ),
              const SizedBox(width: 10),
              Text(
                widget.existing == null ? '新增 ${platform?.label ?? ''} 設定' : '修改 ${platform?.label ?? ''} 設定',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 20),

            // 等級（下拉單選）
            const Text('等級', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _levelOpen = !_levelOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _levelOpen ? (platform?.color ?? Colors.blue) : const Color(0xFFDDDDDD),
                    width: _levelOpen ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Expanded(child: Text(_selectedLevel ?? '請選擇等級',
                      style: TextStyle(fontSize: 14,
                          color: _selectedLevel != null ? Colors.black : Colors.grey[400]))),
                  Icon(_levelOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.grey[500]),
                ]),
              ),
            ),
            if (_levelOpen)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white, border: Border.all(color: const Color(0xFFDDDDDD)),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: Column(children: _kLevels.asMap().entries.map((e) {
                  final idx = e.key; final level = e.value;
                  final selected = _selectedLevel == level;
                  return Column(children: [
                    InkWell(
                      onTap: () => setState(() { _selectedLevel = level; _levelOpen = false; }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Expanded(child: Text(level, style: TextStyle(fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? (platform?.color ?? Colors.blue) : Colors.black))),
                          if (selected) Icon(Icons.check, size: 16, color: platform?.color ?? Colors.blue),
                        ]),
                      ),
                    ),
                    if (idx < _kLevels.length - 1) const Divider(height: 1, indent: 14, endIndent: 14),
                  ]);
                }).toList()),
              ),

            const SizedBox(height: 16),

            // 支付方式（複選）
            const Text('支付方式（可複選）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _kPayMethods.map((method) {
                final selected = _selectedMethods.contains(method);
                return FilterChip(
                  label: Text(method), selected: selected,
                  onSelected: (val) => setState(() => val ? _selectedMethods.add(method) : _selectedMethods.remove(method)),
                  selectedColor: (platform?.color ?? Colors.blue).withOpacity(0.15),
                  checkmarkColor: platform?.color ?? Colors.blue,
                  labelStyle: TextStyle(fontSize: 13,
                      color: selected ? (platform?.color ?? Colors.blue) : Colors.black87,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  side: BorderSide(color: selected ? (platform?.color ?? Colors.blue) : const Color(0xFFDDDDDD)),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('取消'),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: platform?.color ?? Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('儲存', style: TextStyle(fontSize: 15)),
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 修改按鈕（popup：修改 / 刪除）
// ════════════════════════════════════════════════════════════════════════════

class _EditButton extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _EditButton({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (val) { if (val == 'edit') onEdit(); if (val == 'delete') onDelete(); },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Row(children: [
          Icon(Icons.edit_outlined, size: 18, color: Colors.black54), SizedBox(width: 10), Text('修改'),
        ])),
        const PopupMenuItem(value: 'delete', child: Row(children: [
          Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10),
          Text('刪除', style: TextStyle(color: Colors.red)),
        ])),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('修改', style: TextStyle(fontSize: 12, color: Color(0xFF555555))),
          SizedBox(width: 2),
          Icon(Icons.expand_more, size: 14, color: Color(0xFF888888)),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 區塊標頭
// ════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.subtitle, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Expanded(child: Text(subtitle!, style: const TextStyle(fontSize: 11, color: Color(0xFF888888)))),
      ] else
        const Spacer(),
      if (actionLabel != null && onAction != null)
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
            child: Text(actionLabel!, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: Color(0xFF1A73E8))),
          ),
        ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PaymentBarcodeScreen
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
    _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((event) {
      final shouldFlip = event.y < -3;
      if (shouldFlip != _isFlipped && mounted) setState(() => _isFlipped = shouldFlip);
    });
  }

  Future<void> _setBrightness() async {
    try {
      _originalBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(1.0);
    } catch (e) { debugPrint('⚠️ 亮度設定失敗: $e'); }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    ScreenBrightness().setScreenBrightness(_originalBrightness).catchError((_) {});
    super.dispose();
  }

  Future<void> _launchApp(PayPlatform platform) async {
    final scheme = Platform.isIOS ? platform.iosScheme : platform.androidScheme;
    if (scheme != null) {
      final uri = Uri.parse(scheme);
      if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); return; }
    }
    if (platform.universalUrl != null) {
      await launchUrl(Uri.parse(platform.universalUrl!), mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('無法開啟 ${platform.label}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = platformById(widget.platformId);
    if (platform == null) return const Scaffold(body: Center(child: Text('找不到支付平台')));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.white,
        title: Text(platform.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Center(
        child: AnimatedRotation(
          duration: const Duration(milliseconds: 300),
          turns: _isFlipped ? 0.5 : 0.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: platform.color, borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: platform.color.withOpacity(0.35),
                      blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Center(child: Text(platform.iconText,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                        color: Colors.white, height: 1.3),
                    textAlign: TextAlign.center)),
              ),
              const SizedBox(height: 28),
              Text(platform.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                platform.universalUrl != null
                    ? '點擊下方按鈕開啟 ${platform.label} APP 進行支付'
                    : '請使用裝置內建 ${platform.label} 進行支付',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]), textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              if (platform.iosScheme != null || platform.androidScheme != null || platform.universalUrl != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _launchApp(platform),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text('開啟 ${platform.label}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: platform.color,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 36),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.screen_rotation, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('傾斜手機，畫面自動翻轉給店員看',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}