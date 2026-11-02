/// 应用全局信息：名称、版本、更新检查地址。
///
/// 发版时同步修改 [version]（与 pubspec.yaml 的 version 保持一致），
/// 并将远端 update.json 中的 version 设为更高版本，App 启动后即会提示更新。
class AppInfo {
  AppInfo._();

  static const name = 'zephyr';
  static const version = '1.7.0';

  /// 远端更新信息地址（按顺序尝试，任一可达即可；前两个在国内网络通常可直连）：
  /// {"version": "1.6.2", "url": "https://...", "notes": "更新说明"}
  /// 发布新版时更新仓库根目录 update.json 即可，App 会据此判断并提示。
  static const updateUrls = [
    'https://zephyr.zz2167625.workers.dev/update.json',
    'https://cdn.jsdelivr.net/gh/zz2167625-sys/musicTool@main/update.json',
    'https://raw.githubusercontent.com/zz2167625-sys/musicTool/main/update.json',
  ];

  /// 登录校验服务端地址（POST JSON {username, password}，200 表示通过）。
  /// 凭据只存在服务端 Worker 机密中，APK 与仓库内均不含任何密码。
  static const authUrl = 'https://zephyr.zz2167625.workers.dev/auth';
}
