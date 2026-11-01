import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_source.dart';
import '../models/song.dart';
import 'json_utils.dart';

class MusicApi {
  static const _timeout = Duration(seconds: 12);

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
}
