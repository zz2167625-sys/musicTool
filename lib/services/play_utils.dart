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
    final source =
        SourceManager.instance.byName(resolved[newStart].sourceName);
    await playerHandler.playQueue(resolved, newStart,
        headers: source?.headers);
    await LocalStore.instance.addRecent(resolved[newStart]);
    return true;
  }
}
