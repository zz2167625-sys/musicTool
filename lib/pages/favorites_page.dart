import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/local_store.dart';
import '../services/play_utils.dart';
import '../widgets/song_tile.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  Future<void> _play(
    BuildContext context,
    List<Song> songs,
    bool shuffle,
  ) async {
    final ok = shuffle
        ? await PlayUtils.shuffleAll(songs)
        : await PlayUtils.playAll(songs);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法获取播放地址，请换一首或检查音源')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: LocalStore.instance,
      builder: (context, _) {
        final favorites = LocalStore.instance.favorites;
        return Scaffold(
          appBar: AppBar(
            title: const Text('收藏'),
            centerTitle: false,
            actions: [
              if (favorites.isNotEmpty) ...[
                IconButton(
                  tooltip: '随机播放',
                  icon: const Icon(Icons.shuffle_rounded),
                  onPressed: () => _play(context, favorites, true),
                ),
                IconButton(
                  tooltip: '播放全部',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => _play(context, favorites, false),
                ),
              ],
            ],
          ),
          body: favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        size: 48,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '还没有收藏的歌曲',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: favorites.length,
                  itemBuilder: (context, i) => SongTile(
                    song: favorites[i],
                    onTap: () async {
                      if (!await PlayUtils.playSongs(favorites, i) &&
                          context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取播放地址')),
                        );
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite),
                      color: scheme.primary,
                      onPressed: () =>
                          LocalStore.instance.toggleFavorite(favorites[i]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
