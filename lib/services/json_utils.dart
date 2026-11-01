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

Song? extractSong(
  dynamic item,
  Mapping mapping,
  String sourceName,
  String Function(String raw) resolveUrl,
) {
  if (item is! Map) return null;
  final id = asText(getPath(item, mapping.id));
  final title = asText(getPath(item, mapping.title));
  final rawUrl = asText(getPath(item, mapping.url));
  if (id.isEmpty || title.isEmpty || rawUrl.isEmpty) return null;

  int? duration;
  final d = getPath(item, mapping.duration);
  if (d is num) {
    duration = mapping.durationUnit == 'ms' ? (d / 1000).round() : d.round();
  }

  final rawCover = asText(getPath(item, mapping.cover));
  return Song(
    id: id,
    title: title,
    artist: artistText(getPath(item, mapping.artist)),
    album: albumText(getPath(item, mapping.album)),
    cover: rawCover.isEmpty ? '' : resolveUrl(rawCover),
    url: resolveUrl(rawUrl),
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
