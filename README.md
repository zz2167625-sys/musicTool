# zephyr

基于 Flutter 的多源在线音乐播放器（Android APK），原「音乐盒子 musicTool」。

应用本身**不内置任何音乐内容**，通过导入「音乐源」接入各大音乐平台的开放 API，实现聚合搜索与在线播放。

## 功能特性

- 多源聚合搜索：同时搜索多个音乐源，结果合并展示，来源一目了然
- 本地音乐导入：从设备选择 MP3 文件，复制到应用内，离线播放（「我的」→「本地音乐」）
- 后台播放：锁屏/切后台继续播放，通知栏直接控制（audio_service）
- 收藏与最近播放：本地持久化保存
- 插件式音乐源：通过链接或粘贴 JSON 一键导入，支持启用/停用/删除
- 应用更新提示：启动时自动检查新版本，也可在「我的」→「检查更新」手动检查
- 配套抓取工具：`tools/music_source_scraper.py` 从 GitHub/Gitee/grep.app 搜索可用的音乐源 JSON
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

## 本地音乐（MP3 导入）

打开应用 → 「我的」→ 「本地音乐」→ 点击「导入 MP3」，从设备选择 MP3 文件。
文件会被复制到应用内部存储（`local_music/` 目录），删除应用数据前不会丢失，
可离线播放、加入收藏、出现在最近播放中。

## 音乐源抓取工具

项目根目录 `tools/music_source_scraper.py`（纯 Python 标准库，Python 3.8+）
从 GitHub / Gitee 公开仓库与 grep.app 代码搜索中查找并校验音乐源 JSON，
并且**每次运行都会生成内置模板**（iTunes、Deezer 公开 API，免密钥、可在线试听），
保证开箱即有可用音乐源：

```bash
python tools/music_source_scraper.py                # 搜索并保存到 tools/sources/
python tools/music_source_scraper.py --repo owner/name   # 扫描指定仓库
python tools/music_source_scraper.py --url https://x/s.json  # 抓取单个文件
python tools/music_source_scraper.py --test         # 对每个源做真实搜索测试
python tools/music_source_scraper.py --print        # 打印 JSON，可直接粘贴到 App
python tools/music_source_scraper.py --serve 8000   # 启动本地 HTTP 服务
python tools/music_source_scraper.py --no-templates # 不生成内置模板
```

手机与电脑在同一局域网时，运行 `--serve` 后按提示用
「我的 → 导入音乐源 → 从链接导入」填写 `http://<电脑IP>:8000/<文件>.json` 即可。
抓取到的源保存在 `tools/sources/` 目录，可自行审查后使用。

## 应用更新提示

App 启动 3 秒后自动检查远端 `update.json`，发现新版本时弹窗提示（含更新说明与下载链接复制）；也可在「我的」→「检查更新」手动检查。

- 版本与地址常量见 [lib/app_info.dart](lib/app_info.dart)：`version` 与 pubspec.yaml 保持一致，`updateUrl` 指向你托管的 update.json
- 仓库根目录 [update.json](update.json) 为模板：每次发版时把 `version` 改为大于 App 内版本的新版本号，`url` 填下载地址，`notes` 写更新说明
- 建议把仓库推到 GitHub 后使用 raw 链接，例如
  `https://raw.githubusercontent.com/<用户名>/<仓库名>/main/update.json`

## 应用图标

`tools/make_icons.py` 从一张「图标居中、黑色背景」的源图生成全套 Android 图标
（去黑边、透明化、各密度 mipmap + 自适应图标）：

```bash
pip install pillow
python tools/make_icons.py <源图片.jpg>
# 产物：tools/icon_master.png（1024 透明母版）与 android res 下各 mipmap
```

生成后重新 `flutter build apk --release` 即可生效。

## 技术栈

- Flutter 3（Material 3）
- just_audio + audio_service + just_audio_background（后台播放）
- file_picker + path_provider（本地 MP3 导入）
- http（网络请求）
- shared_preferences（本地存储）

## 免责声明

本项目仅供学习交流使用。请仅导入你有权访问或作者明确开放的 API 与文件，遵守当地法律法规与相关平台服务条款，勿用于任何商业或侵权用途。抓取工具仅聚合公开仓库中由第三方分享的配置文件，请自行审查后使用。本项目与任何音乐平台无关。
