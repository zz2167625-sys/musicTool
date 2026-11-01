import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';

class UpdateInfo {
  final String version;
  final String url;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
  });
}

class UpdateChecker {
  static const _timeout = Duration(seconds: 10);

  /// 检查远端更新。有新版本返回 [UpdateInfo]，否则返回 null。
  /// 网络错误、地址未配置、格式非法一律按「无更新」处理，不打扰用户。
  static Future<UpdateInfo?> check() async {
    if (AppInfo.updateUrl.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse(AppInfo.updateUrl))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      if (json is! Map) return null;
      final remoteVersion = json['version']?.toString().trim() ?? '';
      if (remoteVersion.isEmpty) return null;
      if (!isNewer(remoteVersion, AppInfo.version)) return null;
      return UpdateInfo(
        version: remoteVersion,
        url: json['url']?.toString().trim() ?? '',
        notes: json['notes']?.toString().trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 按数字段比较版本号，如 1.2.0 < 1.10.1。
  static bool isNewer(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parse(String version) {
    final nums = <int>[];
    for (final part in version.split(RegExp(r'[^0-9]+'))) {
      if (part.isEmpty) continue;
      nums.add(int.tryParse(part) ?? 0);
    }
    return nums;
  }
}
