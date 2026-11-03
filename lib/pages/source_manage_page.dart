import 'package:flutter/material.dart';

import '../models/music_source.dart';
import '../services/music_api.dart';
import '../services/source_manager.dart';

/// 音乐源管理页：从「我的」页点击「音乐源」进入。
class SourceManagePage extends StatefulWidget {
  const SourceManagePage({super.key});

  @override
  State<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends State<SourceManagePage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐源'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add),
        label: const Text('导入音乐源'),
      ),
      body: AnimatedBuilder(
        animation: SourceManager.instance,
        builder: (context, _) {
          final sources = SourceManager.instance.sources;
          if (sources.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '暂无音乐源。点击右下角「导入音乐源」，'
                  '粘贴音乐源 JSON 文本或填写 JSON 文件链接。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children:
                sources.map((source) => _SourceTile(source: source)).toList(),
          );
        },
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

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
