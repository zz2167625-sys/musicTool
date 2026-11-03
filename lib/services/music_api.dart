import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_source.dart';
import '../models/song.dart';
import 'bili_api.dart';
import 'json_utils.dart';
import 'source_manager.dart';

/// 单个音乐源的搜索报告：结果 + 失败原因，便于搜索页展示每个源的覆盖情况。
class SourceSearchReport {
  const SourceSearchReport({
    required this.sourceName,
    required this.songs,
    this.error,
  });

  final String sourceName;
  final List<Song> songs;
  final String? error;

  bool get ok => error == null;
}

/// 聚合搜索报告：去重后的歌曲列表 + 每个源的结果。
class SearchReport {
  const SearchReport({required this.songs, required this.sources});

  final List<Song> songs;
  final List<SourceSearchReport> sources;
}

class MusicApi {
  static const _timeout = Duration(seconds: 12);
  static const _probeTimeout = Duration(seconds: 7);
  static const _urlCacheTtl = Duration(minutes: 10);

  static final Map<String, ({String url, int at})> _urlCache = {};
  static final Map<String, ({bool ok, int at})> _probeCache = {};

  static Future<List<Song>> search(
    String keyword,
    List<MusicSource> sources,
  ) async {
    final report = await searchDetailed(keyword, sources);
    return report.songs;
  }

  /// 同时搜索多个源，返回逐源报告与去重后的合并结果。
  /// 去重规则：同名同歌手只保留第一个来源的结果。
  static Future<SearchReport> searchDetailed(
    String keyword,
    List<MusicSource> sources,
  ) async {
    final reports = await Future.wait(
      sources.map((s) => _searchOne(keyword, s)),
    );
    final seen = <String>{};
    final songs = <Song>[];
    for (final report in reports) {
      for (final song in report.songs) {
        if (seen.add('${song.title}|${song.artist}')) {
          songs.add(song);
        }
      }
    }
    return SearchReport(songs: songs, sources: reports);
  }

  /// 对单个音乐源执行一次搜索（设置页「测试」使用，不计入自动停用统计）。
  static Future<SourceSearchReport> testSource(
    MusicSource source, {
    String keyword = '周杰伦',
  }) => _searchOne(keyword, source, recordHealth: false);

