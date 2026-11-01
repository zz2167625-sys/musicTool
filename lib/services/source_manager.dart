import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_source.dart';

class SourceManager extends ChangeNotifier {
  SourceManager._();

  static final SourceManager instance = SourceManager._();

  static const _key = 'music_sources';

  final List<MusicSource> _sources = [];

  List<MusicSource> get sources => List.unmodifiable(_sources);

  List<MusicSource> get enabledSources =>
      _sources.where((s) => s.enabled).toList();

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
    notifyListeners();
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
