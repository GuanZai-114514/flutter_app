import 'package:flutter/material.dart';

import '../models/pay_platform.dart';

class PayMethodChip extends StatelessWidget {
  final PayPlatform platform;
  final bool showLabel;
  final String? badge;
  final VoidCallback? onTap;

  const PayMethodChip({
    super.key,
    required this.platform,
    this.showLabel = false,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBadge = badge != null && badge!.isNotEmpty;
    final accent = hasBadge ? const Color(0xFFD32F2F) : const Color(0xFFE8E8E8);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: showLabel
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: accent, width: hasBadge ? 1.5 : 1.0),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x07000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: showLabel ? _buildLabeledContent(accent) : _buildIconOnlyContent(),
      ),
    );
  }

  Widget _buildIconOnlyContent() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: platform.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          platform.iconText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildLabeledContent(Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: platform.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              platform.iconText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              platform.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF222222),
              ),
            ),
            if (badge != null)
              Text(
                '回饋 $badge',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
