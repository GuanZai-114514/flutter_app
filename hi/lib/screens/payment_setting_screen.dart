import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════════
// 資料模型
// ═══════════════════════════════════════════════════════════════════════════════

enum PaymentMode { nfc, qr, other }

class PaymentConfig {
  final int? id; // SQLite rowid，新增時為 null
  final String platform;
  final String method;
  final String level;
  final PaymentMode mode;

  const PaymentConfig({
    this.id,
    required this.platform,
    required this.method,
    required this.level,
    required this.mode,
  });

  bool get isOther => mode == PaymentMode.other;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'platform': platform,
        'method': method,
        'level': level,
        'mode': mode.name,
      };

  factory PaymentConfig.fromMap(Map<String, dynamic> m) => PaymentConfig(
        id: m['id'] as int?,
        platform: m['platform'] as String,
        method: m['method'] as String,
        level: m['level'] as String,
        mode: PaymentMode.values.firstWhere(
          (e) => e.name == m['mode'],
          orElse: () => PaymentMode.qr,
        ),
      );

  PaymentConfig copyWith({
    int? id,
    String? platform,
    String? method,
    String? level,
    PaymentMode? mode,
  }) =>
      PaymentConfig(
        id: id ?? this.id,
        platform: platform ?? this.platform,
        method: method ?? this.method,
        level: level ?? this.level,
        mode: mode ?? this.mode,
      );

  /// 顯示用摘要（列表副標題）
  String get summary {
    if (isOther) return '其他支付方式';
    final parts = <String>[method];
    if (level != '無') parts.add(level);
    final modeLabel = mode == PaymentMode.nfc ? 'NFC 感應' : 'QR 掃碼';
    parts.add(modeLabel);
    return parts.join('  ·  ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SQLite Helper
// ═══════════════════════════════════════════════════════════════════════════════

class PaymentDb {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'payment_configs.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE payment_configs (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          platform TEXT    NOT NULL,
          method   TEXT    NOT NULL,
          level    TEXT    NOT NULL,
          mode     TEXT    NOT NULL
        )
      '''),
    );
  }

  static Future<List<PaymentConfig>> getAll() async {
    final rows = await (await db).query('payment_configs',
        orderBy: 'platform, id');
    return rows.map(PaymentConfig.fromMap).toList();
  }

  static Future<PaymentConfig> insert(PaymentConfig c) async {
    final id = await (await db).insert('payment_configs', c.toMap());
    return c.copyWith(id: id);
  }

  static Future<void> update(PaymentConfig c) async {
    await (await db).update(
      'payment_configs',
      c.toMap(),
      where: 'id = ?',
      whereArgs: [c.id],
    );
  }

  static Future<void> delete(int id) async {
    await (await db)
        .delete('payment_configs', where: 'id = ?', whereArgs: [id]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 靜態支付資料
// ═══════════════════════════════════════════════════════════════════════════════

class _PayData {
  static const List<String> platforms = [
    '悠遊付', '街口支付', '全支付', '台灣Pay', 'LINE Pay',
  ];

  static const Map<String, List<String>> methods = {
    '悠遊付': ['錢包or銀行帳戶', '其他支付方式'],
    '街口支付': ['街口帳戶', '街利存帳戶', '街利存帳戶_新戶', '其他支付方式'],
    '全支付': [
      '全支付帳戶', '國泰世華', '將來銀行', '華泰銀行',
      '國泰世華信用卡', '富邦銀行信用卡', '華泰銀行信用卡',
      '上海商銀信用卡', '玉山銀行信用卡', '聯邦銀行信用卡',
      '華南銀行信用卡', '台新銀行信用卡', '其他支付方式',
    ],
    '台灣Pay': [
      '台灣銀行', '土地銀行', '合作金庫銀行', '第一銀行',
      '華南銀行', '兆豐銀行', '台灣企銀', '彰化銀行',
      '台灣銀行信用卡', '土地銀行信用卡', '合作金庫銀行信用卡',
      '第一銀行信用卡', '彰化銀行信用卡', '兆豐銀行信用卡',
      '台灣企銀信用卡', '其他支付方式',
    ],
    'LINE Pay': [
      '中國信託LINE Pay聯名卡 Visa', '中國信託LINE Pay聯名卡 JCB',
      '富邦J卡', '聯邦賴點卡', '聯邦賴點卡_新戶',
      '永豐DAWAY卡', '永豐DAWAY卡_新戶', '其他支付方式',
    ],
  };

  static const Map<String, List<String>> levels = {
    '悠遊付': ['銀級', '金級', '白金級'],
    '街口支付': ['銅牌', '銀牌', '金牌', '白金', '尊爵'],
    '全支付': [],
    '台灣Pay': [],
    'LINE Pay': [],
  };

  static const Map<String, List<PaymentMode>> supportedModes = {
    '悠遊付': [PaymentMode.nfc, PaymentMode.qr],
    '街口支付': [PaymentMode.qr],
    '全支付': [PaymentMode.qr],
    '台灣Pay': [PaymentMode.qr],
    'LINE Pay': [PaymentMode.qr],
  };

  static bool hasLevel(String platform) =>
      (levels[platform] ?? []).isNotEmpty;

  static List<PaymentMode> getModes(String platform) =>
      supportedModes[platform] ?? [PaymentMode.qr];
}

// ═══════════════════════════════════════════════════════════════════════════════
// 主畫面
// ═══════════════════════════════════════════════════════════════════════════════

class PaymentSettingScreen extends StatefulWidget {
  const PaymentSettingScreen({super.key});

  @override
  State<PaymentSettingScreen> createState() => _PaymentSettingScreenState();
}

class _PaymentSettingScreenState extends State<PaymentSettingScreen> {
  // platform → 已儲存的設定清單
  Map<String, List<PaymentConfig>> _configsByPlatform = {};
  // 哪些平台展開中
  final Set<String> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await PaymentDb.getAll();
    final map = <String, List<PaymentConfig>>{};
    for (final c in all) {
      map.putIfAbsent(c.platform, () => []).add(c);
    }
    if (mounted) {
      setState(() {
        _configsByPlatform = map;
        _loading = false;
      });
    }
  }

  // ── 新增 ──────────────────────────────────────────────────────────────────

  Future<void> _onAdd(String platform) async {
    final result = await _showSheet(context, platform: platform);
    if (result == null) return;
    final saved = await PaymentDb.insert(result);
    setState(() {
      _configsByPlatform.putIfAbsent(platform, () => []).add(saved);
      _expanded.add(platform);
    });
  }

  // ── 編輯 ──────────────────────────────────────────────────────────────────

  Future<void> _onEdit(PaymentConfig config) async {
    final result =
        await _showSheet(context, platform: config.platform, editing: config);
    if (result == null) return;
    await PaymentDb.update(result);
    setState(() {
      final list = _configsByPlatform[config.platform]!;
      final idx = list.indexWhere((c) => c.id == result.id);
      if (idx >= 0) list[idx] = result;
    });
  }

  // ── 刪除 ──────────────────────────────────────────────────────────────────

  Future<void> _onDelete(PaymentConfig config) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除'),
        content: Text('確定刪除「${config.method}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    await PaymentDb.delete(config.id!);
    setState(() {
      final list = _configsByPlatform[config.platform]!;
      list.removeWhere((c) => c.id == config.id);
    });
  }

  // ── 開 Sheet ──────────────────────────────────────────────────────────────

  Future<PaymentConfig?> _showSheet(
    BuildContext context, {
    required String platform,
    PaymentConfig? editing,
  }) {
    return showModalBottomSheet<PaymentConfig>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(
        platform: platform,
        editing: editing,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('行動支付設定',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 區塊標題
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: const [
                  Icon(Icons.wallet, color: Colors.white, size: 15),
                  SizedBox(width: 6),
                  Text('行動支付',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),

          // 各平台
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              children: _PayData.platforms.asMap().entries.map((entry) {
                final idx = entry.key;
                final platform = entry.value;
                final isLast = idx == _PayData.platforms.length - 1;
                return _PlatformTile(
                  platform: platform,
                  configs: _configsByPlatform[platform] ?? [],
                  isExpanded: _expanded.contains(platform),
                  isLast: isLast,
                  onToggle: () => setState(() {
                    if (_expanded.contains(platform)) {
                      _expanded.remove(platform);
                    } else {
                      _expanded.add(platform);
                    }
                  }),
                  onAdd: () => _onAdd(platform),
                  onEdit: _onEdit,
                  onDelete: _onDelete,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 平台列（標題 + 展開區）
// ═══════════════════════════════════════════════════════════════════════════════

class _PlatformTile extends StatelessWidget {
  final String platform;
  final List<PaymentConfig> configs;
  final bool isExpanded;
  final bool isLast;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final ValueChanged<PaymentConfig> onEdit;
  final ValueChanged<PaymentConfig> onDelete;

  const _PlatformTile({
    required this.platform,
    required this.configs,
    required this.isExpanded,
    required this.isLast,
    required this.onToggle,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasConfigs = configs.isNotEmpty;

    return Column(
      children: [
        // ── 平台標題列 ──────────────────────────────────────────────────
        InkWell(
          onTap: hasConfigs ? onToggle : null,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(16),
            bottom: (isLast && !isExpanded)
                ? const Radius.circular(16)
                : Radius.zero,
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                // 平台名稱
                Expanded(
                  child: Row(children: [
                    Text(
                      platform,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C1E)),
                    ),
                    if (hasConfigs) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${configs.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0)),
                        ),
                      ),
                    ],
                  ]),
                ),

                // 展開箭頭（有設定時顯示）
                if (hasConfigs)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFAAAAAA), size: 20),
                  ),

                const SizedBox(width: 8),

                // 新增按鈕
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1565C0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 展開的設定清單 ────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: isExpanded
              ? Column(
                  children: [
                    Divider(
                        height: 1,
                        color: Colors.grey.shade100,
                        indent: 16,
                        endIndent: 16),
                    ...configs.asMap().entries.map((entry) {
                      final i = entry.key;
                      final cfg = entry.value;
                      final isLastItem = i == configs.length - 1;
                      return _ConfigRow(
                        config: cfg,
                        isLastItem: isLastItem && isLast,
                        onEdit: () => onEdit(cfg),
                        onDelete: () => onDelete(cfg),
                      );
                    }),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // 分隔線（非最後一個平台）
        if (!isLast)
          Divider(
              height: 1,
              color: Colors.grey.shade100,
              indent: 16,
              endIndent: 16),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 單筆設定列
// ═══════════════════════════════════════════════════════════════════════════════

class _ConfigRow extends StatelessWidget {
  final PaymentConfig config;
  final bool isLastItem;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConfigRow({
    required this.config,
    required this.isLastItem,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final modeIcon = config.isOther
        ? Icons.more_horiz
        : config.mode == PaymentMode.nfc
            ? Icons.nfc_rounded
            : Icons.qr_code_2_rounded;
    final modeColor = config.isOther
        ? Colors.grey
        : config.mode == PaymentMode.nfc
            ? Colors.blue.shade600
            : Colors.green.shade600;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: isLastItem
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : BorderRadius.zero,
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 模式圖示
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: modeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(modeIcon, color: modeColor, size: 18),
            ),
            const SizedBox(width: 12),

            // 摘要文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.method == '其他支付方式'
                        ? '其他支付方式'
                        : config.method,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.isOther
                        ? '直接開啟 App 付款'
                        : '${config.level != '無' ? '${config.level}  ·  ' : ''}${config.mode == PaymentMode.nfc ? 'NFC 感應' : 'QR 掃碼'}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),

            // 編輯按鈕
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF1565C0),
              ),
              child: const Text('編輯',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),

            // 刪除按鈕
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.remove_circle,
                  color: Colors.red.shade400, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom Sheet（新增 / 編輯）
// ═══════════════════════════════════════════════════════════════════════════════

class _PaymentSheet extends StatefulWidget {
  final String platform;
  final PaymentConfig? editing; // null = 新增

  const _PaymentSheet({required this.platform, this.editing});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late String? _method;
  late String? _level;
  late PaymentMode? _mode;

  bool get _isEditing => widget.editing != null;
  bool get _isOther => _method == '其他支付方式';

  bool get _canConfirm {
    if (_method == null) return false;
    if (_isOther) return true;
    if (_mode == null) return false;
    if (_PayData.hasLevel(widget.platform) && _level == null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _method = e?.method;
    _level = e?.level == '無' ? null : e?.level;
    _mode = e?.isOther == true ? null : e?.mode;
  }

  void _onConfirm() {
    if (!_canConfirm) return;
    final config = PaymentConfig(
      id: widget.editing?.id,
      platform: widget.platform,
      method: _method!,
      level: _isOther
          ? '無'
          : (_PayData.hasLevel(widget.platform) ? _level! : '無'),
      mode: _isOther ? PaymentMode.other : _mode!,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final methods = _PayData.methods[widget.platform] ?? [];
    final levels = _PayData.levels[widget.platform] ?? [];
    final modes = _PayData.getModes(widget.platform);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom + 28;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 標題
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditing ? '編輯支付設定' : '新增支付設定',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.platform,
                      style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF1565C0),
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // ── 支付方式 ────────────────────────────────────────────────
            _Label(text: '支付方式'),
            const SizedBox(height: 6),
            _Dropdown(
              hint: '選擇支付方式',
              value: _method,
              items: methods,
              otherItem: '其他支付方式',
              onChanged: (v) => setState(() {
                _method = v;
                _level = null;
                _mode = null;
              }),
            ),
            const SizedBox(height: 16),

            // ── 等級 ────────────────────────────────────────────────────
            _Label(
              text: '等級',
              disabled: _isOther || !_PayData.hasLevel(widget.platform),
            ),
            const SizedBox(height: 6),
            if (_isOther || !_PayData.hasLevel(widget.platform))
              _DisabledHint(
                  text: _isOther ? '選擇其他支付方式時不需填寫' : '此平台無等級設定')
            else
              _Dropdown(
                hint: '選擇等級',
                value: _level,
                items: levels,
                enabled: _method != null && !_isOther,
                onChanged: (v) => setState(() => _level = v),
              ),
            const SizedBox(height: 16),

            // ── 支付模式 ────────────────────────────────────────────────
            _Label(
                text: '支付模式',
                disabled: _isOther || _method == null),
            const SizedBox(height: 8),
            if (_isOther)
              _DisabledHint(text: '選擇其他支付方式時不需填寫')
            else
              _ModeSelector(
                modes: modes,
                selected: _mode,
                enabled: _method != null && !_isOther,
                onSelected: (m) => setState(() => _mode = m),
              ),

            const SizedBox(height: 28),

            // ── 確認 ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _canConfirm ? _onConfirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _isEditing ? '儲存變更' : '新增',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 共用小元件
// ═══════════════════════════════════════════════════════════════════════════════

class _ModeSelector extends StatelessWidget {
  final List<PaymentMode> modes;
  final PaymentMode? selected;
  final bool enabled;
  final ValueChanged<PaymentMode> onSelected;

  const _ModeSelector({
    required this.modes,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || modes.isEmpty) {
      return _DisabledHint(text: '請先選擇支付方式');
    }
    return Row(
      children: modes.map((m) {
        final isSelected = selected == m;
        final isNfc = m == PaymentMode.nfc;
        final label = isNfc ? '感應式支付' : '掃碼式支付';
        final icon =
            isNfc ? Icons.nfc_rounded : Icons.qr_code_2_rounded;
        final desc = isNfc ? 'NFC 靠近感應' : 'QR Code 掃碼';
        final accent = isNfc ? Colors.blue.shade700 : Colors.green.shade700;

        return Expanded(
          child: GestureDetector(
            onTap: () => onSelected(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                  right: isNfc && modes.length > 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(
                  vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withOpacity(0.08)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? accent : Colors.grey.shade200,
                  width: isSelected ? 1.5 : 0.8,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      size: 32,
                      color: isSelected
                          ? accent
                          : Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? accent
                              : Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? accent.withOpacity(0.7)
                              : Colors.grey.shade400)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool disabled;
  const _Label({required this.text, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: disabled ? Colors.grey.shade400 : Colors.grey.shade700,
          letterSpacing: 0.3,
        ));
  }
}

class _DisabledHint extends StatelessWidget {
  final String text;
  const _DisabledHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 0.8),
      ),
      child: Row(children: [
        Icon(Icons.remove_circle_outline,
            size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade400)),
      ]),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? otherItem;

  const _Dropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.otherItem,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: enabled ? cs.surface : Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.grey.shade200, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: const Color(0xFF1565C0), width: 1.5),
        ),
      ),
      hint: Text(hint,
          style:
              TextStyle(fontSize: 14, color: Colors.grey.shade400)),
      items: enabled
          ? items.map((e) {
              final isOther = e == otherItem;
              return DropdownMenuItem<String>(
                value: e,
                child: Row(children: [
                  if (isOther) ...[
                    Icon(Icons.more_horiz,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(e,
                        style: TextStyle(
                          fontSize: 14,
                          color: isOther
                              ? Colors.grey.shade500
                              : null,
                          fontStyle: isOther
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              );
            }).toList()
          : null,
      onChanged: enabled ? onChanged : null,
    );
  }
}
