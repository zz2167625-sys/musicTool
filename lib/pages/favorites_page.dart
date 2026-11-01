import 'package:flutter/material.dart';

import '../services/local_store.dart';
import '../services/play_utils.dart';
import '../widgets/song_tile.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: LocalStore.instance,
        builder: (context, _) {
          final favorites = LocalStore.instance.favorites;
          if (favorites.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有收藏的歌曲',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, i) => SongTile(
              song: favorites[i],
              onTap: () => PlayUtils.playSongs(favorites, i),
              trailing: IconButton(
                icon: const Icon(Icons.favorite),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () =>
                    LocalStore.instance.toggleFavorite(favorites[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}
