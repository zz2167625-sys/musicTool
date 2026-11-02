import '../models/song.dart';
import 'local_store.dart';
import 'music_api.dart';
import 'player_handler.dart';
import 'source_manager.dart';

class PlayUtils {
  /// 解析播放地址后开始播放；返回是否成功开始播放。
  static Future<bool> playSongs(List<Song> songs, int startIndex) async {
    if (songs.isEmpty || startIndex < 0 || startIndex >= songs.length) {
      return false;
    }
    final target = songs[startIndex];
    final resolved = await MusicApi.resolveUrls(songs);
    final newStart = resolved.indexWhere((s) => s.uid == target.uid);
    if (newStart < 0) return false;
    await playerHandler.playQueue(resolved, newStart);
    await LocalStore.instance.addRecent(resolved[newStart]);
    return true;
  }

  /// 播放整个列表（从第一首开始）。
  static Future<bool> playAll(List<Song> songs) => playSongs(songs, 0);

  /// 随机播放整个列表：先随机选一首作为起点。
  static Future<bool> shuffleAll(List<Song> songs) {
    if (songs.isEmpty) return Future.value(false);
    final start = DateTime.now().microsecondsSinceEpoch % songs.length;
    return playSongs(songs, start);
  }

  /// 该歌曲是否来自本地文件（本地音乐不需要网络解析）。
  static bool isLocal(Song song) =>
      song.url.startsWith('file://') || song.sourceName == '本地音乐';

  /// 当前音源的展示名称，找不到时回退到歌曲自带来源。
  static String sourceLabel(Song song) {
    final source = SourceManager.instance.byName(song.sourceName);
    return source?.name ?? song.sourceName;
  }
}
