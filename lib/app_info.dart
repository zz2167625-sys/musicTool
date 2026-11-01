/// 应用全局信息：名称、版本、更新检查地址。
///
/// 发版时同步修改 [version]（与 pubspec.yaml 的 version 保持一致），
/// 并将远端 update.json 中的 version 设为更高版本，App 启动后即会提示更新。
class AppInfo {
  AppInfo._();

  static const name = 'zephyr';
  static const version = '1.2.0';

  /// 远端更新信息地址，需返回如下 JSON：
  /// {"version": "1.2.1", "url": "https://...", "notes": "更新说明"}
  /// 发布新版时更新该文件即可，App 会据此判断并提示。
  static const updateUrl =
      'https://raw.githubusercontent.com/zz2167625-sys/musicTool/main/update.json';
}
