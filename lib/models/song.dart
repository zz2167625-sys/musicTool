import 'package:audio_service/audio_service.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String cover;
  final String url;
  final int? duration;
  final String sourceName;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.cover,
    required this.url,
    this.duration,
    required this.sourceName,
  });

  String get uid => '$sourceName::$id';

  Song copyWith({String? url}) => Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        cover: cover,
        url: url ?? this.url,
        duration: duration,
        sourceName: sourceName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'cover': cover,
        'url': url,
        'duration': duration,
        'sourceName': sourceName,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        cover: json['cover']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        duration: (json['duration'] as num?)?.toInt(),
        sourceName: json['sourceName']?.toString() ?? '',
      );

  MediaItem toMediaItem() => MediaItem(
        id: uid,
        title: title,
        artist: artist,
        album: album.isEmpty ? sourceName : album,
        artUri: cover.isEmpty ? null : Uri.tryParse(cover),
        duration: duration == null ? null : Duration(seconds: duration!),
        extras: {
          'url': url,
          'sourceName': sourceName,
          'cover': cover,
          'songId': id,
        },
      );

  factory Song.fromMediaItem(MediaItem item) => Song(
        id: item.extras?['songId']?.toString() ?? item.id,
        title: item.title,
        artist: item.artist ?? '',
        album: item.album ?? '',
        cover: item.artUri?.toString() ?? '',
        url: item.extras?['url']?.toString() ?? '',
        duration: item.duration?.inSeconds,
        sourceName: item.extras?['sourceName']?.toString() ?? '',
      );
}
