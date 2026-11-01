/// 应用全局信息：名称、版本、更新检查地址。
///
/// 发版时同步修改 [version]（与 pubspec.yaml 的 version 保持一致），
/// 并将远端 update.json 中的 version 设为更高版本，App 启动后即会提示更新。
class AppInfo {
  AppInfo._();

  static const name = 'zephyr';
  static const version = '1.3.0';

  /// 远端更新信息地址（公开 Gist，仓库私有化后仍可匿名访问）：
  /// {"version": "1.3.1", "url": "https://...", "notes": "更新说明"}
  /// 发布新版时更新 Gist 中的 update.json 即可，App 会据此判断并提示。
  static const updateUrl =
      'https://gist.githubusercontent.com/zz2167625-sys/2bd9e8f419b263f4c3c0d5009854c0f0/raw/update.json';
}
