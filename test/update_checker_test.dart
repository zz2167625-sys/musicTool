import 'package:flutter_test/flutter_test.dart';

import 'package:my_tools/services/update_checker.dart';

void main() {
  test('版本号比较', () {
    expect(UpdateChecker.isNewer('1.2.1', '1.2.0'), isTrue);
    expect(UpdateChecker.isNewer('1.10.0', '1.9.9'), isTrue);
    expect(UpdateChecker.isNewer('2.0.0', '1.9.9'), isTrue);
    expect(UpdateChecker.isNewer('v1.3.0', '1.2.9'), isTrue);
    expect(UpdateChecker.isNewer('1.2.0', '1.2.0'), isFalse);
    expect(UpdateChecker.isNewer('1.2.0', '1.2.1'), isFalse);
    expect(UpdateChecker.isNewer('1.2', '1.2.0'), isFalse);
    expect(UpdateChecker.isNewer('1.2.0', '1.2'), isFalse);
  });
}
