import '../models/song.dart';
import 'local_store.dart';
import 'player_handler.dart';
import 'source_manager.dart';

class PlayUtils {
  static Future<void> playSongs(List<Song> songs, int startIndex) async {
    if (songs.isEmpty || startIndex < 0 || startIndex >= songs.length) return;
    final source = SourceManager.instance.byName(songs[startIndex].sourceName);
    await playerHandler.playQueue(songs, startIndex,
        headers: source?.headers);
    await LocalStore.instance.addRecent(songs[startIndex]);
  }
}
