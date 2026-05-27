import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
// 全局共享狀態（ValueNotifier 跨 Tab 同步）
// ════════════════════════════════════════════════════════════════════════════

/// 使用者選取的行動支付 id 清單
final payMethodsNotifier = ValueNotifier<List<String>>([]);

/// 各超商會員是否已設定
final memberSetupNotifier = ValueNotifier<Map<String, bool>>({
  'fm': false,
  'seven': false,
  'hilife': false,
  'ok': false,
});

/// 載具是否已設定
final carrierSetupNotifier = ValueNotifier<bool>(false);

const _kPayMethodsPrefKey = 'pay_methods_list';

Future<void> loadPayMethods() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList(_kPayMethodsPrefKey) ?? [];
  payMethodsNotifier.value = saved;
}

Future<void> savePayMethods(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kPayMethodsPrefKey, ids);
}
