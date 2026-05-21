import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 載具輸入畫面
/// 格式規範（財政部手機條碼共通性載具）：
///   - 固定 8 碼
///   - 第 1 碼：半形斜線 /
///   - 其餘 7 碼：大寫英文(A-Z)、數字(0-9)、特殊符號(. - +)
///   - 使用 Code128 條碼（支援斜線字元，Code39 不支援）
///   - 號碼永久儲存於 shared_preferences，APP 重啟後自動載入
class CarrierInputScreen extends StatefulWidget {
  const CarrierInputScreen({super.key});

  @override
  State<CarrierInputScreen> createState() => _CarrierInputScreenState();
}

class _CarrierInputScreenState extends State<CarrierInputScreen> {
  // ── 格式驗證正則 ──────────────────────────────────────────
  static final RegExp _carrierRegex = RegExp(r'^/[A-Z0-9.\-+]{7}$');
  static const String _prefKey = 'carrier_code';

  // ── 狀態 ──────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? _savedValue;
  String? _errorText;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── 持久化：讀取 ──────────────────────────────────────────
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (!mounted) return;
    // ✅ 讀取時再次 sanitize：trim + toUpperCase，防止舊資料汙染
    final clean = saved?.trim().toUpperCase();
    setState(() {
      _savedValue = clean;
      if (clean != null) _controller.text = clean;
      _isLoading = false;
    });
  }

  // ── 持久化：儲存 ──────────────────────────────────────────
  Future<void> _save(String value) async {
    // ✅ 儲存前再次 sanitize，確保存入的一定是 trim + 大寫，不含任何空白
    final clean = value.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, clean);
  }

  // ── 持久化：清除 ──────────────────────────────────────────
  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ── 格式驗證 ──────────────────────────────────────────────
  Future<void> _validate() async {
    // ✅ 統一在這裡做 sanitize，後續所有邏輯都用 raw 這個已清理的值
    final raw = _controller.text.trim().toUpperCase();
    // 同步更新 controller 顯示，讓使用者看到實際被儲存的值
    _controller.text = raw;

    if (raw.isEmpty) {
      setState(() {
        _errorText = '請輸入載具號碼';
        _savedValue = null;
      });
      return;
    }
    if (raw.length != 8) {
      setState(() {
        _errorText = '長度不正確，需固定 8 碼（/ + 7碼）';
        _savedValue = null;
      });
      return;
    }
    if (!raw.startsWith('/')) {
      setState(() {
        _errorText = '第一碼必須為斜線「/」';
        _savedValue = null;
      });
      return;
    }
    if (!_carrierRegex.hasMatch(raw)) {
      setState(() {
        _errorText = '字元不合法，只允許：英文字母、數字、. - +';
        _savedValue = null;
      });
      return;
    }

    _focusNode.unfocus();
    await _save(raw);
    if (!mounted) return;
    setState(() {
      _errorText = null;
      _savedValue = raw;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 載具號碼已儲存'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── 刪除已儲存的載具 ──────────────────────────────────────
  Future<void> _deleteSaved() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除載具'),
        content: const Text('確定要刪除已儲存的載具號碼嗎？'),
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
    await _clear();
    if (!mounted) return;
    _controller.clear();
    setState(() {
      _savedValue = null;
      _errorText = null;
    });
  }

  // ── 條碼區塊 ──────────────────────────────────────────────
  Widget _buildBarcodeSection() {
    if (_savedValue == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 300),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              Text(
                '請讓店員掃描以下條碼',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              // ✅ 修正重點：
              //   1. 用 LayoutBuilder 取得實際可用寬度，避免 double.infinity 渲染異常
              //   2. padding 保留左右各 16px quiet zone（條碼規範要求靜區）
              //   3. 高度提高至 120，掃描器更容易辨識
              LayoutBuilder(
                builder: (context, constraints) {
                  // ✅ 三重 sanitize：trim、toUpperCase、再次確認無空白
                  //    確保傳入 BarcodeWidget 的資料與財政部載具格式完全吻合
                  final barcodeData = _savedValue!
                      .trim()
                      .toUpperCase()
                      .replaceAll(RegExp(r'\s'), ''); // 移除任何隱藏空白字元
                  assert(
                    barcodeData.length == 8 && barcodeData.startsWith('/'),
                    '❌ 條碼資料異常: "$barcodeData"',
                  );
                  return BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: barcodeData,
                    width: constraints.maxWidth,
                    height: 120,
                    drawText: false,
                    // quiet zone（靜區）：條碼左右兩端必須留白，否則掃描器容易失敗
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                  );
                },
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _savedValue!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '複製載具號碼',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _savedValue!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已複製載具號碼'),
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
                    tooltip: '刪除載具',
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
      ),
    );
  }

  // ── 主畫面 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('電子載具'),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => _focusNode.unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 輸入欄位 ──────────────────────────────────
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[/A-Za-z0-9.\-+]'),
                  ),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: '手機載具號碼',
                  hintText: '/AB+1234',
                  helperText: '格式：/ 開頭 + 7碼（英數 . - +），共 8 碼',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.receipt_long),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _errorText = null;
                              // 只清輸入框，不刪已儲存的號碼
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {
                  _errorText = null;
                }),
                onSubmitted: (_) => _validate(),
              ),
              const SizedBox(height: 16),

              // ── 確認按鈕 ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _validate,
                  icon: const Icon(Icons.check),
                  label: const Text('確認並儲存條碼'),
                ),
              ),
              const SizedBox(height: 28),

              // ── 條碼顯示 ──────────────────────────────────
              _buildBarcodeSection(),
            ],
          ),
        ),
      ),
    );
  }
}
