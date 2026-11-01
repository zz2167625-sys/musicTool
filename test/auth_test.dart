import 'package:flutter_test/flutter_test.dart';
import 'package:my_tools/services/auth.dart';

void main() {
  group('Auth 登录认证', () {
    test('仅唯一账号可通过校验', () {
      expect(Auth.verify('zest', '1235789z'), isTrue);
      expect(Auth.verify(' zest ', '1235789z'), isTrue);
    });

    test('错误账号或密码被拒绝', () {
      expect(Auth.verify('zest', 'wrong'), isFalse);
      expect(Auth.verify('other', '1235789z'), isFalse);
      expect(Auth.verify('', ''), isFalse);
      expect(Auth.verify('zest', ''), isFalse);
    });
  });
}
