import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/music_api.dart';
import '../services/play_utils.dart';
import '../services/search_history.dart';
import '../services/source_manager.dart';
import '../widgets/song_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<Song> _all = [];
  SearchReport? _report;
  String? _filterSource;
  bool _loading = false;
  String _error = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistory.load();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _search([String? keyword]) async {
    final text = (keyword ?? _controller.text).trim();
    if (text.isEmpty || _loading) return;
    _controller.text = text;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = '';
      _all = [];
      _report = null;
      _filterSource = null;
    });
    final sources = SourceManager.instance.enabledSources;
    if (sources.isEmpty) {
      setState(() {
        _loading = false;
        _error = '还没有可用的音乐源，请先到「我的」页面添加或导入';
      });
      return;
    }
    final report = await MusicApi.searchDetailed(text, sources);
    final history = await SearchHistory.add(text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _report = report;
      _all = report.songs;
      _history = history;
      if (report.songs.isEmpty) {
        final failed = report.sources
            .where((s) => !s.ok)
            .map((s) => s.sourceName);
        _error = failed.isEmpty
            ? '没有搜到结果，换个关键词试试'
            : '所有音乐源都没有返回结果（${failed.join('、')}）';
      }
    });
  }

  List<Song> get _visible {
    final filter = _filterSource;
    if (filter == null) return _all;
    return _all.where((s) => s.sourceName == filter).toList();
  }

  int _countOf(String sourceName) =>
      _all.where((s) => s.sourceName == sourceName).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        centerTitle: false,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              tooltip: '清空搜索历史',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await SearchHistory.clear();
                if (mounted) setState(() => _history = []);
              },
            ),
          if (_all.isNotEmpty)
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => _play(0),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌手，同时搜索所有已启用音源',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _search,
                    ),
                  ],
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _all.isNotEmpty) _buildSourceBar(scheme),
          Expanded(child: _buildBody(scheme, visible)),
        ],
      ),
    );
  }

  Widget _buildSourceBar(ColorScheme scheme) {
    final reports = _report?.sources ?? const <SourceSearchReport>[];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: Text('全部 ${_all.length}'),
              selected: _filterSource == null,
              showCheckmark: false,
              onSelected: (_) => setState(() => _filterSource = null),
            ),
          ),
          ...reports.map((r) {
            final count = _countOf(r.sourceName);
            final hasResult = count > 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                avatar: !r.ok
                    ? Icon(Icons.error_outline, size: 16, color: scheme.error)
                    : null,
                label: Text(
                  hasResult ? '${r.sourceName} $count' : r.sourceName,
                ),
                selected: _filterSource == r.sourceName,
                showCheckmark: false,
                onSelected: hasResult
                    ? (_) => setState(() => _filterSource = r.sourceName)
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, List<Song> visible) {
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isNotEmpty) {
      if (_filterSource != null) {
        return ListView.builder(
          itemCount: visible.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '共 ${_all.length} 首 · ${_all.map((s) => s.sourceName).toSet().length} 个音源',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _filterSource = null),
                      child: const Text('查看全部'),
                    ),
                  ],
                ),
              );
            }
            final song = visible[i - 1];
            return SongTile(song: song, onTap: () => _play(i - 1));
          },
        );
      }
      // 按音乐源分组展示
      final reports = _report?.sources ?? const <SourceSearchReport>[];
      final groups = <(String, List<Song>)>[
        for (final r in reports)
          if (_countOf(r.sourceName) > 0)
            (
              r.sourceName,
              _all.where((s) => s.sourceName == r.sourceName).toList(),
            ),
      ];
      final children = <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '共 ${_all.length} 首 · ${groups.length} 个音源',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final (name, songs) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.album_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Text(
                  '${songs.length} 首',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ...songs.map(
            (song) => SongTile(
              song: song,
              onTap: () => _playSongs(songs, songs.indexOf(song)),
            ),
          ),
        ],
      ];
      return ListView(children: children);
    }
    return _buildIdle(scheme);
  }

  Widget _buildIdle(ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        children: [
          Icon(Icons.travel_explore, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '一次搜索，聚合所有已启用音源',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '在「我的」中添加更多音乐源，结果会自动合并去重',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '最近搜索',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _history
                  .map(
                    (h) => ActionChip(
                      avatar: const Icon(Icons.history, size: 16),
                      label: Text(h),
                      onPressed: () => _search(h),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _play(int index) => _playSongs(_visible, index);

  Future<void> _playSongs(List<Song> songs, int index) async {
    if (index < 0 || index >= songs.length) return;
    final ok = await PlayUtils.playSongs(songs, index);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法获取播放地址，请换一首或检查音源')));
    }
  }
}
