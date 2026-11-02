# zephyr

基于 Flutter 的多源在线音乐播放器（Android APK），原「音乐盒子 musicTool」。

应用本身**不内置任何音乐内容**，通过导入「音乐源」接入各大音乐平台的开放 API，实现聚合搜索与在线播放。

## 2.3.0 更新

- 新增「网易云音乐」「ccMixter 开放音乐」音源；Audius 过滤不可播放曲目
- 搜索页逐源统计与筛选、搜索历史、播放全部
- 新增「内置音乐源」目录，升级后可一键补充新增音源
- 修复混源播放时请求头错用的问题；播放页新增随机/循环模式
- 网易云音源支持搜索阶段可播放性校验，避免将死链加入队列

## 功能特性

- 多源聚合搜索：同时搜索多个音乐源，结果合并展示，来源一目了然
- 逐源搜索报告：显示每个音源命中的数量与异常状态，可按音源筛选结果
- 搜索历史：本地保存最近 10 条关键词，点一下即可重新搜索
- 登录保护：启动需登录，全应用仅一个唯一账号（凭据定义在 lib/services/auth.dart），「我的」→「退出登录」
- 本地音乐导入：从设备选择 MP3 文件，复制到应用内，离线播放（「我的」→「本地音乐」）
- 后台播放：锁屏/切后台继续播放，通知栏直接控制（audio_service）
- 随机播放与循环模式：播放页可切换随机、列表循环、单曲循环
- 收藏与最近播放：本地持久化保存，支持一键播放全部/随机播放
- 插件式音乐源：通过链接或粘贴 JSON 一键导入，支持启用/停用/测试/删除
- 内置音源目录：随 App 打包的音源可一键补充，升级后也能拿到新增音源
- 可播放性校验：对版权受限平台先探测音频地址，避免把死链加入播放队列
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
- `mapping.urlTemplate`：可选，播放地址模板，如 `https://x.com/song?id={id}.mp3`，
  `{字段}` 会按条目字段解析（适合播放地址可由 ID 直接拼出的 API）
- `mapping.urlResolve`：可选，播放地址需二次请求时使用，结构如下；
  请求路径/body 中的 `{字段}` 同样按歌曲字段解析，响应中取 `urlPath` 指向的地址
  ```json
  "urlResolve": {
    "path": "/song/url/v1?id={id}&level=standard",
    "method": "GET",
    "urlPath": "data.0.url",
    "body": {}
  }
  ```
- `mapping.filter`：可选，条目过滤条件，例如只保留可流式播放的曲目
  ```json
  "filter": { "is_streamable": true }
  ```
- `mapping.checkPlayable`：可选，解析出播放地址后做一次音频探测，返回网页而不是
  音频的链接会被剔除（适合网易云这类版权受限平台）
- `mapping.checkPlayableOnSearch`：可选，搜索时就过滤掉不可播条目，只返回真正
  能播放的结果（会增加少量搜索耗时）
- `notes`：可选，音源说明，会显示在「我的 → 音乐源」列表中
- 三种地址来源优先级：`url` 字段 → `urlTemplate` → `urlResolve`（播放时异步解析，结果缓存 10 分钟）
- `headers` 会同时用于搜索请求与播放请求

导入方式：打开应用 → 「我的」→ 右下角「导入音乐源」→ 粘贴 JSON 或填写 JSON 链接。

## 完整歌曲播放

App 内置五个音源，开箱即用：

- 「酷我 完整歌曲」：免登录、国内直连，主流曲目覆盖好，解析成功率高
- 「酷狗 完整歌曲」：免登录，部分热门曲目需要酷狗会员，未授权曲目会解析失败
- 「网易云音乐」：直连公开搜索接口；无版权/VIP 曲目会在搜索阶段自动跳过，
  只展示能真正播放的结果
- 「Audius 音乐」：海外开放音乐平台，完整歌曲、免密钥（需可访问外网）
- 「ccMixter 开放音乐」：知识共享（CC）授权的完整歌曲，英文关键词命中率更高

「我的」→「内置音乐源」可查看并一键补充所有内置音源；升级 App 后新增的音源
也会出现在这里。

另有扩展方式：

### Jamendo（合法 CC 音乐，一步到位）

