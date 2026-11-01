import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app_info.dart';
import 'pages/home_shell.dart';
import 'services/local_music.dart';
import 'services/local_store.dart';
import 'services/player_handler.dart';
import 'services/source_manager.dart';
import 'services/update_checker.dart';
import 'widgets/update_dialog.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SourceManager.instance.load();
  await LocalStore.instance.load();
  await LocalMusicManager.instance.load();
  await AudioService.init(
    builder: () => playerHandler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.zephyr.my_tools.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const MusicToolApp());
  unawaited(_autoCheckUpdate());
}

Future<void> _autoCheckUpdate() async {
  await Future.delayed(const Duration(seconds: 3));
  final info = await UpdateChecker.check();
  if (info == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    showUpdateAvailable(navigator.context, info);
  });
}

class MusicToolApp extends StatelessWidget {
  const MusicToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomeShell(),
    );
  }
}
