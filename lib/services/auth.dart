import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

enum AuthResult { success, invalidCredentials, tooManyAttempts, networkError, serverError }

/// 登录认证：全应用仅一个唯一账号。
///
/// 服务端校验：AppInfo.authUrl 配置后，凭据只存在服务端（APK 内无任何密码），
/// 登录时向服务端提交账号密码校验。
/// 本地兜底：authUrl 留空时使用构建期注入的 LOCAL_USER / LOCAL_PASS 做本地校验
/// （凭据在 APK 内，可被反编译；源码与仓库中不包含任何凭据）。
/// 构建示例：flutter build apk --release --dart-define=LOCAL_USER=... --dart-define=LOCAL_PASS=...
class Auth {
  Auth._();

  static const localUsername =
      String.fromEnvironment('LOCAL_USER', defaultValue: 'zest');
  static const localPassword = String.fromEnvironment('LOCAL_PASS');

  static const _loggedInKey = 'auth_logged_in_v1';

  static bool verifyLocal(String user, String pass) =>
      localPassword.isNotEmpty &&
      user.trim() == localUsername &&
      pass == localPassword;

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  static Future<AuthResult> login(String username, String password) async {
    if (AppInfo.authUrl.isEmpty) {
      if (!verifyLocal(username, password)) {
        return AuthResult.invalidCredentials;
      }
      await setLoggedIn(true);
      return AuthResult.success;
    }
    try {
      final resp = await http
          .post(
            Uri.parse(AppInfo.authUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 12));
      switch (resp.statusCode) {
        case 200:
          await setLoggedIn(true);
          return AuthResult.success;
        case 401:
          return AuthResult.invalidCredentials;
        case 429:
          return AuthResult.tooManyAttempts;
        default:
          return AuthResult.serverError;
      }
    } catch (_) {
      return AuthResult.networkError;
    }
  }
}
