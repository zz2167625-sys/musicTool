import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/song.dart';
import '../services/auth.dart';
import '../services/local_music.dart';
import '../services/play_utils.dart';
import '../services/source_manager.dart';
import '../widgets/song_tile.dart';
import '../widgets/update_dialog.dart';
import 'login_page.dart';
import 'source_manage_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
      appBar: AppBar(title: const Text('我的'), centerTitle: false),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.cloud_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('音乐源'),
                subtitle: Text('${sources.length} 个 · 点击管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourceManagePage()),
                ),
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
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text(AppInfo.name),
                subtitle: Text('版本 ${AppInfo.version}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('检查更新'),
                subtitle: const Text('发现新版本时提示下载'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => checkForUpdates(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('免责声明'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDisclaimer,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
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
