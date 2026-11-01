import 'package:shared_preferences/shared_preferences.dart';

/// 登录认证：全应用仅一个唯一账号，凭据集中在此处修改。
class Auth {
  Auth._();

  static const username = 'zest';
  static const password = '1235789z';

  static const _loggedInKey = 'auth_logged_in_v1';

  static bool verify(String user, String pass) =>
      user.trim() == username && pass == password;

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }
}
