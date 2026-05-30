import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 資料模型
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentMode { nfc, qr, other }

class PaymentConfig {
  final String platform;
  final String method;  // '其他支付方式' 時為空
  final String level;   // 無等級填 '無'
  final PaymentMode mode;

  const PaymentConfig({
    required this.platform,
    required this.method,
    required this.level,
    required this.mode,
  });

  bool get isOther => mode == PaymentMode.other;
}

// ─────────────────────────────────────────────────────────────────────────────
// 靜態資料
// ─────────────────────────────────────────────────────────────────────────────

class _PayData {
  static const List<String> platforms = [
    '悠遊付', '街口支付', '全支付', '台灣Pay', 'Line Pay',
  ];

  static const Map<String, List<String>> methods = {
    '悠遊付':   ['錢包or銀行帳戶', '其他支付方式'],
    '街口支付': ['街口帳戶', '街利存帳戶', '街利存帳戶_新戶', '其他支付方式'],
    '全支付':   [
      '全支付帳戶', '國泰世華', '將來銀行', '華泰銀行',
      '國泰世華信用卡', '富邦銀行信用卡', '華泰銀行信用卡',
      '上海商銀信用卡', '玉山銀行信用卡', '聯邦銀行信用卡',
      '華南銀行信用卡', '台新銀行信用卡', '其他支付方式',
    ],
    '台灣Pay':  [
      '台灣銀行', '土地銀行', '合作金庫銀行', '第一銀行',
      '華南銀行', '兆豐銀行', '台灣企銀', '彰化銀行',
      '台灣銀行信用卡', '土地銀行信用卡', '合作金庫銀行信用卡',
      '第一銀行信用卡', '彰化銀行信用卡', '兆豐銀行信用卡',
      '台灣企銀信用卡', '其他支付方式',
    ],
    'Line Pay': [
      '中國信託Line Pay聯名卡 Visa', '中國信託Line Pay聯名卡 JCB',
      '富邦J卡', '聯邦賴點卡', '聯邦賴點卡_新戶',
      '永豐DAWAY卡', '永豐DAWAY卡_新戶', '其他支付方式',
    ],
  };

  static const Map<String, List<String>> levels = {
    '悠遊付':   ['銀級', '金級', '白金級'],
    '街口支付': ['銅牌', '銀牌', '金牌', '白金', '尊爵'],
    '全支付':   [],
    '台灣Pay':  [],
    'Line Pay': [],
  };

  // 各平台支援的支付模式
  static const Map<String, List<PaymentMode>> supportedModes = {
    '悠遊付':   [PaymentMode.nfc, PaymentMode.qr],
    '街口支付': [PaymentMode.qr],
    '全支付':   [PaymentMode.qr],
    '台灣Pay':  [PaymentMode.qr],
    'Line Pay': [PaymentMode.qr],
  };

  // Line Pay 使用獨立 QR，其他用 TWQR
  static bool isTwqr(String platform) => platform != 'Line Pay';

  static bool hasLevel(String platform) =>
      (levels[platform] ?? []).isNotEmpty;

  static List<PaymentMode> getModes(String platform) =>
      supportedModes[platform] ?? [PaymentMode.qr];
}

// ─────────────────────────────────────────────────────────────────────────────
// 入口
// ─────────────────────────────────────────────────────────────────────────────