  static Future<SourceSearchReport> _searchOne(
    String keyword,
    MusicSource source, {
    bool recordHealth = true,
  }) async {
    try {
      if (source.adapter == 'bilibili') {
        final songs = await BiliApi.searchSongs(keyword, source.name);
        if (songs.isEmpty) {
          if (recordHealth) {
            SourceManager.instance.recordSourceFailure(source.name);
          }
          return SourceSearchReport(
            sourceName: source.name,
            songs: const [],
            error: '没有可用结果',
          );
        }
        if (recordHealth) {
          SourceManager.instance.recordSourceSuccess(source.name);
        }
        return SourceSearchReport(sourceName: source.name, songs: songs);
      }
      final headers = {...source.headers, 'User-Agent': 'zephyr/2.3'};
      http.Response resp;
      if (source.search.method == 'POST') {
        final bodyText = jsonEncode(source.search.body);
        final body = bodyText.contains('{keyword}')
            ? _substituteKeyword(source.search.body, keyword)
            : {
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
      if (resp.statusCode != 200) {
        if (recordHealth) {
          SourceManager.instance.recordSourceFailure(source.name);
        }
        return SourceSearchReport(
          sourceName: source.name,
          songs: const [],
          error: 'HTTP ${resp.statusCode}',
        );
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      var songs = extractSongs(
        data,
        source.mapping,
        source.name,
        source.resolveUrl,
      );
      if (songs.isEmpty) {
        if (recordHealth) {
          SourceManager.instance.recordSourceFailure(source.name);
        }
        return SourceSearchReport(
          sourceName: source.name,
          songs: const [],
          error: '没有可用结果',
        );
      }
      if (source.mapping.checkPlayableOnSearch) {
        songs = await _filterPlayable(songs, source, headers);
        if (songs.isEmpty) {
          // 接口本身正常，只是没有可播曲目，不计入失败次数。
          return SourceSearchReport(
            sourceName: source.name,
            songs: const [],
            error: '无可用版权曲目',
          );
        }
      }
      if (recordHealth) {
        SourceManager.instance.recordSourceSuccess(source.name);
      }
      return SourceSearchReport(sourceName: source.name, songs: songs);
    } on TimeoutException {
      if (recordHealth) {
        SourceManager.instance.recordSourceFailure(source.name);
      }
      return SourceSearchReport(
        sourceName: source.name,
        songs: const [],
        error: '请求超时',
      );
    } on FormatException {
      if (recordHealth) {
        SourceManager.instance.recordSourceFailure(source.name);
      }
      return SourceSearchReport(
        sourceName: source.name,
        songs: const [],
        error: '返回格式异常',
      );
    } catch (_) {
      if (recordHealth) {
        SourceManager.instance.recordSourceFailure(source.name);
      }
      return SourceSearchReport(
        sourceName: source.name,
        songs: const [],
        error: '网络异常',
      );
    }
  }

  /// 解析队列中所有歌曲的播放地址：
  /// - 已带地址的歌曲直接复用；
  /// - 配置了 urlTemplate 的按模板拼接；
  /// - 配置了 urlResolve 的二次请求解析；
  /// - 开启 checkPlayable 的源会做一次音频可用性探测，剔除死链。
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

  static dynamic _substituteKeyword(dynamic value, String keyword) {
    if (value is String) return value.replaceAll('{keyword}', keyword);
    if (value is Map) {
      return value.map(
          (k, v) => MapEntry(k, _substituteKeyword(v, keyword)));
    }
    if (value is List) {
      return value.map((e) => _substituteKeyword(e, keyword)).toList();
    }
    return value;
  }

  static Future<Song?> _resolveOne(Song song) async {
    final source = SourceManager.instance.byName(song.sourceName);
    if (source == null) {
      return song.url.isEmpty ? null : song;
    }
    if (source.adapter == 'bilibili') {
      final cached = _urlCache[song.uid];
      if (cached != null &&
          DateTime.now().millisecondsSinceEpoch - cached.at <
              _urlCacheTtl.inMilliseconds) {
        return cached.url.isEmpty ? null : song.copyWith(url: cached.url);
      }
      final url = await BiliApi.audioUrl(song.id) ?? '';
      _urlCache[song.uid] = (
        url: url,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      return url.isEmpty ? null : song.copyWith(url: url);
    }
    final headers = {...source.headers, 'User-Agent': 'zephyr/2.3'};

    var url = song.url;
    final config = source.mapping.urlResolve;
    if (config != null) {
      // urlResolve 生成的地址通常带时效，收藏/最近播放里的旧地址可能已过期，
      // 因此每次播放都重新解析（10 分钟内命中缓存）。
      url = await _resolveWithRequest(song, source, config, headers) ?? '';
    } else if (url.isEmpty) {
      final template = source.mapping.urlTemplate;
      if (template.isNotEmpty) {
        url =
            resolveTemplateUrl(template, {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
            }) ??
            '';
      }
    }
    if (url.isEmpty) return null;
    url = source.resolveUrl(url);

    if (source.mapping.checkPlayable && !await _isPlayable(url, headers)) {
      return null;
    }
    return url == song.url ? song : song.copyWith(url: url);
  }

  static Future<String?> _resolveWithRequest(
    Song song,
    MusicSource source,
    UrlResolveConfig config,
    Map<String, String> headers,
  ) async {
    final cacheKey = song.uid;
    final cached = _urlCache[cacheKey];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.at <
            _urlCacheTtl.inMilliseconds) {
      return cached.url.isEmpty ? null : cached.url;
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
      http.Response resp;
      if (config.method == 'POST') {
        final body = config.body.map(
          (k, v) => MapEntry(k, v is String ? substituteFields(v, values) : v),
        );
        resp = await http
            .post(
              uri,
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
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
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }

  /// 搜索阶段过滤：只保留能真正返回音频的条目。
  static Future<List<Song>> _filterPlayable(
    List<Song> songs,
    MusicSource source,
    Map<String, String> headers,
  ) async {
    final result = <Song>[];
    for (var i = 0; i < songs.length; i += 8) {
      final chunk = songs.skip(i).take(8);
      final checked = await Future.wait(
        chunk.map((song) async {
          final url = _candidateUrl(song, source);
          if (url == null) return null;
          return await _isPlayable(url, headers) ? song : null;
        }),
      );
      result.addAll(checked.whereType<Song>());
    }
    return result;
  }

  /// 只使用直链或 urlTemplate 计算候选地址（搜索阶段没有 id 之外的字段）。
  static String? _candidateUrl(Song song, MusicSource source) {
    if (song.url.isNotEmpty) return source.resolveUrl(song.url);
    final template = source.mapping.urlTemplate;
    if (template.isEmpty) return null;
    final raw = resolveTemplateUrl(template, {
      'id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
    });
    return raw == null ? null : source.resolveUrl(raw);
  }

  /// 探测地址是否真的返回音频（而不是版权提示网页），结果缓存 10 分钟。
  static Future<bool> _isPlayable(
    String url,
    Map<String, String> headers,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return true;
    }
    final cached = _probeCache[url];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.at <
            _urlCacheTtl.inMilliseconds) {
      return cached.ok;
    }
    var ok = false;
    try {
      final resp = await http
          .get(uri, headers: {...headers, 'Range': 'bytes=0-1'})
          .timeout(_probeTimeout);
      final type = (resp.headers['content-type'] ?? '').toLowerCase();
      ok =
          (resp.statusCode == 200 || resp.statusCode == 206) &&
          (type.startsWith('audio/') ||
              type.contains('octet-stream') ||
              type.contains('mpegurl'));
    } catch (_) {
      ok = false;
    }
    _probeCache[url] = (ok: ok, at: DateTime.now().millisecondsSinceEpoch);
    return ok;
  }
}
