import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// MV 检索服务：通过 B 站公开接口搜索歌曲 MV 并解析出可直接播放的视频地址。
/// 搜索 → 视频详情(cid) → wbi 签名取流，匿名可用，360P。
class MvService {
  MvService._();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      'Chrome/120.0 Safari/537.36';
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

  /// 根据「歌手 歌名」搜索 MV，返回可直接播放的视频地址；失败返回 null。
  static Future<String?> resolveMv(String keyword) async {
    try {
      await _ensureSession();
      final bvid = await _searchBvid(keyword);
      if (bvid == null) return null;
      final cid = await _viewCid(bvid);
      if (cid == null) return null;
      return await _playUrl(bvid, cid);
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> _getJson(String url) async {
    final resp = await http.get(Uri.parse(url), headers: _headers).timeout(
        const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

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
    final nav = await _getJson('https://api.bilibili.com/x/web-interface/nav');
    final wbi = (nav is Map ? nav['data'] : null);
    final img = ((wbi is Map ? wbi['wbi_img'] : null) is Map
            ? (wbi!['wbi_img'] as Map)['img_url']
            : null)
        ?.toString()
        .split('/')
        .last
        .split('.')
        .first;
    final sub = ((wbi is Map ? wbi['wbi_img'] : null) is Map
            ? (wbi!['wbi_img'] as Map)['sub_url']
            : null)
        ?.toString()
        .split('/')
        .last
        .split('.')
        .first;
    if (img != null && sub != null) {
      final raw = img + sub;
      _mixinKey =
          _mixinTab.map((i) => raw[i]).join().substring(0, 32);
      _keysAt = now;
    }
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

  static String _query(Map<String, String> params) =>
      params.entries.map((e) =>
          '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  static Future<String?> _searchBvid(String keyword) async {
    final data = await _getJson(
        'https://api.bilibili.com/x/web-interface/search/type?'
        'search_type=video&keyword=${Uri.encodeComponent(keyword)}');
    final result = (data is Map ? data['data'] : null);
    final videos = (result is Map ? result['result'] : null);
    if (videos is! List || videos.isEmpty) return null;
    final bvid = (videos.first as Map?)?['bvid']?.toString();
    return (bvid == null || bvid.isEmpty) ? null : bvid;
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

  static Future<String?> _playUrl(String bvid, String cid) async {
    final data = await _getJson(
        'https://api.bilibili.com/x/player/playurl?'
        '${_query(_signed({'bvid': bvid, 'cid': cid, 'qn': '16', 'fnval': '1'}))}');
    final durl = (data is Map ? data['data'] : null) is Map
        ? (data!['data'] as Map)['durl']
        : null;
    if (durl is! List || durl.isEmpty) return null;
    final url = (durl.first as Map?)?['url']?.toString();
    return (url == null || url.isEmpty) ? null : url;
  }
}
