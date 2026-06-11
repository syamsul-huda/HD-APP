import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._();

  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
  static final viewMode = ValueNotifier<String>('list'); // 'list' | 'grid'

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('dark_mode') ?? false;
    themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    viewMode.value = prefs.getString('view_mode') ?? 'list';
  }

  static Future<void> setDarkMode(bool dark) async {
    themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', dark);
  }

  static Future<void> setViewMode(String mode) async {
    viewMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('view_mode', mode);
  }

  static bool get isDark => themeMode.value == ThemeMode.dark;
}
