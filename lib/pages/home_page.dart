import 'package:flutter/material.dart';

import '../services/local_store.dart';
import '../services/play_utils.dart';
import '../services/source_manager.dart';
import '../widgets/song_tile.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('zephyr'),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [LocalStore.instance, SourceManager.instance]),
        builder: (context, _) {
          final recents = LocalStore.instance.recents;
          final hasSources = SourceManager.instance.sources.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '发现好音乐',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              if (!hasSources)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '还没有音乐源，到「我的」页面导入后即可搜索全网歌曲。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '最近播放',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (recents.isNotEmpty)
                    Text(
                      '${recents.length} 首',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (recents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.music_note_outlined,
                          size: 48,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '播放过的歌曲会出现在这里',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...recents.map(
                  (song) => SongTile(
                    song: song,
                    onTap: () async {
                      final i = recents.indexOf(song);
                      if (!await PlayUtils.playSongs(recents, i) &&
                          context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取播放地址')),
                        );
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
