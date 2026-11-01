import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/update_checker.dart';

/// 弹出「发现新版本」对话框，并提供复制下载链接。
Future<void> showUpdateAvailable(
    BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v${AppInfo.version}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.notes),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后再说'),
        ),
        if (info.url.isNotEmpty)
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: info.url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('下载链接已复制到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制下载链接'),
          ),
      ],
    ),
  );
}

/// 手动检查更新：有新版本弹窗，否则提示已是最新。
Future<void> checkForUpdates(BuildContext context) async {
  final info = await UpdateChecker.check();
  if (!context.mounted) return;
  if (info == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前已是最新版本')),
    );
    return;
  }
  await showUpdateAvailable(context, info);
}
