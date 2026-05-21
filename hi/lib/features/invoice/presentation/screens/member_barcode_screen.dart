import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 會員條碼畫面
///
/// 支援條碼格式：
///   - Code 128  → 英數混合，最通用（7-11、全家等）✅ 支援斜線
///   - EAN-13    → 純 13 位數字（國際零售規範）
///   - QR Code   → 任意字串（LINE、百貨會員等）
///   ⚠️  Code 39 已移除：其字元集不含斜線 /，無法用於手機載具，
///       且會員條碼幾乎不使用 Code 39，避免使用者誤選造成生成失敗。
///
/// 持久化：
///   - 按品牌分開儲存，key = member_barcode_{brand} / member_type_{brand}
///   - 傳入 brandName 為空時使用通用 key（從首頁直接進入的情況）
///   - APP 重啟後自動載入
///
/// OCR 辨識範圍：A-Z、a-z、0-9（最長連續英數段）
class MemberBarcodeScreen extends StatefulWidget {
  /// 品牌名稱，用於分開儲存不同店家的會員條碼。
  final String? brandName;

  const MemberBarcodeScreen({super.key, this.brandName});

  @override
  State<MemberBarcodeScreen> createState() => _MemberBarcodeScreenState();
}

// ── 條碼格式選項 ──────────────────────────────────────────────────────────────

enum _BarcodeType {
  code128('Code 128', '英數混合，最通用（7-11、全家等）'),
  ean13('EAN-13', '純 13 位數字'),
  qrCode('QR Code', '任意字串（LINE、百貨會員等）');

  const _BarcodeType(this.label, this.description);
  final String label;
  final String description;

  static _BarcodeType fromString(String s) => _BarcodeType.values
      .firstWhere((e) => e.name == s, orElse: () => _BarcodeType.code128);
}

// ── State ─────────────────────────────────────────────────────────────────────

class _MemberBarcodeScreenState extends State<MemberBarcodeScreen> {
  final TextEditingController _controller = TextEditingController();

  String? _savedValue;
  bool _isScanning = false;
  bool _isLoading = true;
  _BarcodeType _selectedType = _BarcodeType.code128;

