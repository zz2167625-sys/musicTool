Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return {};
}

Map<String, String> _asStringMap(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val.toString()));
  }
  return {};
}

class SearchConfig {
  final String path;
  final String method;
  final String keywordParam;
  final Map<String, dynamic> params;
  final Map<String, dynamic> body;

  const SearchConfig({
    required this.path,
    required this.method,
    required this.keywordParam,
    required this.params,
    required this.body,
  });

  factory SearchConfig.fromJson(Map<String, dynamic> json) => SearchConfig(
        path: json['path']?.toString() ?? '',
        method: (json['method']?.toString() ?? 'GET').toUpperCase(),
        keywordParam: json['keywordParam']?.toString() ?? 'keywords',
        params: _asMap(json['params']),
        body: _asMap(json['body']),
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'method': method,
        'keywordParam': keywordParam,
        'params': params,
        'body': body,
      };
}

class Mapping {
  final String list;
  final String id;
  final String title;
  final String artist;
  final String album;
  final String cover;
  final String url;
  final String duration;
  final String durationUnit;

  const Mapping({
    required this.list,
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.cover,
    required this.url,
    required this.duration,
    required this.durationUnit,
  });

  factory Mapping.fromJson(Map<String, dynamic> json) => Mapping(
        list: json['list']?.toString() ?? '',
        id: json['id']?.toString() ?? 'id',
        title: json['title']?.toString() ?? 'name',
        artist: json['artist']?.toString() ?? 'artists',
        album: json['album']?.toString() ?? 'album',
        cover: json['cover']?.toString() ?? 'picUrl',
        url: json['url']?.toString() ?? 'url',
        duration: json['duration']?.toString() ?? 'duration',
        durationUnit: (json['durationUnit']?.toString() ?? 's').toLowerCase(),
      );

  Map<String, dynamic> toJson() => {
        'list': list,
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'cover': cover,
        'url': url,
        'duration': duration,
        'durationUnit': durationUnit,
      };
}

class MusicSource {
  final String name;
  final String version;
  final String baseUrl;
  final Map<String, String> headers;
  final SearchConfig search;
  final Mapping mapping;
  bool enabled;

  MusicSource({
    required this.name,
    required this.version,
    required this.baseUrl,
    required this.headers,
    required this.search,
    required this.mapping,
    this.enabled = true,
  });

  factory MusicSource.fromJson(Map<String, dynamic> json) {
    final searchJson = json['search'];
    final mappingJson = json['mapping'];
    if (searchJson is! Map || mappingJson is! Map) {
      throw const FormatException('缺少 search 或 mapping 配置');
    }
    final name = json['name']?.toString();
    final baseUrl = json['baseUrl']?.toString();
    if (name == null || name.isEmpty) {
      throw const FormatException('name 不能为空');
    }
    if (baseUrl == null || baseUrl.isEmpty) {
      throw const FormatException('baseUrl 不能为空');
    }
    return MusicSource(
      name: name,
      version: json['version']?.toString() ?? '1.0.0',
      baseUrl: baseUrl,
      headers: _asStringMap(json['headers']),
      search: SearchConfig.fromJson(searchJson.cast<String, dynamic>()),
      mapping: Mapping.fromJson(mappingJson.cast<String, dynamic>()),
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'baseUrl': baseUrl,
        'headers': headers,
        'search': search.toJson(),
        'mapping': mapping.toJson(),
        'enabled': enabled,
      };

  String get _normalizedBase =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Uri buildSearchUri({String? keyword}) {
    final path = search.path.isEmpty
        ? ''
        : (search.path.startsWith('/') ? search.path : '/${search.path}');
    final query =
        search.params.map((k, v) => MapEntry(k, v.toString()));
    if (keyword != null) {
      query[search.keywordParam] = keyword;
    }
    return Uri.parse('$_normalizedBase$path').replace(queryParameters: query);
  }

  String resolveUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) return raw;
    return Uri.parse(_normalizedBase).resolve(raw).toString();
  }
}
