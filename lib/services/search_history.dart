import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史：本地持久化最近 10 条关键词。
class SearchHistory {
  SearchHistory._();

  static const _key = 'search_history';
  static const maxItems = 10;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? <String>[];
  }

  static Future<List<String>> add(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return load();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.remove(text);
    list.insert(0, text);
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }
    await prefs.setStringList(_key, list);
    return list;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
