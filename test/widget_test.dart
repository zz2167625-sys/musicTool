import 'package:flutter_test/flutter_test.dart';
import 'package:my_tools/models/music_source.dart';
import 'package:my_tools/models/song.dart';
import 'package:my_tools/services/json_utils.dart';

void main() {
  group('MusicSource 解析', () {
    test('完整音源 JSON 能正确解析', () {
      final source = MusicSource.fromJson({
        'name': '示例源',
        'version': '1.0.0',
        'baseUrl': 'https://example.com/api/',
        'headers': {'Referer': 'https://example.com'},
        'search': {
          'path': '/search',
          'method': 'GET',
          'keywordParam': 'keywords',
          'params': {'limit': 20},
          'body': <String, dynamic>{},
        },
        'mapping': {
          'list': 'result.songs',
          'id': 'id',
          'title': 'name',
          'artist': 'artists',
          'album': 'album.name',
          'cover': 'picUrl',
          'url': 'url',
          'duration': 'duration',
          'durationUnit': 'ms',
        },
      });
      expect(source.name, '示例源');
      expect(source.search.keywordParam, 'keywords');
      expect(source.headers['Referer'], 'https://example.com');
      expect(source.mapping.durationUnit, 'ms');
      expect(source.buildSearchUri(keyword: '晴天').toString(),
          contains('keywords=%E6%99%B4%E5%A4%A9'));
    });

    test('缺少必填字段时抛异常', () {
      expect(() => MusicSource.fromJson({'name': 'x'}),
          throwsA(isA<FormatException>()));
      expect(
        () => MusicSource.fromJson({
          'name': 'x',
          'baseUrl': 'https://a.com',
          'search': <String, dynamic>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('相对 URL 会基于 baseUrl 解析', () {
      final source = MusicSource.fromJson({
        'name': 's',
        'baseUrl': 'https://example.com/api',
        'search': {'path': '/search'},
        'mapping': <String, dynamic>{},
      });
      expect(source.resolveUrl('/song.mp3'),
          'https://example.com/song.mp3');
      expect(source.resolveUrl('https://cdn.com/song.mp3'),
          'https://cdn.com/song.mp3');
    });
  });

  group('搜索响应映射', () {
    test('从嵌套结果中提取歌曲', () {
      const mapping = Mapping(
        list: 'result.songs',
        id: 'id',
        title: 'name',
        artist: 'artists',
        album: 'album.name',
        cover: 'picUrl',
        url: 'url',
        duration: 'duration',
        durationUnit: 'ms',
      );
      final data = {
        'result': {
          'songs': [
            {
              'id': 1,
              'name': '晴天',
              'artists': [
                {'name': '周杰伦'}
              ],
              'album': {'name': '叶惠美'},
              'picUrl': 'https://x.com/1.jpg',
              'url': 'https://x.com/1.mp3',
              'duration': 269000,
            }
          ]
        }
      };
      final songs = extractSongs(data, mapping, '示例源', (u) => u);
      expect(songs.length, 1);
      expect(songs.first.title, '晴天');
      expect(songs.first.artist, '周杰伦');
      expect(songs.first.album, '叶惠美');
      expect(songs.first.duration, 269);
      expect(songs.first.uid, '示例源::1');
    });

    test('缺字段的条目会被跳过', () {
      const mapping = Mapping(
        list: 'songs',
        id: 'id',
        title: 'name',
        artist: 'artists',
        album: 'album',
        cover: 'pic',
        url: 'url',
        duration: 'duration',
        durationUnit: 's',
      );
      final data = {
        'songs': [
          {'id': '1', 'name': '缺URL'},
          {'id': '2', 'name': '完整', 'url': 'https://x.com/2.mp3'},
        ]
      };
      final songs = extractSongs(data, mapping, 's', (u) => u);
      expect(songs.length, 1);
      expect(songs.first.title, '完整');
    });
  });

  group('Song 序列化', () {
    test('toJson/fromJson 往返一致', () {
      const song = Song(
        id: '1',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        cover: 'https://x.com/1.jpg',
        url: 'https://x.com/1.mp3',
        duration: 269,
        sourceName: '示例源',
      );
      final restored = Song.fromJson(song.toJson());
      expect(restored.uid, song.uid);
      expect(restored.title, song.title);
      expect(restored.duration, 269);
    });

    test('MediaItem 往返保留关键字段', () {
      const song = Song(
        id: '1',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        cover: 'https://x.com/1.jpg',
        url: 'https://x.com/1.mp3',
        duration: 269,
        sourceName: '示例源',
      );
      final restored = Song.fromMediaItem(song.toMediaItem());
      expect(restored.uid, song.uid);
      expect(restored.url, song.url);
      expect(restored.cover, song.cover);
    });
  });
}