class PaymentSheet {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _PaymentBottomSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部選單
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentBottomSheet extends StatefulWidget {
  const _PaymentBottomSheet();

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  String? _platform;
  String? _method;
  String? _level;
  PaymentMode? _mode;

  bool get _isOther => _method == '其他支付方式';

  // 確認鈕可按條件：
  // 「其他」→ 只要選了平台+方式就能確認
  // 一般  → 平台+方式+模式都選，有等級的要選等級
  bool get _canConfirm {
    if (_platform == null || _method == null) return false;
    if (_isOther) return true;
    if (_mode == null) return false;
    if (_PayData.hasLevel(_platform!) && _level == null) return false;
    return true;
  }

  void _onPlatformChanged(String? v) => setState(() {
        _platform = v;
        _method = null;
        _level = null;
        _mode = null;
      });

  void _onMethodChanged(String? v) => setState(() {
        _method = v;
        _level = null;
        _mode = null;
      });

  void _onLevelChanged(String? v) => setState(() => _level = v);

  void _onModeSelected(PaymentMode m) => setState(() => _mode = m);

  void _onConfirm() {
    if (!_canConfirm) return;
    final config = PaymentConfig(
      platform: _platform!,
      method:   _isOther ? '其他支付方式' : _method!,
      level:    _isOther
          ? '無'
          : (_PayData.hasLevel(_platform!) ? _level! : '無'),
      mode:     _isOther ? PaymentMode.other : _mode!,
    );
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaymentResultScreen(config: config),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final methods = _platform != null
        ? (_PayData.methods[_platform!] ?? <String>[])
        : <String>[];
    final levels = _platform != null
        ? (_PayData.levels[_platform!] ?? <String>[])
        : <String>[];
    final modes = _platform != null
        ? _PayData.getModes(_platform!)
        : <PaymentMode>[];
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom + 28;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text('行動支付設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('依序選擇支付平台與方式',
                style: TextStyle(fontSize: 13,
                    color: cs.onSurface.withOpacity(0.5))),
            const SizedBox(height: 20),

            // ── 1. 行動支付（平台） ────────────────────────────────────
            _Label(text: '行動支付'),
            const SizedBox(height: 6),
            _Dropdown(
              hint: '選擇支付平台',
              value: _platform,
              items: _PayData.platforms,
              onChanged: _onPlatformChanged,
            ),
            const SizedBox(height: 16),

            // ── 2. 支付方式 ────────────────────────────────────────────
            _Label(text: '支付方式', disabled: _platform == null),
            const SizedBox(height: 6),
            _Dropdown(
              hint: _platform == null ? '請先選擇支付平台' : '選擇支付方式',
              value: _method,
              items: methods,
              enabled: _platform != null,
              onChanged: _onMethodChanged,
              otherItem: '其他支付方式',
            ),
            const SizedBox(height: 16),

            // ── 3. 等級 ────────────────────────────────────────────────
            _Label(
              text: '等級',
              disabled: _isOther || _platform == null ||
                  !_PayData.hasLevel(_platform ?? ''),
            ),
            const SizedBox(height: 6),
            if (_isOther ||
                (_platform != null && !_PayData.hasLevel(_platform!)))
              _DisabledHint(
                  text: _isOther ? '選擇其他支付方式時不需填寫' : '此平台無等級，顯示為「無」')
            else
              _Dropdown(
                hint: _platform == null ? '請先選擇支付平台' : '選擇等級',
                value: _level,
                items: levels,
                enabled: _platform != null && _method != null && !_isOther,
                onChanged: _onLevelChanged,
              ),
            const SizedBox(height: 16),

            // ── 4. 支付模式（感應 / 掃碼） ────────────────────────────
            _Label(
              text: '支付模式',
              disabled: _isOther || _method == null,
            ),
            const SizedBox(height: 8),
            if (_isOther)
              _DisabledHint(text: '選擇其他支付方式時不需填寫')
            else
              _ModeSelector(
                modes: modes,
                selected: _mode,
                enabled: _method != null && !_isOther,
                onSelected: _onModeSelected,
              ),

            const SizedBox(height: 28),

            // ── 確認按鈕 ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _canConfirm ? _onConfirm : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('確認',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 支付模式選擇器（感應 / 掃碼 兩個大按鈕）
// ─────────────────────────────────────────────────────────────────────────────

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
    final cs = Theme.of(context).colorScheme;

    if (!enabled || modes.isEmpty) {
      return _DisabledHint(text: '請先選擇支付方式');
    }

    return Row(
      children: modes.map((m) {
        final isSelected = selected == m;
        final isNfc = m == PaymentMode.nfc;
        final label = isNfc ? '感應式支付' : '掃碼式支付';
        final icon = isNfc ? Icons.nfc_rounded : Icons.qr_code_2_rounded;
        final desc = isNfc ? 'NFC 靠近感應' : 'QR Code 掃碼';

        return Expanded(
          child: GestureDetector(
            onTap: () => onSelected(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                  right: m == PaymentMode.nfc && modes.length > 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primaryContainer
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? cs.primary : Colors.grey.shade200,
                  width: isSelected ? 1.5 : 0.8,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: isSelected
                        ? cs.primary
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? cs.primary : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? cs.primary.withOpacity(0.7)
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 結果畫面（NFC 提示 / QR TWQR / QR Line Pay 獨立 / 其他）
// ─────────────────────────────────────────────────────────────────────────────

class PaymentResultScreen extends StatelessWidget {
  final PaymentConfig config;
  const PaymentResultScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(config.platform,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: switch (config.mode) {
          PaymentMode.nfc   => _NfcView(config: config),
          PaymentMode.qr    => _QrView(config: config),
          PaymentMode.other => _OtherView(platform: config.platform),
        },
      ),
    );
  }
}

// ── NFC 感應畫面 ──────────────────────────────────────────────────────────────

class _NfcView extends StatelessWidget {
  final PaymentConfig config;
  const _NfcView({required this.config});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 平台資訊
          _PlatformBadge(config: config),
          const SizedBox(height: 40),

          // NFC 動畫區
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              children: [
                // 三層漸淡圓圈模擬 NFC 波紋
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withOpacity(0.08),
                      ),
                    ),
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withOpacity(0.14),
                      ),
                    ),
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.shade100,
                      ),
                      child: Icon(Icons.nfc_rounded,
                          size: 32, color: Colors.blue.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '請靠近感應',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '將手機靠近店家的 NFC 感應區',
                  style: TextStyle(
                      fontSize: 14, color: Colors.blue.shade500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 提示說明
          _InfoTile(
            icon: Icons.smartphone_outlined,
            color: Colors.blue,
            text: '請確認手機已開啟 NFC 功能，並解鎖螢幕',
          ),
          const SizedBox(height: 10),
          _InfoTile(
            icon: Icons.info_outline,
            color: Colors.orange,
            text: '感應時手機背面靠近讀卡機，保持靜止約 1 秒',
          ),
        ],
      ),
    );
  }
}

// ── QR code 掃碼畫面 ──────────────────────────────────────────────────────────

class _QrView extends StatelessWidget {
  final PaymentConfig config;
  const _QrView({required this.config});

