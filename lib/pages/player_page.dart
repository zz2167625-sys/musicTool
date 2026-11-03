import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../models/song.dart';
import '../services/local_store.dart';
import '../services/mv_service.dart';
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
                    const Expanded(child: Center(child: Text('暂无播放内容'))),
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (item.artist?.isNotEmpty ?? false)
                                ? item.artist!
                                : (item.album ?? ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '来自 ${item.extras?['sourceName'] ?? '未知音源'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          _ProgressBar(item: item, format: _format),
                          const SizedBox(height: 8),
                          const _Controls(),
                          const SizedBox(height: 8),
                          _FavoriteButton(item: item),
                          const SizedBox(height: 16),
                          _MvSection(item: item),
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

class _MvSection extends StatefulWidget {
  const _MvSection({required this.item});

  final MediaItem item;

  @override
  State<_MvSection> createState() => _MvSectionState();
}

class _MvSectionState extends State<_MvSection> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _noMv = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _MvSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _disposeController();
      _resolve();
    }
  }

  @override
  void dispose() {
    // MV 播放中退出页面时恢复音乐播放，避免音乐停留在暂停状态
    if (_playing) {
      playerHandler.play();
    }
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _playing = false;
  }

  Future<void> _resolve() async {
    final keyword = '${widget.item.artist ?? ''} ${widget.item.title}'.trim();
    setState(() {
      _loading = true;
      _noMv = false;
    });
    final url = await MvService.resolveMv(keyword);
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _loading = false;
        _noMv = true;
      });
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _noMv = true;
      });
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    controller.addListener(() {
      if (controller.value.position >= controller.value.duration &&
          controller.value.duration > Duration.zero) {
        _stopMv();
      }
    });
    setState(() {
      _controller = controller;
      _loading = false;
    });
  }

  void _playMv() {
    final controller = _controller;
    if (controller == null) return;
    playerHandler.pause();
    controller.setVolume(1);
    controller.play();
    setState(() => _playing = true);
  }

  void _stopMv() {
    final controller = _controller;
    if (controller == null) return;
    controller.pause();
    playerHandler.play();
    setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (_loading) {
      child = const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_noMv) {
      child = SizedBox(
        height: 40,
        child: Center(
          child: Text(
            '暂无 MV',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    } else if (_controller != null) {
      child = Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller!),
                  if (!_playing)
                    InkWell(
                      onTap: _playMv,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 56,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  if (_playing)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          onPressed: _stopMv,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _playing ? 'MV 播放中（音乐已暂停）' : '点击播放 MV（音乐会暂停）',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    } else {
      child = const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
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
        final value = position.inMilliseconds
            .clamp(0, maxMs.toInt())
            .toDouble();
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
            StreamBuilder<bool>(
              stream: playerHandler.shuffleModeEnabledStream,
              builder: (context, snapshot) {
                final enabled = snapshot.data ?? false;
                return IconButton(
                  tooltip: enabled ? '随机播放：开' : '随机播放：关',
                  icon: const Icon(Icons.shuffle_rounded),
                  color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                  onPressed: playerHandler.toggleShuffle,
                );
              },
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: () => playerHandler.skipToPrevious(),
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: () => playerHandler.skipToNext(),
            ),
            StreamBuilder<LoopMode>(
              stream: playerHandler.loopModeStream,
              builder: (context, snapshot) {
                final mode = snapshot.data ?? LoopMode.off;
                return IconButton(
                  tooltip: switch (mode) {
                    LoopMode.off => '列表播完停止',
                    LoopMode.all => '列表循环',
                    LoopMode.one => '单曲循环',
                  },
                  icon: Icon(
                    mode == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                  ),
                  color: mode == LoopMode.off
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                  onPressed: playerHandler.cycleLoopMode,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
