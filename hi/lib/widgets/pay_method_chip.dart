import 'package:flutter/material.dart';
import '../models/pay_platform.dart';

/// 行動支付小圓圈 Chip
/// 用於 HomeScreen 的「其他可用支付」橫向列，以及 MemberScreen 的支付方法列表。
class PayMethodChip extends StatelessWidget {
  final PayPlatform platform;

  /// 顯示在右上角的角標，例如 "5%" 或 "10%"
  final String? badge;

  /// 是否在圓圈下方顯示平台名稱
  final bool showLabel;

  final VoidCallback? onTap;

  const PayMethodChip({
    super.key,
    required this.platform,
    this.badge,
    this.showLabel = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // ── 圓圈本體 ──────────────────────────────────────
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: platform.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: platform.color.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: platform.imagePath != null
                      ? Image.asset(
                          platform.imagePath!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              platform.label.length <= 2
                                  ? platform.label
                                  : platform.label.substring(0, 2),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            platform.label.length <= 2
                                ? platform.label
                                : platform.label.substring(0, 2),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),

              // ── 角標（badge） ─────────────────────────────────
              if (badge != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ── 標籤文字 ──────────────────────────────────────────
          if (showLabel) ...[
            const SizedBox(height: 5),
            SizedBox(
              width: 60,
              child: Text(
                platform.label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
