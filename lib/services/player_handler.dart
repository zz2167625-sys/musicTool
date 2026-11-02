import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'source_manager.dart';

final PlayerHandler playerHandler = PlayerHandler();

class PlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  int? _lastIndex;

  PlayerHandler() {
    _loadEmptyPlaylist();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    _listenForAutoAdvance();
  }

  Stream<bool> get shuffleModeEnabledStream => _player.shuffleModeEnabledStream;

  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  bool get shuffleModeEnabled => _player.shuffleModeEnabled;

  Future<void> toggleShuffle() =>
      _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);

  /// 循环模式：关闭 → 列表循环 → 单曲循环 → 关闭。
  Future<void> cycleLoopMode() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
  }

  /// 播放完一首后自动切换列表下一首（just_audio 通常自动处理，这里兜底）。
  void _listenForAutoAdvance() {
    _player.processingStateStream.listen((state) {
      if (state != ProcessingState.completed) return;
      final index = _player.currentIndex;
      final length = _player.sequence.length;
      if (_lastIndex == null || length <= 1) return;
      if (_player.loopMode != LoopMode.one &&
          index == _lastIndex &&
          _lastIndex! < length - 1) {
        _player.seekToNext();
      }
    });
  }

  Future<void> _loadEmptyPlaylist() async {
    try {
      await _player.setAudioSources(const []);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 3],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[event.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: event.currentIndex,
        ),
      );
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      final newQueue = queue.value;
      if (index == null || newQueue.isEmpty || index >= newQueue.length) return;
      final oldMediaItem = newQueue[index];
      final newMediaItem = oldMediaItem.copyWith(duration: duration);
      newQueue[index] = newMediaItem;
      queue.add(newQueue);
      mediaItem.add(newMediaItem);
    });
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      _lastIndex = index;
      final playlist = queue.value;
      if (index == null || playlist.isEmpty || index >= playlist.length) {
        return;
      }
      mediaItem.add(playlist[index]);
    });
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((sequenceState) {
      final sequence = sequenceState.effectiveSequence;
      if (sequence.isEmpty) return;
      final items = sequence.map((source) => source.tag as MediaItem);
      queue.add(items.toList());
    });
  }

  /// 播放队列。每个音源可能有自己的请求头（Referer/Cookie 等），
  /// 这里按歌曲所属音源逐条设置，避免混源队列复用错请求头。
  Future<void> playQueue(List<Song> songs, int startIndex) async {
    if (songs.isEmpty) return;
    final items = songs.map((s) => s.toMediaItem()).toList();
    queue.add(items);
    final sources = songs.map((s) {
      final source = SourceManager.instance.byName(s.sourceName);
      final headers = source == null || source.headers.isEmpty
          ? null
          : Map<String, String>.from(source.headers);
      return AudioSource.uri(
        Uri.parse(s.url),
        tag: s.toMediaItem(),
        headers: headers,
      );
    }).toList();
    await _player.setAudioSources(
      sources,
      initialIndex: startIndex,
      preload: true,
    );
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
