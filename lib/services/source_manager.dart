import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_source.dart';

class SourceManager extends ChangeNotifier {
  SourceManager._();

  static final SourceManager instance = SourceManager._();

  static const _key = 'music_sources';
  static const _legacySeededKey = 'builtin_sources_seeded_v3';
  static const _seededNamesKey = 'builtin_source_names';

  /// 内置音乐源（随 App 打包，首次启动自动导入）。
  /// 新增内置源会自动加入老用户列表；用户主动删除过的源不会被自动加回。
  static const builtInAssets = [
    'assets/sources/猫耳FM.json',
    'assets/sources/udio.json',
    'assets/sources/bilibili.json',
  ];

  /// 2.3.0 及更早版本内置过的源，用于升级时区分「老内置源」与「新增源」。
  static const _legacyBuiltInNames = [
    '酷我 完整歌曲',
    '酷狗 完整歌曲',
    'Audius 音乐',
    '网易云音乐',
    'ccMixter 开放音乐',
  ];

  final List<MusicSource> _sources = [];
  final Map<String, int> _failStreak = {};

  /// 连续失败达到该次数后自动停用该音乐源。
  static const autoDisableThreshold = 5;

  List<MusicSource> get sources => List.unmodifiable(_sources);

  int failStreakOf(String name) => _failStreak[name] ?? 0;

  void recordSourceSuccess(String name) {
    if (_failStreak.remove(name) != null) {
      notifyListeners();
    }
  }

  void recordSourceFailure(String name) {
    final streak = (_failStreak[name] ?? 0) + 1;
    _failStreak[name] = streak;
    if (streak >= autoDisableThreshold) {
      final source = byName(name);
      if (source != null && source.enabled) {
        source.enabled = false;
        _save();
        return;
      }
    }
    notifyListeners();
  }

  /// 清除某音源的失败计数（重新启用或手动测试后调用）。
  void resetFailures(String name) {
    if (_failStreak.remove(name) != null) {
      notifyListeners();
    }
  }

  List<MusicSource> get enabledSources =>
      _sources.where((s) => s.enabled).toList();

  /// 已废弃的音源名称（不再提供，升级时自动移除）。
  static const _removedSourceNames = [
    '网易云音乐（自建）',
    '网易云 直链',
    'iTunes 试听',
    'Deezer 试听',
    '酷我 完整歌曲',
    '酷狗 完整歌曲',
    'Audius 音乐',
    '网易云音乐',
    'ccMixter 开放音乐',
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _sources
        ..clear()
        ..addAll(list.map(MusicSource.fromJson));
    } catch (_) {
      _sources.clear();
    }
    var changed = false;
    _sources.removeWhere((s) {
      if (_removedSourceNames.contains(s.name)) {
        changed = true;
        return true;
      }
      return false;
    });
    if (changed) {
      await _save();
    }
    notifyListeners();
  }

  /// 首次启动导入全部内置源；老用户升级时只补充新增的内置源。
  /// 用户主动删除过的源记录在 [_seededNamesKey] 中，不会被自动加回。
  Future<void> seedBuiltInSources() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_seededNamesKey);
    final seeded =
        stored ??
        (prefs.getBool(_legacySeededKey) == true
            ? List<String>.from(_legacyBuiltInNames)
            : <String>[]);
    var added = 0;
    var updated = 0;
    for (final asset in builtInAssets) {
      final source = await _loadAsset(asset);
      if (source == null) continue;
      final existing = byName(source.name);
      if (existing != null) {
        // 内置源配置升级：保留用户的启用/停用状态。
        if (_isNewerVersion(source.version, existing.version)) {
          source.enabled = existing.enabled;
          final index = _sources.indexOf(existing);
          if (index >= 0) {
            _sources[index] = source;
            updated++;
          }
        }
        if (!seeded.contains(source.name)) seeded.add(source.name);
        continue;
      }
      if (seeded.contains(source.name)) continue;
      _sources.add(source);
      seeded.add(source.name);
      added++;
    }
    await prefs.setStringList(_seededNamesKey, seeded);
    await prefs.setBool(_legacySeededKey, true);
    if (added > 0 || updated > 0) {
      await _save();
    }
  }

  static bool _isNewerVersion(String candidate, String current) {
    final a = candidate.split('.').map(int.tryParse).toList();
    final b = current.split('.').map(int.tryParse).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? (a[i] ?? 0) : 0;
      final y = i < b.length ? (b[i] ?? 0) : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// 读取随 App 打包的全部内置源（设置页「内置音乐源」目录使用）。
  Future<List<MusicSource>> loadBundledSources() async {
    final result = <MusicSource>[];
    for (final asset in builtInAssets) {
      final source = await _loadAsset(asset);
      if (source != null) result.add(source);
    }
    return result;
  }

  Future<MusicSource?> _loadAsset(String asset) async {
    try {
      final data = await rootBundle.loadString(asset);
      return parseSourceJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_sources.map((s) => s.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 添加或覆盖一个音乐源；同时记入「已处理的内置源」。
  Future<void> addSource(MusicSource source) async {
    _sources.removeWhere((s) => s.name == source.name);
    _sources.add(source);
    _failStreak.remove(source.name);
    await _markSeeded(source.name);
    await _save();
  }

  Future<void> removeSource(String name) async {
    _sources.removeWhere((s) => s.name == name);
    _failStreak.remove(name);
    await _save();
  }

  Future<void> toggleSource(String name, bool enabled) async {
    for (final s in _sources) {
      if (s.name == name) {
        s.enabled = enabled;
        if (enabled) _failStreak.remove(name);
        break;
      }
    }
    await _save();
  }

  Future<void> _markSeeded(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final seeded = prefs.getStringList(_seededNamesKey) ?? <String>[];
    if (!seeded.contains(name)) {
      seeded.add(name);
      await prefs.setStringList(_seededNamesKey, seeded);
    }
  }

  MusicSource? byName(String? name) {
    if (name == null) return null;
    for (final s in _sources) {
      if (s.name == name) return s;
    }
    return null;
  }

  static MusicSource? parseSourceJson(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      return MusicSource.fromJson(json.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static Future<MusicSource> fetchSource(String url) async {
    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes));
    if (json is! Map) {
      throw const FormatException('音乐源文件必须是 JSON 对象');
    }
    return MusicSource.fromJson(json.cast<String, dynamic>());
  }
}
