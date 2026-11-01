import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class LocalStore extends ChangeNotifier {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  static const _favKey = 'favorites';
  static const _recentKey = 'recents';
  static const _maxRecents = 50;

  List<Song> _favorites = [];
  List<Song> _recents = [];

  List<Song> get favorites => List.unmodifiable(_favorites);

  List<Song> get recents => List.unmodifiable(_recents);

  Future<void> load() async {
    _favorites = await _getList(_favKey);
    _recents = await _getList(_recentKey);
    notifyListeners();
  }

  bool isFavorite(Song song) => _favorites.any((s) => s.uid == song.uid);

  Future<bool> toggleFavorite(Song song) async {
    final idx = _favorites.indexWhere((s) => s.uid == song.uid);
    bool nowFavorite;
    if (idx >= 0) {
      _favorites.removeAt(idx);
      nowFavorite = false;
    } else {
      _favorites.insert(0, song);
      nowFavorite = true;
    }
    notifyListeners();
    await _setList(_favKey, _favorites);
    return nowFavorite;
  }

  Future<void> addRecent(Song song) async {
    _recents.removeWhere((s) => s.uid == song.uid);
    _recents.insert(0, song);
    if (_recents.length > _maxRecents) {
      _recents.removeRange(_maxRecents, _recents.length);
    }
    notifyListeners();
    await _setList(_recentKey, _recents);
  }

  static Future<List<Song>> _getList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _setList(String key, List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        key, jsonEncode(songs.map((s) => s.toJson()).toList()));
  }
}
