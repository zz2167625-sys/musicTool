import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class LocalMusicManager extends ChangeNotifier {
  LocalMusicManager._();

  static final LocalMusicManager instance = LocalMusicManager._();

  static const sourceName = '本地音乐';
  static const _key = 'local_songs';

  final List<Song> _songs = [];

  List<Song> get songs => List.unmodifiable(_songs);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _songs
        ..clear()
        ..addAll(list.map(Song.fromJson));
    } catch (_) {
      _songs.clear();
    }
    _songs.removeWhere(_fileMissing);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_songs.map((s) => s.toJson()).toList()));
    notifyListeners();
  }

  bool _fileMissing(Song song) {
    final path = Uri.tryParse(song.url)?.toFilePath();
    return path == null || !File(path).existsSync();
  }

  Future<Directory> _musicDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}local_music');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<int> importMp3() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );
    if (files.isEmpty) return 0;
    final dir = await _musicDir();
    var imported = 0;
    for (final f in files) {
      final srcPath = f.path;
      if (srcPath == null) continue;
      final dest = File('${dir.path}${Platform.pathSeparator}${f.name}');
      try {
        await File(srcPath).copy(dest.path);
      } catch (e) {
        debugPrint('导入 MP3 失败：$e');
        continue;
      }
      final uri = dest.uri.toString();
      _songs.removeWhere((s) => s.url == uri);
      _songs.insert(
        0,
        Song(
          id: f.name,
          title: f.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          artist: '本地文件',
          album: sourceName,
          cover: '',
          url: uri,
          sourceName: sourceName,
        ),
      );
      imported++;
    }
    if (imported > 0) {
      await _save();
    }
    return imported;
  }

  Future<void> removeSong(Song song) async {
    _songs.removeWhere((s) => s.uid == song.uid);
    final path = Uri.tryParse(song.url)?.toFilePath();
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    await _save();
  }
}
