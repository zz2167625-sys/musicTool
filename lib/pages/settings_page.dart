import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/music_source.dart';
import '../models/song.dart';
import '../services/auth.dart';
import '../services/local_music.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加音乐源：$result')),
      );
    }
  }

  Future<void> _importMp3() async {
    final count = await LocalMusicManager.instance.importMp3();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(count > 0 ? '已导入 $count 首本地音乐' : '未选择文件')),
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
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add),
        label: const Text('导入音乐源'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [SourceManager.instance, LocalMusicManager.instance]),
        builder: (context, _) {
          final sources = SourceManager.instance.sources;
          final localSongs = LocalMusicManager.instance.songs;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '音乐源',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${sources.length} 个',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (sources.isEmpty)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '暂无音乐源。点击右下角「导入音乐源」，'
                      '粘贴音乐源 JSON 文本或填写 JSON 文件链接。'
                      '音乐源格式示例见项目 README 与 example_source.json。',
                    ),
                  ),
                )
              else
                ...sources.map((source) => _SourceCard(source: source)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '本地音乐',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${localSongs.length} 首',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: ListTile(
                  leading: Icon(
                    Icons.library_music_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('导入 MP3'),
                  subtitle: const Text('从设备选择 MP3 文件，复制到应用内并离线播放'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importMp3,
                ),
              ),
              if (localSongs.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...localSongs.map(
                  (song) => _LocalSongTile(
                    song: song,
                    onTap: () async {
                      if (!await PlayUtils.playSongs(
                              localSongs, localSongs.indexOf(song)) &&
                          context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取播放地址')),
                        );
                      }
                    },
                    onDelete: () =>
                        LocalMusicManager.instance.removeSong(song),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '关于',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(
          Icons.cloud_outlined,
          color: source.enabled ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          source.name,
          style: TextStyle(
            color: source.enabled ? null : scheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          'v${source.version} · ${source.baseUrl}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
                if (value == 'delete') {
                  SourceManager.instance.removeSource(source.name);
                }
              },
              itemBuilder: (context) => const [
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
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SongTile(
        song: song,
        onTap: onTap,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: onDelete,
        ),
      ),
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
