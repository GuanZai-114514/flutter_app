import 'package:flutter/material.dart';
// 這裡確保路徑是小寫，對應你的實體檔案
import 'package:hi/features/invoice/presentation/screens/carrier_input_screen.dart';
import 'package:hi/features/invoice/presentation/screens/member_barcode_screen.dart';

/// 從店家詳情頁呼叫：
///   InvoiceInputSheet.show(context);
class InvoiceInputSheet {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _InvoiceInputSheet(),
    );
  }
}

class _InvoiceInputSheet extends StatelessWidget {
  const _InvoiceInputSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上方橫條 Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '選擇輸入方式',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '選擇要輸入的發票 / 會員資訊',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.barcode_reader,
                  label: '載具條碼',
                  description: '手動輸入號碼',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CarrierInputScreen(),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.person_outline,
                  label: '會員條碼',
                  description: '輸入或拍照辨識',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MemberBarcodeScreen(),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant, width: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: cs.onSurface.withOpacity(0.6)),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.45),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}