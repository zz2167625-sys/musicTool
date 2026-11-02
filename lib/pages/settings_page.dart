import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/music_source.dart';
import '../models/song.dart';
import '../services/auth.dart';
import '../services/local_music.dart';
import '../services/music_api.dart';
import '../services/play_utils.dart';
import '../services/source_manager.dart';
import '../widgets/song_tile.dart';
import 'login_page.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _showImportDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportSourceDialog(),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已添加音乐源：$result')));
    }
  }

  Future<void> _importMp3() async {
    final count = await LocalMusicManager.instance.importMp3();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(count > 0 ? '已导入 $count 首本地音乐' : '未选择文件')),
    );
  }

  Future<void> _showBundledSources() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _BundledSourcesDialog(),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码才能使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Auth.setLoggedIn(false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showDisclaimer() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('免责声明'),
        content: const Text(
          '本应用仅提供音乐源接入框架与播放功能，不内置任何音乐内容。'
          '请仅导入你有权访问或作者明确开放的 API。'
          '请遵守当地法律法规，勿将本应用用于任何商业或侵权用途。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add),
        label: const Text('导入音乐源'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          SourceManager.instance,
          LocalMusicManager.instance,
        ]),
        builder: (context, _) {
          final sources = SourceManager.instance.sources;
          final localSongs = LocalMusicManager.instance.songs;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ExpansionTile(
                initiallyExpanded: true,
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '音乐源',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${sources.length} 个 · 点击展开或收起',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  if (sources.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '暂无音乐源。点击右下角「导入音乐源」，'
                        '粘贴音乐源 JSON 文本或填写 JSON 文件链接。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ...sources.map((source) => _SourceCard(source: source)),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.library_add_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('内置音乐源'),
                subtitle: const Text('酷我 / 酷狗 / 网易云 / Audius / ccMixter，一键补充'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showBundledSources,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '本地音乐',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${localSongs.length} 首',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.library_music_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('导入 MP3'),
                subtitle: const Text('从设备选择 MP3 文件，复制到应用内并离线播放'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _importMp3,
              ),
              if (localSongs.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...localSongs.map(
                  (song) => _LocalSongTile(
                    song: song,
                    onTap: () async {
                      if (!await PlayUtils.playSongs(
                            localSongs,
                            localSongs.indexOf(song),
                          ) &&
                          context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取播放地址')),
                        );
                      }
                    },
                    onDelete: () => LocalMusicManager.instance.removeSong(song),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '关于',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(AppInfo.name),
                subtitle: Text('版本 ${AppInfo.version}'),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('检查更新'),
                subtitle: const Text('发现新版本时提示下载'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => checkForUpdates(context),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('免责声明'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDisclaimer,
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                subtitle: const Text('退出后需重新输入账号密码'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _logout,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final MusicSource source;

  Future<void> _test(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在测试「${source.name}」…')));
    final report = await MusicApi.testSource(source);
    if (!context.mounted) return;
    if (report.ok) {
      SourceManager.instance.resetFailures(source.name);
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          report.ok
              ? '「${source.name}」可用，返回 ${report.songs.length} 首'
              : '「${source.name}」不可用：${report.error ?? '未知错误'}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failing =
        source.enabled && SourceManager.instance.failStreakOf(source.name) > 0;
    final status = !source.enabled
        ? '已停用'
        : failing
        ? '最近搜索异常'
        : '';
    final detail = [
      if (status.isNotEmpty) status,
      if (source.notes.isNotEmpty) source.notes,
      source.baseUrl,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        !source.enabled
            ? Icons.cloud_off_outlined
            : failing
            ? Icons.cloud_sync_outlined
            : Icons.cloud_outlined,
        color: source.enabled
            ? (failing ? scheme.error : scheme.primary)
            : scheme.onSurfaceVariant,
      ),
      title: Text(
        source.name,
        style: TextStyle(
          color: source.enabled ? null : scheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enabled,
            onChanged: (v) =>
                SourceManager.instance.toggleSource(source.name, v),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'test') {
                _test(context);
              } else if (value == 'delete') {
                SourceManager.instance.removeSource(source.name);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'test',
                child: Row(
                  children: [
                    Icon(Icons.network_check),
                    SizedBox(width: 8),
                    Text('测试连接'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 8),
                    Text('删除'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocalSongTile extends StatelessWidget {
  const _LocalSongTile({
    required this.song,
    required this.onTap,
    required this.onDelete,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SongTile(
      song: song,
      onTap: onTap,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: onDelete,
      ),
    );
  }
}

class _BundledSourcesDialog extends StatefulWidget {
  const _BundledSourcesDialog();

  @override
  State<_BundledSourcesDialog> createState() => _BundledSourcesDialogState();
}

class _BundledSourcesDialogState extends State<_BundledSourcesDialog> {
  List<MusicSource>? _sources;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SourceManager.instance.loadBundledSources();
    if (!mounted) return;
    setState(() => _sources = list);
  }

  Future<void> _add(MusicSource source) async {
    await SourceManager.instance.addSource(source);
    if (mounted) setState(() {});
  }

  Future<void> _addAll() async {
    final missing = (_sources ?? const <MusicSource>[])
        .where((s) => SourceManager.instance.byName(s.name) == null)
        .toList();
    for (final source in missing) {
      await SourceManager.instance.addSource(source);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sources = _sources;
    final missing =
        sources
            ?.where((s) => SourceManager.instance.byName(s.name) == null)
            .length ??
        0;
    return AlertDialog(
      title: const Text('内置音乐源'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          maxHeight: 420,
          minHeight: 120,
        ),
        child: sources == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    '这些音源随 App 打包，可直接添加。已添加的不会重复出现。',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sources.map((source) {
                    final added =
                        SourceManager.instance.byName(source.name) != null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.album_outlined,
                        color: added ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      title: Text(source.name),
                      subtitle: Text(
                        [
                          if (source.notes.isNotEmpty) source.notes,
                          source.baseUrl,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: added
                          ? Text(
                              '已添加',
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 12,
                              ),
                            )
                          : TextButton(
                              onPressed: () => _add(source),
                              child: const Text('添加'),
                            ),
                    );
                  }),
                ],
              ),
      ),
      actions: [
        if (missing > 0)
          TextButton(onPressed: _addAll, child: Text('全部添加 ($missing)')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ImportSourceDialog extends StatefulWidget {
  const _ImportSourceDialog();

  @override
  State<_ImportSourceDialog> createState() => _ImportSourceDialogState();
}

class _ImportSourceDialogState extends State<_ImportSourceDialog> {
  final _urlController = TextEditingController();
  final _jsonController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = await SourceManager.fetchSource(url);
      await SourceManager.instance.addSource(source);
      if (mounted) Navigator.pop(context, source.name);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '导入失败：$e';
      });
    }
  }

  Future<void> _importFromText() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final source = SourceManager.parseSourceJson(text);
    if (source == null) {
      setState(() {
        _busy = false;
        _error = 'JSON 解析失败，请检查格式';
      });
      return;
    }
    await SourceManager.instance.addSource(source);
    if (mounted) Navigator.pop(context, source.name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入音乐源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '音乐源 JSON 链接',
                hintText: 'https://example.com/source.json',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _importFromUrl,
                icon: const Icon(Icons.link),
                label: const Text('从链接导入'),
              ),
            ),
            const Divider(),
            TextField(
              controller: _jsonController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '或粘贴 JSON 文本',
                hintText: '{"name": "...", "baseUrl": "...", ...}',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _importFromText,
                icon: const Icon(Icons.code),
                label: const Text('从文本导入'),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
