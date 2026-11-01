import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'pages/home_shell.dart';
import 'services/local_store.dart';
import 'services/player_handler.dart';
import 'services/source_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SourceManager.instance.load();
  await LocalStore.instance.load();
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
}

class MusicToolApp extends StatelessWidget {
  const MusicToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '音乐盒子',
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
