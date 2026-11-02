import '../models/music_source.dart';
import '../models/song.dart';

dynamic getPath(dynamic data, String path) {
  if (path.isEmpty) return data;
  dynamic cur = data;
  for (final part in path.split('.')) {
    if (cur is Map) {
      cur = cur[part];
    } else if (cur is List && int.tryParse(part) != null) {
      cur = cur[int.parse(part)];
    } else {
      return null;
    }
  }
  return cur;
}

String asText(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return '';
}

String artistText(dynamic v) {
  if (v == null) return '';
  if (v is List) {
    return v.map(artistText).where((s) => s.isNotEmpty).join(' / ');
  }
  if (v is Map) {
    for (final key in const ['name', 'nickname', 'title', 'username']) {
      if (v[key] != null) return asText(v[key]);
    }
    return '';
  }
  return asText(v);
}

String albumText(dynamic v) {
  if (v is Map) {
    for (final key in const ['name', 'title']) {
      if (v[key] != null) return asText(v[key]);
    }
    return '';
  }
  return asText(v);
}

/// 用 values 中的字段值替换模板中的 {field} 占位符。
String substituteFields(String template, Map<String, String> values) {
  final matches = RegExp(r'\{([^{}]+)\}').allMatches(template);
  var out = template;
  for (final m in matches) {
    final field = m.group(1)!;
    final value = values[field] ?? '';
    out = out.replaceAll('{$field}', Uri.encodeComponent(value));
  }
  return out;
}

/// 将 URL 模板（如 https://x/song?id={id}）按歌曲条目字段解析为完整 URL。
String? resolveTemplateUrl(String template, Map<dynamic, dynamic> item) {
  if (template.isEmpty) return null;
  final values = <String, String>{};
  final matches = RegExp(r'\{([^{}]+)\}').allMatches(template);
  for (final m in matches) {
    values[m.group(1)!] = asText(getPath(item, m.group(1)!));
  }
  final result = substituteFields(template, values);
  return result.isEmpty ? null : result;
}

/// 条目过滤：filter 中的每个字段路径都必须与期望值一致。
/// 支持布尔、数字与字符串三种期望值；字段缺失时按不匹配处理（false 除外）。
bool matchesFilter(dynamic item, Map<String, dynamic> filter) {
  for (final entry in filter.entries) {
    final actual = getPath(item, entry.key);
    final expected = entry.value;
    if (expected is bool) {
      if ((actual == true) != expected) return false;
    } else if (expected is num) {
      final parsed = actual is num ? actual : num.tryParse(asText(actual));
      if (parsed != expected) return false;
    } else {
      if (asText(actual) != expected.toString()) return false;
    }
  }
  return true;
}

Song? extractSong(
  dynamic item,
  Mapping mapping,
  String sourceName,
  String Function(String raw) resolveUrl,
) {
  if (item is! Map) return null;
  if (!matchesFilter(item, mapping.filter)) return null;
  final id = asText(getPath(item, mapping.id));
  final title = asText(getPath(item, mapping.title));
  if (id.isEmpty || title.isEmpty) return null;

  final rawUrl = asText(getPath(item, mapping.url));
  String url;
  if (rawUrl.isNotEmpty) {
    url = resolveUrl(rawUrl);
  } else {
    final fromTemplate = resolveTemplateUrl(mapping.urlTemplate, item);
    if (fromTemplate != null) {
      url = resolveUrl(fromTemplate);
    } else if (mapping.urlResolve != null) {
      // 播放地址需二次请求（urlResolve），此处留空，播放时再解析。
      url = '';
    } else {
      return null;
    }
  }

  int? duration;
  final d = getPath(item, mapping.duration);
  num? value;
  if (d is num) {
    value = d;
  } else if (d is String) {
    value = num.tryParse(d);
  }
  if (value != null) {
    duration = mapping.durationUnit == 'ms'
        ? (value / 1000).round()
        : value.round();
  }

  final rawCover = asText(getPath(item, mapping.cover));
  return Song(
    id: id,
    title: title,
    artist: artistText(getPath(item, mapping.artist)),
    album: albumText(getPath(item, mapping.album)),
    cover: rawCover.isEmpty ? '' : resolveUrl(rawCover),
    url: url,
    duration: duration,
    sourceName: sourceName,
  );
}

List<Song> extractSongs(
  dynamic data,
  Mapping mapping,
  String sourceName,
  String Function(String raw) resolveUrl,
) {
  final list = getPath(data, mapping.list);
  if (list is! List) return const [];
  final songs = <Song>[];
  for (final item in list) {
    final song = extractSong(item, mapping, sourceName, resolveUrl);
    if (song != null) songs.add(song);
  }
  return songs;
}
