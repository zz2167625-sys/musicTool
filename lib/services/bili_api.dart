import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// B 站公开接口封装：匿名 Cookie、wbi 签名、视频搜索、视频/音频取流。
/// 供 bilibili 音乐源适配器与 MV 检索共用。
class BiliApi {
  BiliApi._();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      'Chrome/121.0.0.0 Safari/537.36';
  static const _referer = 'https://www.bilibili.com/';

  static String? _cookie;
  static String? _mixinKey;
  static int _keysAt = 0;

  static const _mixinTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5,
    49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55,
    40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57,
    62, 11, 36, 20, 34, 44, 52,
  ];

  static Map<String, String> get _headers => {
        'User-Agent': _ua,
        'Referer': _referer,
        'Cookie': ?_cookie,
      };

  static Future<void> _ensureSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_mixinKey != null && now - _keysAt < 12 * 3600 * 1000) return;
    if (_cookie == null) {
      try {
        final resp = await http
            .get(Uri.parse('https://www.bilibili.com/'),
                headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 10));
        final cookies = <String, String>{};
        final setCookies = resp.headers['set-cookie'];
        if (setCookies != null) {
          for (final part in setCookies.split(';')) {
            final idx = part.indexOf('=');
            if (idx > 0) {
              cookies[part.substring(0, idx).trim()] =
                  part.substring(idx + 1).trim();
            }
          }
        }
        final buf = <String>[];
        for (final name in ['buvid3', 'buvid4', 'b_nut', '_uuid']) {
          final value = cookies[name];
          if (value != null) buf.add('$name=$value');
        }
        if (buf.isNotEmpty) _cookie = buf.join('; ');
      } catch (_) {}
    }
    try {
      final nav =
          await _getJson('https://api.bilibili.com/x/web-interface/nav');
      final wbi = (nav is Map ? nav['data'] : null);
      final wbiImg = (wbi is Map ? wbi['wbi_img'] : null);
      final img = (wbiImg is Map ? wbiImg['img_url'] : null)
          ?.toString()
          .split('/')
          .last
          .split('.')
          .first;
      final sub = (wbiImg is Map ? wbiImg['sub_url'] : null)
          ?.toString()
          .split('/')
          .last
          .split('.')
          .first;
      if (img != null && sub != null) {
        _mixinKey = _mixinTab.map((i) => (img + sub)[i]).join().substring(0, 32);
        _keysAt = now;
      }
    } catch (_) {}
  }

  static Future<dynamic> _getJson(String url) async {
    final resp =
        await http.get(Uri.parse(url), headers: _headers).timeout(
            const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static Map<String, String> _signed(Map<String, String> params) {
    final mixinKey = _mixinKey;
    if (mixinKey == null) return params;
    params['wts'] =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final query = (params.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    params['w_rid'] = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return params;
  }

  static String _query(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  static String _stripHtml(String text) =>
      text.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  /// 搜索视频（bilibili 音乐源适配器用），返回 Song 列表（url 留空，播放时解析）。
  static Future<List<Song>> searchSongs(String keyword, String sourceName) async {
    try {
      await _ensureSession();
      final data = await _getJson(
          'https://api.bilibili.com/x/web-interface/wbi/search/type?'
          '${_query(_signed({'search_type': 'video', 'keyword': keyword, 'page': '1', 'page_size': '30'}))}');
      final result = (data is Map ? data['data'] : null);
      final videos = (result is Map ? result['result'] : null);
      if (videos is! List) return const [];
      final songs = <Song>[];
      for (final v in videos) {
        if (v is! Map) continue;
        final bvid = v['bvid']?.toString() ?? '';
        final title = _stripHtml(v['title']?.toString() ?? '');
        if (bvid.isEmpty || title.isEmpty) continue;
        final duration = _parseDuration(v['duration']?.toString() ?? '');
        final pic = v['pic']?.toString() ?? '';
        songs.add(Song(
          id: bvid,
          title: title,
          artist: v['author']?.toString() ?? '',
          album: '',
          cover: pic.startsWith('//') ? 'https:$pic' : pic,
          url: '',
          duration: duration,
          sourceName: sourceName,
        ));
      }
      return songs;
    } catch (_) {
      return const [];
    }
  }

  static int? _parseDuration(String text) {
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return m * 60 + s;
  }

  /// 解析视频的纯音频流地址（dash audio baseUrl，匿名 64-128k）。
  static Future<String?> audioUrl(String bvid) async {
    try {
      await _ensureSession();
      final cid = await _viewCid(bvid);
      if (cid == null) return null;
      final data = await _getJson(
          'https://api.bilibili.com/x/player/playurl?'
          '${_query({'bvid': bvid, 'cid': cid, 'fnval': '16'})}');
      final dash = (data is Map ? data['data'] : null) is Map
          ? (data!['data'] as Map)['dash']
          : null;
      final audios = (dash is Map ? dash['audio'] : null);
      if (audios is! List || audios.isEmpty) return null;
      final sorted = audios
          .whereType<Map>()
          .toList()
        ..sort((a, b) =>
            ((a['bandwidth'] as num?) ?? 0).compareTo((b['bandwidth'] as num?) ?? 0));
      // 取中档码率（约 128k），避免最低档音质
      final pick = sorted[sorted.length ~/ 2];
      final url = pick['baseUrl']?.toString() ?? '';
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _viewCid(String bvid) async {
    final data = await _getJson(
        'https://api.bilibili.com/x/web-interface/view?'
        '${_query(_signed({'bvid': bvid}))}');
    final cid = ((data is Map ? data['data'] : null) is Map
            ? (data!['data'] as Map)['cid']
            : null)
        ?.toString();
    return (cid == null || cid.isEmpty) ? null : cid;
  }

  /// 解析视频直链（MV 用，360P 匿名可播）。
  static Future<String?> videoUrl(String bvid, String cid) async {
    try {
      final data = await _getJson(
          'https://api.bilibili.com/x/player/playurl?'
          '${_query(_signed({'bvid': bvid, 'cid': cid, 'qn': '16', 'fnval': '1'}))}');
      final durl = (data is Map ? data['data'] : null) is Map
          ? (data!['data'] as Map)['durl']
          : null;
      if (durl is! List || durl.isEmpty) return null;
      final url = (durl.first as Map?)?['url']?.toString();
      return (url == null || url.isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }

  /// MV 检索：搜索第一个视频并解析出视频直链。
  static Future<String?> resolveMv(String keyword) async {
    try {
      await _ensureSession();
      final data = await _getJson(
          'https://api.bilibili.com/x/web-interface/search/type?'
          'search_type=video&keyword=${Uri.encodeComponent(keyword)}');
      final result = (data is Map ? data['data'] : null);
      final videos = (result is Map ? result['result'] : null);
      if (videos is! List || videos.isEmpty) return null;
      final bvid = (videos.first as Map?)?['bvid']?.toString();
      if (bvid == null || bvid.isEmpty) return null;
      final cid = await _viewCid(bvid);
      if (cid == null) return null;
      return await videoUrl(bvid, cid);
    } catch (_) {
      return null;
    }
  }
}
