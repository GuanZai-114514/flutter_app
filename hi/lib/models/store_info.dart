import 'package:flutter/material.dart';

class StoreCondition {
  final String text;
  final bool isRed;
  const StoreCondition(this.text, {this.isRed = false});
}

class StoreInfo {
  final String id;
  final String name;
  final String shortName;
  final Color primaryColor;
  final String cashback;
  final List<StoreCondition> conditions;
  final bool hasBadge;

  const StoreInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.primaryColor,
    required this.cashback,
    required this.conditions,
    this.hasBadge = false,
  });
}

const kStores = <String, StoreInfo>{
  'fm': StoreInfo(
    id: 'fm', name: '全家便利商店', shortName: '全家',
    primaryColor: Color(0xFF003087), cashback: '5%', hasBadge: true,
    conditions: [
      StoreCondition('消費滿 100 元享 5% 回饋', isRed: true),
      StoreCondition('滿 200 減 20'),
      StoreCondition('需使用 FamiPay 付款', isRed: true),
    ],
  ),
  'seven': StoreInfo(
    id: 'seven', name: '7-ELEVEN', shortName: '7-11',
    primaryColor: Color(0xFFEF6C00), cashback: '3%',
    conditions: [
      StoreCondition('Open 錢包付款享 3%', isRed: true),
      StoreCondition('滿 150 減 15'),
      StoreCondition('每月上限 100 點', isRed: true),
    ],
  ),
  'hilife': StoreInfo(
    id: 'hilife', name: '萊爾富', shortName: 'Hi-Life',
    primaryColor: Color(0xFFE53935), cashback: '2%',
    conditions: [
      StoreCondition('Hi-Life Pay 付款', isRed: true),
      StoreCondition('滿 50 減 5'),
      StoreCondition('週末加碼 +1%', isRed: true),
    ],
  ),
  'ok': StoreInfo(
    id: 'ok', name: 'OK超商', shortName: 'OK',
    primaryColor: Color(0xFFE53935), cashback: '4%', hasBadge: true,
    conditions: [
      StoreCondition('OK Pay 付款享 4%', isRed: true),
      StoreCondition('滿 150 減 10'),
      StoreCondition('每筆最高回饋 20 點', isRed: true),
    ],
  ),
};