[Jamendo](https://developer.jamendo.com) 免费注册后创建应用获取 `client_id`，
把 [tools/templates/jamendo_完整歌曲.json](tools/templates/jamendo_完整歌曲.json)
中的 `YOUR_CLIENT_ID` 替换后导入。曲库为独立音乐人作品，全部为完整歌曲。

免责声明：请仅导入你有权访问的 API，遵守各平台服务条款与当地法律法规。

## 本地音乐（MP3 导入）

打开应用 → 「我的」→ 「本地音乐」→ 点击「导入 MP3」，从设备选择 MP3 文件。
文件会被复制到应用内部存储（`local_music/` 目录），删除应用数据前不会丢失，
可离线播放、加入收藏、出现在最近播放中。

## 音乐源抓取工具

项目根目录 `tools/music_source_scraper.py`（纯 Python 标准库，Python 3.8+）
从 GitHub / Gitee 公开仓库与 grep.app 代码搜索中查找并校验音乐源 JSON，
并且**每次运行都会生成内置模板**（酷我、酷狗、网易云、Audius、ccMixter 公开
API，免密钥），保证开箱即有可用音乐源：

```bash
python tools/music_source_scraper.py                # 搜索并保存到 tools/sources/
python tools/music_source_scraper.py --repo owner/name   # 扫描指定仓库
python tools/music_source_scraper.py --url https://x/s.json  # 抓取单个文件
python tools/music_source_scraper.py --test         # 对每个源做真实搜索测试
python tools/music_source_scraper.py --print        # 打印 JSON，可直接粘贴到 App
python tools/music_source_scraper.py --serve 8000   # 启动本地 HTTP 服务
python tools/music_source_scraper.py --no-templates # 不生成内置模板
python tools/music_source_scraper.py --search 周杰伦      # 用所有源搜歌，结果存 scraped_songs.json
python tools/music_source_scraper.py --search 周杰伦 --download  # 同时下载音频到 scraped_files/
python tools/music_source_scraper.py --app-assets   # 把当前音乐源同步到 App 内置资源 assets/sources/
```

手机与电脑在同一局域网时，运行 `--serve` 后按提示用
「我的 → 导入音乐源 → 从链接导入」填写 `http://<电脑IP>:8000/<文件>.json` 即可。
抓取到的源保存在 `tools/sources/` 目录，可自行审查后使用。
运行 `--app-assets` 后重新构建 App，内置音乐源即更新（开箱即可搜索，无需导入）。

## 应用更新提示

App 启动 3 秒后自动检查远端 `update.json`，发现新版本时弹窗提示（含更新说明与下载链接复制）；也可在「我的」→「检查更新」手动检查。

- 版本与地址常量见 [lib/app_info.dart](lib/app_info.dart)：`version` 与 pubspec.yaml 保持一致，`updateUrl` 指向仓库 raw 链接
- 仓库根目录 [update.json](update.json) 为模板：每次发版时把 `version` 改为大于 App 内版本的新版本号，`url` 填下载地址，`notes` 写更新说明
- 仓库公开，raw 链接可直接匿名访问：
  `https://raw.githubusercontent.com/<用户名>/<仓库名>/main/update.json`
- 下载地址 `https://github.com/zz2167625-sys/musicTool/releases/latest` 指向最新 Release 页面

## 登录

App 启动后需登录，全应用仅一个唯一账号。支持两种校验模式：

- **服务端校验（默认已启用）**：[lib/app_info.dart](lib/app_info.dart) 的
  `authUrl` 已指向部署好的 Cloudflare Worker（POST JSON `{username, password}`，
  200 表示通过，401 拒绝，429 限流）。凭据只存在 Worker 机密（`LOGIN_USER` /
  `LOGIN_PASS`）中，APK 与仓库内不含任何密码。
  接口实现见 `auth_site/cloudflare_worker.js`（含每 IP 限流）与
  `auth_site/functions/index.ts`（Deno Edge Function 版）。
- **本地兜底**：`authUrl` 留空时使用构建期注入的 `LOCAL_USER` / `LOCAL_PASS`
  做本地校验（凭据在 APK 内，可被反编译，仅作临时方案）。凭据不进入源码与仓库，
  构建时传入：
  ```bash
  flutter build apk --release \
    --dart-define=LOCAL_USER=你的账号 --dart-define=LOCAL_PASS=你的密码
  ```
  未注入 `LOCAL_PASS` 时本地模式拒绝一切登录。

登录状态保存在本机，下次启动自动登录；可在「我的」→「退出登录」注销。

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
