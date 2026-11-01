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
        title: const Text('音乐盒子'),
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
              const SizedBox(height: 8),
              Text(
                '聚合多源搜索，一处听遍全网',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              if (!hasSources)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_download_outlined,
                          color:
                              Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '还没有音乐源。到「我的」页面导入音乐源后，即可搜索全网歌曲。',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
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
                    onTap: () =>
                        PlayUtils.playSongs(recents, recents.indexOf(song)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
