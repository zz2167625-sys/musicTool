import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../pages/player_page.dart';
import '../services/player_handler.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<MediaItem?>(
      stream: playerHandler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerPage()),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: item.artUri == null
                                  ? ColoredBox(
                                      color: scheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.music_note,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Image.network(
                                      item.artUri.toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        Icons.music_note,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  (item.artist?.isNotEmpty ?? false)
                                      ? item.artist!
                                      : (item.album ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          StreamBuilder<PlaybackState>(
                            stream: playerHandler.playbackState,
                            builder: (context, snapshot) {
                              final playing = snapshot.data?.playing ?? false;
                              return IconButton(
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: () {
                                  if (playing) {
                                    playerHandler.pause();
                                  } else {
                                    playerHandler.play();
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<PlaybackState>(
                      stream: playerHandler.playbackState,
                      builder: (context, snapshot) {
                        final state = snapshot.data;
                        final position = state?.position ?? Duration.zero;
                        final total = item.duration ?? Duration.zero;
                        final maxMs = total.inMilliseconds > 0
                            ? total.inMilliseconds.toDouble()
                            : position.inMilliseconds.toDouble() + 1;
                        final value = position.inMilliseconds
                            .clamp(0, maxMs.toInt())
                            .toDouble();
                        return LinearProgressIndicator(
                          value: value / maxMs,
                          minHeight: 2,
                          backgroundColor: scheme.surfaceContainer,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
