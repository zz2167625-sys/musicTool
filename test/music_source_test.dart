import 'package:flutter_test/flutter_test.dart';
import 'package:my_tools/models/music_source.dart';
import 'package:my_tools/services/json_utils.dart';

void main() {
  group('音乐源映射', () {
    test('filter 只保留满足条件的条目', () {
      final mapping = Mapping.fromJson({
        'list': 'data',
        'id': 'id',
        'title': 'title',
        'artist': 'artist',
        'url': 'url',
        'filter': {'is_streamable': true},
      });
      final songs = extractSongs(
        {
          'data': [
            {
              'id': 1,
              'title': '可播放',
              'artist': 'A',
              'url': 'https://a/1.mp3',
              'is_streamable': true,
            },
            {
              'id': 2,
              'title': '不可播放',
              'artist': 'B',
              'url': 'https://a/2.mp3',
              'is_streamable': false,
            },
            {'id': 3, 'title': '缺字段', 'artist': 'C', 'url': 'https://a/3.mp3'},
          ],
        },
        mapping,
        '测试源',
        (raw) => raw,
      );
      expect(songs.map((s) => s.title).toList(), ['可播放']);
    });

    test('checkPlayable 会被解析', () {
      final source = MusicSource.fromJson({
        'name': '测试源',
        'baseUrl': 'https://example.com',
        'search': {'path': '/search'},
        'mapping': {
          'title': 'name',
          'url': 'url',
          'checkPlayable': true,
          'checkPlayableOnSearch': true,
        },
      });
      expect(source.mapping.checkPlayable, isTrue);
      expect(source.mapping.checkPlayableOnSearch, isTrue);
      expect(source.toJson()['mapping']['checkPlayable'], isTrue);
      expect(source.toJson()['mapping']['checkPlayableOnSearch'], isTrue);
    });

    test('notes 会被保留', () {
      final source = MusicSource.fromJson({
        'name': '测试源',
        'baseUrl': 'https://example.com',
        'notes': '仅供测试',
        'search': {'path': '/search'},
        'mapping': {'title': 'name', 'url': 'url'},
      });
      expect(source.notes, '仅供测试');
      expect(source.toJson()['notes'], '仅供测试');
    });

    test('数值型 filter 支持字符串字段', () {
      expect(matchesFilter({'fee': '0'}, {'fee': 0}), isTrue);
      expect(matchesFilter({'fee': '1'}, {'fee': 0}), isFalse);
    });
  });
}
