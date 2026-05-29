import 'package:flutter/material.dart';

class PayPlatform {
  final String id;
  final String label;
  final Color color;
  final String iconText;
  final String? iosScheme;
  final String? androidScheme;
  final String? universalUrl;

  const PayPlatform({
    required this.id,
    required this.label,
    required this.color,
    required this.iconText,
    this.iosScheme,
    this.androidScheme,
    this.universalUrl,
  });
}

const kPayPlatforms = <PayPlatform>[
  PayPlatform(
    id: 'linepay',
    label: 'LINE Pay',
    color: Color(0xFF00B900),
    iconText: 'LINE\nPay',
    iosScheme: 'line://pay/generateQR',
    androidScheme: 'line://pay/generateQR',
    universalUrl: 'https://line.me/en/pay',
  ),
  PayPlatform(
    id: 'jkopay',
    label: '街口支付',
    color: Color(0xFFE53935),
    iconText: '街口',
    iosScheme: 'jkos://showQRCode',
    androidScheme: 'jkos://showQRCode',
    universalUrl: 'https://www.jkopay.com',
  ),
  PayPlatform(
    id: 'allpay',
    label: '全支付',
    color: Color(0xFF1565C0),
    iconText: '全支付',
    iosScheme: 'com.pxpay.plus://zjdja',
    androidScheme: 'com.pxpay.plus://zjdja',
    universalUrl: 'https://www.family.com.tw/marketing/allpay.aspx',
  ),
  PayPlatform(
    id: 'taiwanpay',
    label: '台灣Pay',
    color: Color(0xFF2E7D32),
    iconText: '台灣\nPay',
    iosScheme: 'twmpshortcut://?type=payment',
    androidScheme: 'twmpshortcut://?type=payment',
    universalUrl: 'https://www.taiwanpay.net.tw',
  ),
  PayPlatform(
    id: 'easycard',
    label: '悠遊付',
    color: Color(0xFF00838F),
    iconText: '悠遊付',
    iosScheme: 'tw.com.easycard.easycardwallet://paymentCode',
    androidScheme: 'tw.com.easycard.easycardwallet://paymentCode',
    universalUrl: 'https://www.easycard.com.tw/easywallet',
  ),
  PayPlatform(
    id: 'icashpay',
    label: 'icash Pay',
    color: Color(0xFFEF6C00),
    iconText: 'icash',
    iosScheme: 'icashpay://',
    androidScheme: 'icashpay://',
    universalUrl: 'https://www.icashpay.com.tw',
  ),
  PayPlatform(
    id: 'pxpay',
    label: 'PX Pay',
    color: Color(0xFFD32F2F),
    iconText: 'PX\nPay',
    iosScheme: 'pxpay://',
    androidScheme: 'pxpay://',
    universalUrl: 'https://www.pxmart.com.tw/px/pay.html',
  ),
  PayPlatform(
    id: 'applepay',
    label: 'Apple Pay',
    color: Color(0xFF1C1C1E),
    iconText: ' Pay',
  ),
  PayPlatform(
    id: 'googlepay',
    label: 'Google Pay',
    color: Color(0xFF4285F4),
    iconText: 'G\nPay',
    iosScheme: 'googlepay://',
    androidScheme: 'googlepay://',
    universalUrl: 'https://pay.google.com',
  ),
  PayPlatform(
    id: 'samsungpay',
    label: 'Samsung Pay',
    color: Color(0xFF1428A0),
    iconText: 'S Pay',
    androidScheme: 'samsungpay://',
    universalUrl: 'https://www.samsung.com/tw/apps/samsung-pay/',
  ),
];

PayPlatform? platformById(String id) {
  try {
    return kPayPlatforms.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}

String? discountSoftwareToId(String software) {
  const map = {
    '悠遊付': 'easycard',
    '街口支付': 'jkopay',
    '全支付': 'allpay',
    '台灣Pay': 'taiwanpay',
    'Line Pay': 'linepay',
    'LINE Pay': 'linepay',
  };
  return map[software];
}