  // ── prefs key ──
  String get _keyCode => 'member_barcode_${widget.brandName ?? "_generic"}';
  String get _keyType => 'member_type_${widget.brandName ?? "_generic"}';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── 持久化：讀取 ──────────────────────────────────────────
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyCode);
    final typeStr = prefs.getString(_keyType);
    if (!mounted) return;
    setState(() {
      if (code != null) {
        _savedValue = code;
        _controller.text = code;
        if (typeStr != null) _selectedType = _BarcodeType.fromString(typeStr);
      }
      _isLoading = false;
    });
  }

  // ── 持久化：儲存 ──────────────────────────────────────────
  Future<void> _save(String value, _BarcodeType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCode, value);
    await prefs.setString(_keyType, type.name);
  }

  // ── 持久化：清除 ──────────────────────────────────────────
  Future<void> _deleteSaved() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除會員條碼'),
        content: Text(
          widget.brandName != null
              ? '確定要刪除「${widget.brandName}」的會員條碼嗎？'
              : '確定要刪除已儲存的會員條碼嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCode);
    await prefs.remove(_keyType);
    if (!mounted) return;
    _controller.clear();
    setState(() {
      _savedValue = null;
    });
  }

  // ── OCR ───────────────────────────────────────────────────────────────────

  Future<void> _pickAndScan(ImageSource source) async {
    setState(() => _isScanning = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;

      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      try {
        final result = await recognizer.processImage(inputImage);
        final extracted = _extractBestMatch(result.text);
        if (extracted.isNotEmpty) {
          setState(() {
            _controller.text = extracted;
            _savedValue = null;
            _selectedType = _guessType(extracted);
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('未偵測到有效字串，請重試或手動輸入'),
              ),
            );
          }
        }
      } finally {
        recognizer.close();
      }
    } catch (e) {
      debugPrint('❌ 掃描失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('掃描失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// 從 OCR 結果中抓最長的連續英數段（A-Z a-z 0-9），至少 4 碼
  String _extractBestMatch(String text) {
    final matches = RegExp(r'[A-Za-z0-9]{4,}')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
    if (matches.isEmpty) return '';
    matches.sort((a, b) => b.length.compareTo(a.length));
    return matches.first;
  }

  /// 根據輸入內容自動推測條碼格式
  _BarcodeType _guessType(String value) {
    final digitsOnly = RegExp(r'^\d+$').hasMatch(value);
    if (digitsOnly && value.length == 13) return _BarcodeType.ean13;
    return _BarcodeType.code128;
  }

  // ── 格式驗證 ──────────────────────────────────────────────
  String? _validateForType(String value) {
    if (value.isEmpty) return '請輸入或掃描會員號碼';
    switch (_selectedType) {
      case _BarcodeType.ean13:
        if (!RegExp(r'^\d{13}$').hasMatch(value)) return 'EAN-13 需為純 13 位數字';
      case _BarcodeType.code128:
      case _BarcodeType.qrCode:
        break;
    }
    return null;
  }

  // ── 來源選單 ──────────────────────────────────────────────────────────────
  Future<void> _showSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _SourceTile(
              icon: Icons.camera_alt,
              title: '拍照辨識',
              subtitle: '開啟相機拍攝條碼',
              onTap: () {
                Navigator.pop(ctx);
                _pickAndScan(ImageSource.camera);
              },
            ),
            const SizedBox(height: 4),
            _SourceTile(
              icon: Icons.photo_library,
              title: '從相簿選取',
              subtitle: '選取已有的條碼圖片',
              onTap: () {
                Navigator.pop(ctx);
                _pickAndScan(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── 確認 / 儲存 ───────────────────────────────────────────────────────────
  Future<void> _confirm() async {
    final value = _controller.text.trim();
    final error = _validateForType(value);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    await _save(value, _selectedType);
    if (!mounted) return;
    setState(() => _savedValue = value);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 會員條碼已儲存'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── 條碼 Widget ───────────────────────────────────────────────────────────
  Barcode get _barcode {
    switch (_selectedType) {
      case _BarcodeType.code128:
        return Barcode.code128();
      case _BarcodeType.ean13:
        return Barcode.ean13();
      case _BarcodeType.qrCode:
        return Barcode.qrCode();
    }
  }

  Widget _buildBarcodeSection() {
    if (_savedValue == null) return const SizedBox.shrink();
    final isQR = _selectedType == _BarcodeType.qrCode;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        // ✅ 修正：減少水平 padding，讓條碼有更多空間
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            // 品牌名稱標題
            if (widget.brandName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.brandName!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            Text(
              '請讓店員掃描以下條碼（${_selectedType.label}）',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // ✅ 修正重點：
            //   QR Code 不需要 LayoutBuilder（正方形固定尺寸即可）
            //   1D 條碼（Code128 / EAN-13）改用 LayoutBuilder 取得實際寬度
            //   並加上 padding 確保 quiet zone（靜區）存在
            if (isQR)
              BarcodeWidget(
                barcode: _barcode,
                data: _savedValue!,
                width: 180,
                height: 180,
                drawText: false,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return BarcodeWidget(
                    barcode: _barcode,
                    data: _savedValue!,
                    width: constraints.maxWidth,
                    height: 120,
                    drawText: false,
                    // quiet zone：1D 條碼左右兩端必須留白
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                  );
                },
              ),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _savedValue!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '複製',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _savedValue!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已複製'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: '刪除',
                  onPressed: _deleteSaved,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '已永久儲存，重啟 APP 後仍可使用',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ── 格式選擇列 ────────────────────────────────────────────────────────────
  Widget _buildTypeSelector() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _BarcodeType.values.map((type) {
          final selected = _selectedType == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(type.label),
              selected: selected,
              onSelected: (_) => setState(() {
                _selectedType = type;
                _savedValue = null; // 切換格式需重新確認
              }),
              tooltip: type.description,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 主畫面 ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.brandName != null ? '${widget.brandName} 會員條碼' : '會員條碼',
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 格式選擇 ──────────────────────────────────
              const Text(
                '條碼格式',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              _buildTypeSelector(),
              const SizedBox(height: 4),
              Text(
                _selectedType.description,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),

              // ── 輸入欄 + 掃描按鈕 ─────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: _selectedType == _BarcodeType.ean13
                          ? TextInputType.number
                          : TextInputType.visiblePassword,
                      inputFormatters: [
                        if (_selectedType == _BarcodeType.ean13)
                          FilteringTextInputFormatter.digitsOnly
                        else
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-. /+$%]'),
                          ),
                        if (_selectedType == _BarcodeType.ean13)
                          LengthLimitingTextInputFormatter(13),
                      ],
                      decoration: InputDecoration(
                        labelText: '會員號碼',
                        hintText: _selectedType == _BarcodeType.ean13
                            ? '13 位數字'
                            : '掃描或手動輸入',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirm(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _isScanning
                      ? const SizedBox(
                          width: 52,
                          height: 52,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : Material(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _showSourcePicker,
                            child: const SizedBox(
                              width: 52,
                              height: 52,
                              child: Icon(
                                Icons.qr_code_scanner,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                ],
              ),

              const SizedBox(height: 8),
              Text(
                '點右側按鈕可拍照自動辨識條碼，支援 A-Z / a-z / 0-9',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),

              // ── 儲存按鈕 ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isScanning ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('確認並儲存條碼'),
                ),
              ),
              const SizedBox(height: 28),

              // ── 條碼顯示區 ────────────────────────────────
              _buildBarcodeSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 來源選單 ListTile ─────────────────────────────────────────────────────────

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.blue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
