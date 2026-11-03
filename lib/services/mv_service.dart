import 'bili_api.dart';

/// MV 检索服务：B 站公开接口搜索歌曲 MV 并解析出可直接播放的视频地址。
class MvService {
  MvService._();

  /// 根据「歌手 歌名」搜索 MV，返回可直接播放的视频地址；失败返回 null。
  static Future<String?> resolveMv(String keyword) => BiliApi.resolveMv(keyword);
}
