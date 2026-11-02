import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/local_store.dart';
import '../services/play_utils.dart';
import '../services/source_manager.dart';

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: song.cover.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHigh,
                        child: Icon(
                          Icons.music_note,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Image.network(
                        song.cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.music_note,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
          .showSnackBar(const SnackBar(content: Text('无法获取播放地址')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('zephyr'), centerTitle: false),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          LocalStore.instance,
          SourceManager.instance,
        ]),
        builder: (context, _) {
          final recents = LocalStore.instance.recents;
          final hasSources = SourceManager.instance.sources.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '发现好音乐',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
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
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (recents.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${recents.length} 首',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        IconButton(
                          tooltip: '随机播放最近',
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          onPressed: () => _play(context, recents, true),
                        ),
                        IconButton(
                          tooltip: '播放全部',
                          icon: const Icon(Icons.play_circle_outline, size: 22),
                          onPressed: () => _play(context, recents, false),
                        ),
                      ],
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.35,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: recents.length,
                  itemBuilder: (context, i) => _RecentCard(
                    song: recents[i],
                    onTap: () async {
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
