# 音乐盒子 musicTool

基于 Flutter 的多源在线音乐播放器（Android APK）。

应用本身**不内置任何音乐内容**，通过导入「音乐源」接入各大音乐平台的开放 API，实现聚合搜索与在线播放。

## 功能特性

- 多源聚合搜索：同时搜索多个音乐源，结果合并展示，来源一目了然
- 后台播放：锁屏/切后台继续播放，通知栏直接控制（audio_service）
- 收藏与最近播放：本地持久化保存
- 插件式音乐源：通过链接或粘贴 JSON 一键导入，支持启用/停用/删除
- 深色 Material 3 界面

## 快速开始

```bash
flutter pub get
flutter run
```

构建 APK：

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 音乐源说明

音乐源是一个 JSON 配置文件，描述某个音乐 API 的搜索接口与响应字段映射。
支持 GET / POST 两种搜索方式，支持嵌套字段（点号路径）与相对 URL。

完整示例见 [example_source.json](example_source.json)，核心结构如下：

```json
{
  "name": "示例音乐源",
  "version": "1.0.0",
  "baseUrl": "https://your-music-api.example.com",
  "headers": {},
  "search": {
    "path": "/search",
    "method": "GET",
    "keywordParam": "keywords",
    "params": {},
    "body": {}
  },
  "mapping": {
    "list": "result.songs",
    "id": "id",
    "title": "name",
    "artist": "artists",
    "album": "album.name",
    "cover": "picUrl",
    "url": "url",
    "duration": "duration",
    "durationUnit": "ms"
  }
}
```

- `mapping.list`：搜索响应中歌曲数组所在路径（点号分隔，留空表示整个响应）
- `mapping.durationUnit`：时长单位，`s`（秒）或 `ms`（毫秒）
- 歌曲的 `url` / `cover` 支持相对路径，会基于 `baseUrl` 自动解析
- `headers` 会同时用于搜索请求与播放请求

导入方式：打开应用 → 「我的」→ 右下角「导入音乐源」→ 粘贴 JSON 或填写 JSON 链接。

## 技术栈

- Flutter 3（Material 3）
- just_audio + audio_service + just_audio_background（后台播放）
- http（网络请求）
- shared_preferences（本地存储）

## 免责声明

本项目仅供学习交流使用。请仅导入你有权访问或作者明确开放的 API，遵守当地法律法规与相关平台服务条款，勿用于任何商业或侵权用途。本项目与任何音乐平台无关。
