import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/local_store.dart';
import '../services/player_handler.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surfaceContainerHighest, scheme.surface],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<MediaItem?>(
            stream: playerHandler.mediaItem,
            builder: (context, snapshot) {
              final item = snapshot.data;
              if (item == null) {
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Expanded(
                      child: Center(child: Text('暂无播放内容')),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Cover(item: item),
                          const SizedBox(height: 32),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (item.artist?.isNotEmpty ?? false)
                                ? item.artist!
                                : (item.album ?? ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 32),
                          _ProgressBar(item: item, format: _format),
                          const SizedBox(height: 16),
                          const _Controls(),
                          const SizedBox(height: 8),
                          _FavoriteButton(item: item),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalStore.instance,
      builder: (context, _) {
        final song = Song.fromMediaItem(item);
        final isFav = LocalStore.instance.isFavorite(song);
        return IconButton(
          iconSize: 32,
          icon: Icon(isFav ? Icons.favorite : Icons.favorite_outline),
          color: isFav ? Theme.of(context).colorScheme.primary : null,
          onPressed: () => LocalStore.instance.toggleFavorite(song),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerHigh,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: item.artUri == null
          ? Icon(Icons.music_note, size: 96, color: scheme.onSurfaceVariant)
          : Image.network(
              item.artUri.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.music_note,
                size: 96,
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.item, required this.format});

  final MediaItem item;
  final String Function(Duration) format;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: playerHandler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final position = state?.position ?? Duration.zero;
        final total = item.duration ?? Duration.zero;
        final maxMs = total.inMilliseconds > 0
            ? total.inMilliseconds.toDouble()
            : position.inMilliseconds.toDouble() + 1;
        final value =
            position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
        return Column(
          children: [
            Slider(
              value: value,
              max: maxMs,
              onChanged: (v) {
                playerHandler.seek(Duration(milliseconds: v.round()));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    format(position),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    total.inMilliseconds > 0 ? format(total) : '--:--',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<PlaybackState>(
      stream: playerHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: () => playerHandler.skipToPrevious(),
            ),
            const SizedBox(width: 24),
            IconButton(
              iconSize: 72,
              icon: Icon(
                playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
              ),
              color: scheme.primary,
              onPressed: () {
                if (playing) {
                  playerHandler.pause();
                } else {
                  playerHandler.play();
                }
              },
            ),
            const SizedBox(width: 24),
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: () => playerHandler.skipToNext(),
            ),
          ],
        );
      },
    );
  }
}
