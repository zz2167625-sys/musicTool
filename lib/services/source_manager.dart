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
  static const _seededKey = 'builtin_sources_seeded_v3';

  /// 内置音乐源（由 tools/music_source_scraper.py 抓取，随 App 打包）。
  /// 首次启动自动导入；用户删除后不会被再次添加。
  static const _builtInAssets = [
    'assets/sources/酷我_完整歌曲.json',
    'assets/sources/酷狗_完整歌曲.json',
    'assets/sources/Audius_音乐.json',
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

  List<MusicSource> get enabledSources =>
      _sources.where((s) => s.enabled).toList();

  /// 已废弃的音源名称（不再提供，升级时自动移除）。
  static const _removedSourceNames = [
    '网易云音乐（自建）',
    '网易云 直链',
    'iTunes 试听',
    'Deezer 试听',
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

  /// 首次启动时导入随 App 打包的内置音乐源；之后不再自动注入。
  Future<void> seedBuiltInSources() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) == true) return;
    var added = false;
    for (final asset in _builtInAssets) {
      try {
        final data = await rootBundle.loadString(asset);
        final source = parseSourceJson(data);
        if (source != null && byName(source.name) == null) {
          _sources.add(source);
          added = true;
        }
      } catch (_) {}
    }
    await prefs.setBool(_seededKey, true);
    if (added) {
      await _save();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_sources.map((s) => s.toJson()).toList()));
    notifyListeners();
  }

  Future<void> addSource(MusicSource source) async {
    _sources.removeWhere((s) => s.name == source.name);
    _sources.add(source);
    await _save();
  }

  Future<void> removeSource(String name) async {
    _sources.removeWhere((s) => s.name == name);
    await _save();
  }

  Future<void> toggleSource(String name, bool enabled) async {
    for (final s in _sources) {
      if (s.name == name) {
        s.enabled = enabled;
        break;
      }
    }
    await _save();
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
