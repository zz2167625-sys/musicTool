import 'package:flutter_test/flutter_test.dart';
import 'package:my_tools/services/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Auth 登录认证', () {
    test('登录状态持久化', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await Auth.isLoggedIn(), isFalse);
      await Auth.setLoggedIn(true);
      expect(await Auth.isLoggedIn(), isTrue);
      await Auth.setLoggedIn(false);
      expect(await Auth.isLoggedIn(), isFalse);
    });

    test('本地兜底模式下错误凭据被拒绝', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await Auth.login('any', 'wrong'), AuthResult.invalidCredentials);
      expect(await Auth.isLoggedIn(), isFalse);
    });

    test('本地校验拒绝空密码（未注入 LOCAL_PASS 时不可登录）', () {
      expect(Auth.verifyLocal('zest', ''), isFalse);
    });
  });
}
