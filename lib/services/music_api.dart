import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_source.dart';
import '../models/song.dart';
import 'json_utils.dart';
import 'source_manager.dart';

class MusicApi {
  static const _timeout = Duration(seconds: 12);
  static const _urlCacheTtl = Duration(minutes: 10);

  static final Map<String, ({String url, int at})> _urlCache = {};

  static Future<List<Song>> search(
      String keyword, List<MusicSource> sources) async {
    final results =
        await Future.wait(sources.map((s) => _searchOne(keyword, s)));
    final songs = <Song>[];
    for (final r in results) {
      if (r != null) songs.addAll(r);
    }
    return songs;
  }

  static Future<List<Song>?> _searchOne(
      String keyword, MusicSource source) async {
    try {
      final headers = {...source.headers, 'User-Agent': 'musicTool/1.0'};
      http.Response resp;
      if (source.search.method == 'POST') {
        final body = {
          source.search.keywordParam: keyword,
          ...source.search.body,
        };
        resp = await http
            .post(
              source.buildSearchUri(),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_timeout);
      } else {
        resp = await http
            .get(source.buildSearchUri(keyword: keyword), headers: headers)
            .timeout(_timeout);
      }
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return extractSongs(data, source.mapping, source.name, source.resolveUrl);
    } catch (_) {
      return null;
    }
  }

  /// 解析队列中所有歌曲的播放地址（url 为空的走 urlResolve 二次请求），
  /// 失败或无法解析的歌曲会被剔除。
  static Future<List<Song>> resolveUrls(List<Song> songs) async {
    final resolved = <Song>[];
    for (var i = 0; i < songs.length; i += 6) {
      final chunk = songs.skip(i).take(6);
      final results = await Future.wait(chunk.map(_resolveOne));
      for (final r in results) {
        if (r != null) resolved.add(r);
      }
    }
    return resolved;
  }

  static Future<Song?> _resolveOne(Song song) async {
    if (song.url.isNotEmpty) return song;
    final source = SourceManager.instance.byName(song.sourceName);
    final config = source?.mapping.urlResolve;
    if (source == null || config == null) return null;

    final cacheKey = song.uid;
    final cached = _urlCache[cacheKey];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.at <
            _urlCacheTtl.inMilliseconds) {
      return cached.url.isEmpty ? null : song.copyWith(url: cached.url);
    }

    try {
      final values = {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
      };
      final path = substituteFields(config.path, values);
      final base = source.baseUrl.endsWith('/')
          ? source.baseUrl.substring(0, source.baseUrl.length - 1)
          : source.baseUrl;
      final uri = Uri.parse(base).resolve(path);
      final headers = {...source.headers, 'User-Agent': 'musicTool/1.0'};
      http.Response resp;
      if (config.method == 'POST') {
        final body = config.body.map((k, v) => MapEntry(
            k, v is String ? substituteFields(v, values) : v));
        resp = await http
            .post(uri,
                headers: {...headers, 'Content-Type': 'application/json'},
                body: jsonEncode(body))
            .timeout(_timeout);
      } else {
        resp = await http.get(uri, headers: headers).timeout(_timeout);
      }
      if (resp.statusCode != 200) return null;
      final bodyText = utf8.decode(resp.bodyBytes);
      dynamic data;
      try {
        data = jsonDecode(bodyText);
      } catch (_) {
        // 取链接口可能直接返回纯文本 URL（如酷我 anti.s）
        data = bodyText;
      }
      final raw = asText(getPath(data, config.urlPath));
      final url = raw.isEmpty ? '' : source.resolveUrl(raw);
      _urlCache[cacheKey] = (
        url: url,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      return url.isEmpty ? null : song.copyWith(url: url);
    } catch (_) {
      return null;
    }
  }
}