  @override
  Widget build(BuildContext context) {
    final isTwqr = _PayData.isTwqr(config.platform);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 平台資訊
          _PlatformBadge(config: config),
          const SizedBox(height: 32),

          // QR 說明卡
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  isTwqr ? Icons.qr_code_scanner_rounded : Icons.qr_code_2_rounded,
                  size: 64,
                  color: isTwqr ? Colors.green.shade600 : Colors.indigo.shade400,
                ),
                const SizedBox(height: 20),
                Text(
                  isTwqr ? '掃描 TWQR 立牌' : '掃描 Line Pay 立牌',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  isTwqr
                      ? '請開啟 ${config.platform} App\n掃描店家的 TWQR 共通立牌付款'
                      : '請開啟 LINE App\n掃描 Line Pay 專屬熊大立牌',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.6),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // TWQR / Line Pay 說明
          if (isTwqr)
            _InfoTile(
              icon: Icons.check_circle_outline,
              color: Colors.green,
              text: '${config.platform} 支援 TWQR，可掃描所有貼有 TWQR 標誌的立牌',
            )
          else
            _InfoTile(
              icon: Icons.warning_amber_rounded,
              color: Colors.amber,
              text: 'Line Pay 為獨立系統，僅能掃描 Line Pay 專屬立牌，無法使用 TWQR',
            ),

          const SizedBox(height: 10),
          _InfoTile(
            icon: Icons.smartphone_outlined,
            color: Colors.blue,
            text: '請確認已安裝並登入 ${config.platform} App',
          ),
        ],
      ),
    );
  }
}

// ── 其他支付方式畫面 ──────────────────────────────────────────────────────────

class _OtherView extends StatelessWidget {
  final String platform;
  const _OtherView({required this.platform});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payment_outlined,
                  size: 40, color: Colors.blue.shade400),
            ),
            const SizedBox(height: 20),
            Text(platform,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '已選擇其他支付方式\n請直接開啟 $platform App 進行付款',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 共用小元件
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformBadge extends StatelessWidget {
  final PaymentConfig config;
  const _PlatformBadge({required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payment, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                config.platform,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800),
              ),
            ],
          ),
          if (!config.isOther && config.method.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${config.method}${config.level != '無' ? '  ·  ${config.level}' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoTile(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, color: color.withOpacity(0.9)))),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool disabled;
  const _Label({required this.text, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: disabled ? Colors.grey.shade400 : Colors.grey.shade700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _DisabledHint extends StatelessWidget {
  final String text;
  const _DisabledHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.remove_circle_outline,
              size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      ),
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
          borderSide: BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
      hint: Text(hint,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
      items: enabled
          ? items.map((e) {
              final isOther = e == otherItem;
              return DropdownMenuItem<String>(
                value: e,
                child: Row(
                  children: [
                    if (isOther) ...[
                      Icon(Icons.more_horiz,
                          size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                    ],
                    Text(e,
                        style: TextStyle(
                          fontSize: 14,
                          color: isOther ? Colors.grey.shade500 : null,
                          fontStyle: isOther
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              );
            }).toList()
          : null,
      onChanged: enabled ? onChanged : null,
    );
  }
}
