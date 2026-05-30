import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 會員條碼畫面
///
/// 預設條碼格式：
///   - Code 128  → 英數混合，最通用（7-11、全家等）✅ 支援斜線
///
/// 持久化：
///   - 按品牌分開儲存，key = member_barcode_{brand} / member_type_{brand}
///   - 傳入 brandName 為空時使用通用 key
///   - APP 重啟後自動載入
class MemberBarcodeScreen extends StatefulWidget {
  /// 品牌名稱，用於分開儲存不同店家的會員條碼。
  final String? brandName;

  const MemberBarcodeScreen({super.key, this.brandName});

  @override
  State<MemberBarcodeScreen> createState() => _MemberBarcodeScreenState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _MemberBarcodeScreenState extends State<MemberBarcodeScreen> {
  final TextEditingController _controller = TextEditingController();

  String? _savedValue;
  bool _isScanning = false;
  bool _isLoading = true;
  // 預設固定為 Code 128
  final String _selectedType = 'code128';

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
    if (!mounted) return;
    setState(() {
      if (code != null) {
        final clean = code.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
        _savedValue = clean;
        _controller.text = clean;
      }
      _isLoading = false;
    });
  }

  // ── 持久化：儲存 ──────────────────────────────────────────
  Future<void> _save(String value) async {
    // 儲存前 sanitize：移除前後空白與隱藏字元，統一大寫
    final clean = value.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCode, clean);
    await prefs.setString(_keyType, _selectedType);
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

  // ── 格式驗證 ──────────────────────────────────────────────
  String? _validate(String value) {
    if (value.isEmpty) return '請輸入或掃描會員號碼';
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
    final error = _validate(value);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    await _save(value);
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

  Widget _buildBarcodeSection() {
    if (_savedValue == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
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
              '請讓店員掃描以下條碼',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final barcodeData = _savedValue!
                    .trim()
                    .toUpperCase()
                    .replaceAll(RegExp(r'\s'), '');
                return BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: barcodeData,
                  width: constraints.maxWidth,
                  height: 120,
                  drawText: false,
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
              // ── 輸入欄 + 掃描按鈕 ─────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.visiblePassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9\-. /+$%]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: '會員號碼',
                        hintText: '掃描或手動輸入',
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
