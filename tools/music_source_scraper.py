#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""music_source_scraper.py —— 音乐源抓取工具（musicTool 音乐盒子配套）

从 GitHub / Gitee 公开仓库中搜索、校验「音乐源」JSON 配置文件，保存到
sources/ 目录，供「音乐盒子」App 通过链接或粘贴 JSON 的方式导入。

用法：
  python music_source_scraper.py                        # 搜索并保存所有可用音乐源
  python music_source_scraper.py --search 周杰伦        # 用全部音乐源搜歌，结果存 scraped_songs.json
  python music_source_scraper.py --search 周杰伦 --download  # 同时下载试听文件到 scraped_files/
  python music_source_scraper.py --app-assets           # 把当前音乐源同步到 App 内置资源目录
  python music_source_scraper.py --repo owner/name      # 扫描指定仓库（GitHub/Gitee）
  python music_source_scraper.py --url https://x/s.json # 抓取并校验单个文件
  python music_source_scraper.py --test                 # 搜索后对每个源做真实搜索测试
  python music_source_scraper.py --print                # 同时打印每个源的 JSON（可直接粘贴到 App）
  python music_source_scraper.py --serve 8000           # 启动本地 HTTP 服务，手机在同一局域网
                                                        # 用「从链接导入」导入 http://<电脑IP>:8000/<文件>.json
  python music_source_scraper.py --no-templates         # 不生成内置公开 API 模板
  python music_source_scraper.py --token GITHUB_TOKEN   # 提供 GitHub Token 提高限流额度

每次运行都会把「内置模板」（酷我 / 酷狗 / Audius 公开 API，免密钥、完整歌曲）
写入 sources/ 目录，保证开箱即有可用音乐源；其余来源通过 GitHub / Gitee 仓库搜索
与 grep.app 代码搜索补充。

仅依赖 Python 3.8+ 标准库，无需 pip install。

免责声明：本工具仅聚合公开仓库中由第三方分享的 API 配置文件，不内置任何音乐
内容。请仅导入你有权访问或作者明确开放的 API，遵守当地法律法规与相关平台服务
条款。本项目与任何音乐平台无关。
"""

import argparse
import hashlib
import json
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Windows 控制台默认 GBK，强制 UTF-8 输出避免中文乱码
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "sources"
CACHE_DIR = SCRIPT_DIR / ".scraper_cache"
CACHE_TTL = 24 * 3600

GITHUB_API = "https://api.github.com"
GITHUB_RAW = "https://raw.githubusercontent.com"
GITEE_API = "https://gitee.com/api/v5"
GREP_API = "https://grep.app/api/search"
UA = "musicTool-source-scraper/1.0"

# grep.app 代码级搜索：直接找内容含音乐源字段的 JSON 文件
GREP_QUERIES = [
    '"keywordParam" "baseUrl" "mapping" lang:JSON',
    '"baseUrl" "mapping" "durationUnit" lang:JSON',
    '"音乐源" "baseUrl" "keywordParam" lang:JSON',
]

# 内置模板：公开、免密钥的音乐 API，开箱即可完整播放
BUILTIN_TEMPLATES = [
    {
        "name": "酷狗 完整歌曲",
        "version": "1.0.1",
        "baseUrl": "http://mobilecdn.kugou.com/api/v3",
        "headers": {},
        "notes": "部分热门曲目需酷狗会员，未授权曲目无法播放",
        "search": {
            "path": "/search/song",
            "method": "GET",
            "keywordParam": "keyword",
            "params": {"format": "json", "page": 1, "pagesize": 30},
            "body": {},
        },
        "mapping": {
            "list": "data.info",
            "id": "hash",
            "title": "songname",
            "artist": "singername",
            "album": "album_name",
            "cover": "",
            "url": "",
            "urlResolve": {
                "path": "https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash={id}",
                "method": "GET",
                "urlPath": "url",
                "body": {},
            },
            "duration": "duration",
            "durationUnit": "s",
        },
    },
    {
        "name": "Audius 音乐",
        "version": "1.1.0",
        "baseUrl": "https://discoveryprovider.audius.co",
        "headers": {},
        "notes": "海外开放平台，需可访问外网；仅展示可播放曲目",
        "search": {
            "path": "/v1/tracks/search",
            "method": "GET",
            "keywordParam": "query",
            "params": {"app_name": "zephyr", "limit": 30},
            "body": {},
        },
        "mapping": {
            "list": "data",
            "id": "id",
            "title": "title",
            "artist": "user.name",
            "album": "",
            "cover": "artwork.480x480",
            "url": "",
            "urlTemplate": "https://discoveryprovider.audius.co/v1/tracks/{id}/stream?app_name=zephyr",
            "duration": "duration",
            "durationUnit": "s",
            "filter": {"is_streamable": True, "is_delete": False},
        },
    },
    {
        "name": "酷我 完整歌曲",
        "version": "1.0.1",
        "baseUrl": "https://search.kuwo.cn",
        "headers": {},
        "notes": "免登录，主流曲目覆盖好，解析成功率高",
        "search": {
            "path": "/r.s",
            "method": "GET",
            "keywordParam": "all",
            "params": {
                "client": "kt",
                "pn": 0,
                "rn": 30,
                "ft": "music",
                "rformat": "json",
                "encoding": "utf8",
                "mobi": 1,
            },
            "body": {},
        },
        "mapping": {
            "list": "abslist",
            "id": "MUSICRID",
            "title": "SONGNAME",
            "artist": "ARTIST",
            "album": "ALBUM",
            "cover": "web_albumpic_short",
            "url": "",
            "urlResolve": {
                "path": "https://antiserver.kuwo.cn/anti.s?type=convert_url&rid={id}&format=mp3&response=url",
                "method": "GET",
                "urlPath": "",
                "body": {},
            },
            "duration": "DURATION",
            "durationUnit": "s",
        },
    },
    {
        "name": "网易云音乐",
        "version": "1.0.0",
        "baseUrl": "https://music.163.com",
        "headers": {
            "Referer": "https://music.163.com/",
            "Cookie": "os=pc; appver=2.9.7",
        },
        "notes": "公开搜索接口；无版权/VIP 曲目会自动跳过",
        "search": {
            "path": "/api/cloudsearch/pc",
            "method": "GET",
            "keywordParam": "s",
            "params": {"type": 1, "offset": 0, "limit": 30, "total": "true"},
            "body": {},
        },
        "mapping": {
            "list": "result.songs",
            "id": "id",
            "title": "name",
            "artist": "ar",
            "album": "al",
            "cover": "al.picUrl",
            "url": "",
            "urlTemplate": "https://music.163.com/song/media/outer/url?id={id}.mp3",
            "duration": "dt",
            "durationUnit": "ms",
            "checkPlayable": True,
            "checkPlayableOnSearch": True,
        },
    },
    {
        "name": "ccMixter 开放音乐",
        "version": "1.0.0",
        "baseUrl": "https://ccmixter.org",
        "headers": {
            "Accept": "application/json",
            "Referer": "https://ccmixter.org/",
        },
        "notes": "CC 授权完整歌曲，英文关键词命中率更高",
        "search": {
            "path": "/api/query",
            "method": "GET",
            "keywordParam": "search",
            "params": {"f": "json", "limit": 15},
            "body": {},
        },
        "mapping": {
            "list": "",
            "id": "upload_id",
            "title": "upload_name",
            "artist": "user_name",
            "album": "",
            "cover": "",
            "url": "files.0.download_url",
            "duration": "",
            "durationUnit": "s",
            "checkPlayable": True,
        },
    },
]

# 仓库搜索关键词：前几个与 musicTool 音乐源格式强相关
SEARCH_KEYWORDS = [
    "音乐源 json baseUrl mapping",
    "music source json baseUrl mapping",
    "音乐盒子 音源 json",
    "音源 json 搜索 导入",
    "musicTool 音乐源",
    "聚合音乐 音源 json",
    "lx-music 音源 json",
    "music api source json",
]

MAX_REPOS_PER_RUN = 25
MAX_FILES_PER_REPO = 12
MAX_CANDIDATES = 150
MIN_FILE_BYTES = 80
MAX_FILE_BYTES = 200_000

GITHUB_SEARCH_INTERVAL = 7.0   # 未认证搜索 API 10 次/分钟
API_CALL_INTERVAL = 1.2        # 其余 API（树、文件列表等）


class Throttle:
    """简单限流：保证同类请求之间的最小间隔。"""

    def __init__(self, interval):
        self.interval = interval
        self.last = 0.0
        self.lock = threading.Lock()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            delay = self.last + self.interval - now
            if delay > 0:
                time.sleep(delay)
            self.last = time.monotonic()


search_throttle = Throttle(GITHUB_SEARCH_INTERVAL)
api_throttle = Throttle(API_CALL_INTERVAL)
grep_throttle = Throttle(3.0)


def log(msg):
    print(msg, flush=True)


def warn(msg):
    print(f"[!] {msg}", file=sys.stderr, flush=True)


def cache_key(url):
    return hashlib.md5(url.encode("utf-8")).hexdigest() + ".json"


def cache_get(url):
    CACHE_DIR.mkdir(exist_ok=True)
    f = CACHE_DIR / cache_key(url)
    if f.exists() and time.time() - f.stat().st_mtime < CACHE_TTL:
        try:
            return json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            return None
    return None


def cache_put(url, data):
    CACHE_DIR.mkdir(exist_ok=True)
    try:
        (CACHE_DIR / cache_key(url)).write_text(
            json.dumps(data, ensure_ascii=False), encoding="utf-8"
        )
    except OSError:
        pass


def http_get(url, headers=None, timeout=20, retries=2, throttle=None):
    """GET 请求，带缓存与限流；返回 (状态码, 文本)。"""
    cached = cache_get(url)
    if cached is not None:
        return cached["status"], cached["body"]

    req_headers = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        req_headers.update(headers)

    last_err = None
    for attempt in range(retries + 1):
        if throttle:
            throttle.wait()
        req = urllib.request.Request(url, headers=req_headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                cache_put(url, {"status": resp.status, "body": body})
                return resp.status, body
        except urllib.error.HTTPError as e:
            last_err = e
            body = ""
            try:
                body = e.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            if e.code in (403, 429):
                warn(f"限流/拒绝 ({e.code}) {url}，{attempt + 1}/{retries + 1} 次，等待 15s 重试…")
                time.sleep(15)
                continue
            return e.code, body
        except Exception as e:  # 网络错误
            last_err = e
            time.sleep(3)
    return 0, str(last_err or "request failed")


def http_get_json(url, headers=None, throttle=None):
    status, body = http_get(url, headers=headers, throttle=throttle)
    if status != 200:
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return None


def find_json_blobs(tree, limit=MAX_FILES_PER_REPO):
    """从 git tree 中筛出候选 JSON 文件路径。"""
    out = []
    for item in tree:
        if item.get("type") != "blob":
            continue
        path = item.get("path", "")
        size = item.get("size") or 0
        if not path.lower().endswith(".json"):
            continue
        if not (MIN_FILE_BYTES <= size <= MAX_FILE_BYTES):
            continue
        out.append(path)
        if len(out) >= limit:
            break
    return out


def search_github_repos(keyword, token=None, per_page=20):
    headers = {}
    if token:
        headers["Authorization"] = f"token {token}"
    q = urllib.parse.quote(keyword)
    url = f"{GITHUB_API}/search/repositories?q={q}&per_page={per_page}&sort=updated"
    data = http_get_json(url, headers=headers, throttle=search_throttle)
    if not data:
        return []
    return [
        {
            "provider": "github",
            "full_name": r["full_name"],
            "branch": r.get("default_branch", "master"),
        }
        for r in data.get("items", [])
    ]


def search_gitee_repos(keyword, per_page=20):
    q = urllib.parse.quote(keyword)
    url = f"{GITEE_API}/search/repositories?q={q}&per_page={per_page}"
    data = http_get_json(url, throttle=search_throttle)
    if not data:
        return []
    out = []
    for r in data:
        full = r.get("full_name") or ""
        if not full:
            continue
        out.append(
            {
                "provider": "gitee",
                "full_name": full,
                "branch": r.get("default_branch", "master"),
            }
        )
    return out


def repo_tree(repo):
    """获取仓库文件树；返回文件路径列表或 None。"""
    full, branch = repo["full_name"], repo["branch"]
    if repo["provider"] == "github":
        url = f"{GITHUB_API}/repos/{full}/git/trees/{branch}?recursive=1"
    else:
        url = f"{GITEE_API}/repos/{full}/git/trees/{branch}?recursive=1"
    data = http_get_json(url, throttle=api_throttle)
    if not data:
        return None
    if data.get("truncated"):
        warn(f"{full} 文件树过大被截断，仅扫描已返回部分")
    return data.get("tree") or []


def search_grep(query):
    """grep.app 代码级搜索，直接返回命中的 JSON 文件（仓库 + 路径）。"""
    url = f"{GREP_API}?q={urllib.parse.quote(query)}"
    data = http_get_json(url, throttle=grep_throttle)
    if not data:
        return []
    hits = (data.get("hits") or {}).get("hits") or []
    out = []
    for h in hits:
        repo = h.get("repo") or {}
        path = h.get("path") or {}
        full = repo.get("raw")
        if full and path.get("raw"):
            out.append(
                {
                    "provider": "github",
                    "full_name": full,
                    "branch": repo.get("branch") or "master",
                    "path": path["raw"],
                }
            )
    return out


def repo_default_branch(full_name, provider):
    """查询仓库默认分支；失败返回 'master'。"""
    if provider == "github":
        url = f"{GITHUB_API}/repos/{full_name}"
    else:
        url = f"{GITEE_API}/repos/{full_name}"
    data = http_get_json(url, throttle=api_throttle)
    if data:
        return data.get("default_branch") or "master"
    return "master"


def raw_url(repo, path):
    if repo["provider"] == "github":
        return f"{GITHUB_RAW}/{repo['full_name']}/{repo['branch']}/{path}"
    return f"https://gitee.com/{repo['full_name']}/raw/{repo['branch']}/{path}"


def discover_repos(keyword, token=None):
    repos = search_github_repos(keyword, token=token)
    repos += search_gitee_repos(keyword)
    seen, unique = set(), []
    for r in repos:
        key = (r["provider"], r["full_name"])
        if key not in seen:
            seen.add(key)
            unique.append(r)
    return unique


def extract_by_path(obj, path):
    """按点号路径从嵌套字典中取值；路径为空返回 obj 本身。"""
    cur = obj
    if not path:
        return cur
    for part in path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def normalize_source(obj):
    """校验并规范化音乐源 JSON，返回应用可直接导入的字典；不合法返回 None。

    与 App 内 MusicSource.fromJson 的校验规则保持一致：
    name / baseUrl 必填，search 与 mapping 必须为对象，
    search.path 为以 / 开头的路径，mapping 至少包含 title 与 url 字段。
    """
    if not isinstance(obj, dict):
        return None
    name = str(obj.get("name") or "").strip()
    base_url = str(obj.get("baseUrl") or "").strip()
    if not name or not base_url.lower().startswith(("http://", "https://")):
        return None

    search = obj.get("search")
    mapping = obj.get("mapping")
    if not isinstance(search, dict) or not isinstance(mapping, dict):
        return None

    path = str(search.get("path") or "").strip()
    method = str(search.get("method") or "GET").upper()
    if not path.startswith("/"):
        return None
    if method not in ("GET", "POST"):
        return None
    if not str(mapping.get("title") or "").strip():
        return None
    url_field = str(mapping.get("url") or "").strip()
    url_template = str(mapping.get("urlTemplate") or "").strip()
    url_resolve = mapping.get("urlResolve")
    if not url_field and not url_template:
        if not (isinstance(url_resolve, dict)
                and str(url_resolve.get("path") or "").strip()):
            return None

    def as_map(v):
        return v if isinstance(v, dict) else {}

    def as_str_map(v):
        if not isinstance(v, dict):
            return {}
        return {str(k): str(val) for k, val in v.items()}

    m = {str(k): v for k, v in mapping.items()}
    m.setdefault("list", "")
    m.setdefault("id", "id")
    m.setdefault("album", "album")
    m.setdefault("cover", "picUrl")
    m.setdefault("duration", "duration")
    m.setdefault("durationUnit", "s")

    def norm_resolve(v):
        if not isinstance(v, dict):
            return None
        r = {str(k): val for k, val in v.items()}
        r.setdefault("method", "GET")
        r.setdefault("body", {})
        return {
            "path": str(r.get("path") or "").strip(),
            "method": str(r.get("method") or "GET").upper(),
            "urlPath": str(r.get("urlPath") or "").strip(),
            "body": as_map(r.get("body")),
        }

    s = {str(k): v for k, v in search.items()}
    s.setdefault("keywordParam", "keywords")
    resolved = norm_resolve(url_resolve)

    return {
        "name": name,
        "version": str(obj.get("version") or "1.0.0"),
        "baseUrl": base_url.rstrip("/"),
        "headers": as_str_map(obj.get("headers")),
        "notes": str(obj.get("notes") or ""),
        "search": {
            "path": path,
            "method": method,
            "keywordParam": str(s.get("keywordParam") or "keywords"),
            "params": as_map(s.get("params")),
            "body": as_map(s.get("body")),
        },
        "mapping": {
            "list": str(m.get("list") or ""),
            "id": str(m.get("id") or "id"),
            "title": str(m.get("title") or ""),
            "artist": str(m.get("artist") or "artists"),
            "album": str(m.get("album") or "album"),
            "cover": str(m.get("cover") or "picUrl"),
            "url": str(m.get("url") or ""),
            "urlTemplate": url_template,
            **({"urlResolve": resolved} if resolved else {}),
            "duration": str(m.get("duration") or "duration"),
            "durationUnit": str(m.get("durationUnit") or "s").lower(),
            **(
                {"filter": {str(k): v for k, v in m["filter"].items()}}
                if isinstance(m.get("filter"), dict)
                else {}
            ),
            **({"checkPlayable": True} if m.get("checkPlayable") is True else {}),
            **(
                {"checkPlayableOnSearch": True}
                if m.get("checkPlayableOnSearch") is True
                else {}
            ),
        },
    }


def test_source(source, keyword="周杰伦", timeout=12):
    """对音乐源做一次真实搜索，返回 (是否可用, 结果数)。"""
    s = source["search"]
    try:
        url = source["baseUrl"] + s["path"]
        headers = dict(source.get("headers") or {})
        headers["User-Agent"] = UA
        if s["method"] == "POST":
            body = {s["keywordParam"]: keyword, **s["body"]}
            req = urllib.request.Request(
                url,
                data=json.dumps(body).encode("utf-8"),
                headers={**headers, "Content-Type": "application/json"},
            )
        else:
            query = {k: str(v) for k, v in s["params"].items()}
            query[s["keywordParam"]] = keyword
            url = url + "?" + urllib.parse.urlencode(query)
            req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
        lst = extract_by_path(data, source["mapping"].get("list", ""))
        if isinstance(lst, list):
            return True, len(lst)
        if isinstance(lst, dict):
            return True, len(lst)
        return False, 0
    except Exception:
        return False, 0


def search_source(source, keyword, timeout=15):
    """按音乐源配置执行一次搜索，返回解析后的 JSON；失败返回 None。"""
    s = source["search"]
    try:
        url = source["baseUrl"] + s["path"]
        headers = dict(source.get("headers") or {})
        headers["User-Agent"] = UA
        if s["method"] == "POST":
            body = {s["keywordParam"]: keyword, **s["body"]}
            req = urllib.request.Request(
                url,
                data=json.dumps(body).encode("utf-8"),
                headers={**headers, "Content-Type": "application/json"},
            )
        else:
            query = {k: str(v) for k, v in s["params"].items()}
            query[s["keywordParam"]] = keyword
            url = url + "?" + urllib.parse.urlencode(query)
            req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception as e:
        warn(f"{source['name']} 搜索失败：{e}")
        return None


def get_path(data, path):
    """按点号路径取值，与 App 内 json_utils.getPath 行为一致（支持列表下标）。"""
    if not path:
        return data
    cur = data
    for part in path.split("."):
        if isinstance(cur, dict):
            cur = cur.get(part)
        elif isinstance(cur, list):
            try:
                cur = cur[int(part)]
            except (ValueError, IndexError):
                return None
        else:
            return None
    return cur


def matches_filter(item, flt):
    """与 App 内 matchesFilter 行为一致：所有条件都满足才保留。"""
    if not isinstance(flt, dict) or not flt:
        return True
    for key, expected in flt.items():
        actual = get_path(item, key)
        if isinstance(expected, bool):
            if (actual is True) != expected:
                return False
        elif isinstance(expected, (int, float)):
            try:
                if float(actual) != float(expected):
                    return False
            except (TypeError, ValueError):
                return False
        else:
            if as_text(actual) != str(expected):
                return False
    return True


def as_text(v):
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    if isinstance(v, (int, float, bool)):
        return str(v)
    return ""


def artist_text(v):
    if v is None:
        return ""
    if isinstance(v, list):
        return " / ".join(s for s in (artist_text(x) for x in v) if s)
    if isinstance(v, dict):
        for key in ("name", "nickname", "title", "username"):
            if v.get(key) is not None:
                return as_text(v[key])
        return ""
    return as_text(v)


def album_text(v):
    if isinstance(v, dict):
        for key in ("name", "title"):
            if v.get(key) is not None:
                return as_text(v[key])
        return ""
    return as_text(v)


def resolve_url(base_url, raw):
    if not raw:
        return ""
    if raw.startswith("//"):
        return "https:" + raw
    return urllib.parse.urljoin(base_url + "/", raw)


def resolve_template_url(template, item):
    """将 {field} 占位符按条目字段解析为完整 URL。"""
    if not template:
        return ""
    out = template
    for field in re.findall(r"\{([^{}]+)\}", template):
        value = as_text(get_path(item, field))
        out = out.replace("{" + field + "}", urllib.parse.quote(value))
    return out


def extract_songs(source, data):
    """从搜索响应中提取歌曲列表，与 App 内 json_utils.extractSongs 逻辑一致。"""
    m = source["mapping"]
    lst = get_path(data, m.get("list", ""))
    if not isinstance(lst, list):
        return []
    songs = []
    for item in lst:
        if not isinstance(item, dict):
            continue
        if not matches_filter(item, m.get("filter")):
            continue
        song_id = as_text(get_path(item, m.get("id", "")))
        title = as_text(get_path(item, m.get("title", "")))
        if not song_id or not title:
            continue
        raw_url = as_text(get_path(item, m.get("url", "")))
        if raw_url:
            url = resolve_url(source["baseUrl"], raw_url)
        elif m.get("urlTemplate"):
            url = resolve_template_url(m["urlTemplate"], item)
            url = resolve_url(source["baseUrl"], url) if url else ""
        elif m.get("urlResolve"):
            url = ""  # 播放地址需二次请求，App 播放时解析
        else:
            continue
        duration = None
        d = get_path(item, m.get("duration", ""))
        value = None
        if isinstance(d, (int, float)):
            value = d
        elif isinstance(d, str):
            try:
                value = float(d)
            except ValueError:
                value = None
        if value is not None:
            duration = round(value / 1000) if m.get("durationUnit") == "ms" else round(value)
        raw_cover = as_text(get_path(item, m.get("cover", "")))
        songs.append(
            {
                "id": song_id,
                "title": title,
                "artist": artist_text(get_path(item, m.get("artist", ""))),
                "album": album_text(get_path(item, m.get("album", ""))),
                "cover": resolve_url(source["baseUrl"], raw_cover) if raw_cover else "",
                "url": url,
                "duration": duration,
                "source": source["name"],
            }
        )
    return songs


def load_local_sources():
    """读取 sources/ 目录中已保存的音乐源，返回规范化后的列表。"""
    sources = []
    if not OUTPUT_DIR.exists():
        return sources
    for f in sorted(OUTPUT_DIR.glob("*.json")):
        try:
            obj = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        src = normalize_source(obj)
        if src:
            sources.append(src)
    return sources


def download_binary(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except Exception:
        return None


def run_search_songs(keyword, download=False):
    """用所有本地音乐源搜索歌曲，结果写入 scraped_songs.json。"""
    sources = load_local_sources()
    if not sources:
        log("sources/ 目录没有有效的音乐源，请先运行一次抓取（不带 --search）")
        return 1
    log(f"[搜索] 关键词「{keyword}」，共 {len(sources)} 个音乐源\n")
    seen = set()
    songs = []
    for src in sources:
        log(f"[来源] {src['name']}")
        data = search_source(src, keyword)
        if data is None:
            continue
        found = extract_songs(src, data)
        log(f"  命中 {len(found)} 首")
        for song in found:
            key = (song["title"], song["artist"])
            if key in seen:
                continue
            seen.add(key)
            songs.append(song)
    if not songs:
        log("没有搜到任何歌曲")
        return 1

    if download:
        log(f"\n[下载] 开始下载 {len(songs)} 个试听文件…")
        files_dir = SCRIPT_DIR / "scraped_files"
        files_dir.mkdir(exist_ok=True)
        ok = 0
        for i, song in enumerate(songs, 1):
            raw = song["url"]
            if not raw.startswith(("http://", "https://")):
                continue
            data = download_binary(raw)
            if data is None:
                log(f"  [{i}/{len(songs)}] 下载失败：{song['title']}")
                continue
            ext = Path(urllib.parse.urlparse(raw).path).suffix or ".mp3"
            stem = sanitize_filename(f"{song['artist']} - {song['title']}")[:60]
            name = f"{stem}_{hashlib.md5(raw.encode('utf-8')).hexdigest()[:8]}{ext}"
            (files_dir / name).write_bytes(data)
            song["url"] = f"scraped_files/{name}"
            ok += 1
            log(f"  [{i}/{len(songs)}] 已保存：{name}")
        log(f"\n[下载] 成功 {ok}/{len(songs)}")

    out = {
        "keyword": keyword,
        "generatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
        "count": len(songs),
        "songs": songs,
    }
    path = SCRIPT_DIR / "scraped_songs.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    log(f"\n已保存 {len(songs)} 首到 {path}")
    if download:
        log(f"音频文件位于 {SCRIPT_DIR / 'scraped_files'}")
    return 0


def sync_app_assets():
    """把 sources/ 中的音乐源同步到 App 内置资源目录 assets/sources/。"""
    if not OUTPUT_DIR.exists():
        log("sources/ 目录不存在，请先运行一次抓取")
        return 1
    assets_dir = SCRIPT_DIR.parent / "assets" / "sources"
    assets_dir.mkdir(parents=True, exist_ok=True)
    copied = 0
    for f in sorted(OUTPUT_DIR.glob("*.json")):
        try:
            obj = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        src = normalize_source(obj)
        if src is None:
            continue
        (assets_dir / f.name).write_text(
            json.dumps(src, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        copied += 1
        log(f"  + {f.name}")
    log(f"\n已同步 {copied} 个音乐源到 {assets_dir}")
    log("重新构建 App 后，开箱即用即可搜索这些源")
    return 0


def sanitize_filename(name):
    cleaned = re.sub(r'[\\/:*?"<>|\s]+', "_", name).strip("_")
    return cleaned or "source"


class SourceCollector:
    def __init__(self, token=None, test=False, verbose=False):
        self.token = token
        self.test = test
        self.verbose = verbose
        self.sources = {}  # (name, baseUrl) -> dict(source=..., origin=...)

    def add(self, obj, origin):
        src = normalize_source(obj)
        if src is None:
            return False
        key = (src["name"], src["baseUrl"])
        if key not in self.sources:
            self.sources[key] = {"source": src, "origin": origin}
        return True

    def add_templates(self):
        for tpl in BUILTIN_TEMPLATES:
            if self.add(tpl, "内置模板（公开 API）"):
                log(f"  + 内置模板：{tpl['name']}")

    def add_file(self, url, origin):
        status, body = http_get(url)
        if status != 200:
            if self.verbose:
                warn(f"下载失败 ({status}) {url}")
            return False
        try:
            obj = json.loads(body)
        except json.JSONDecodeError:
            return False
        return self.add(obj, origin)

    def scan_repo(self, repo, max_files=MAX_FILES_PER_REPO):
        tree = repo_tree(repo)
        if tree is None:
            return
        for path in find_json_blobs(tree, limit=max_files):
            if self.add_file(raw_url(repo, path), f"{repo['provider']}:{repo['full_name']}/{path}"):
                log(f"  + 发现可用音乐源：{path}")

    def run_search(self, max_repos=MAX_REPOS_PER_RUN, max_candidates=MAX_CANDIDATES):
        log("[搜索] grep.app 代码级搜索")
        for q in GREP_QUERIES:
            for hit in search_grep(q):
                origin = f"grep.app:{hit['full_name']}/{hit['path']}"
                if self.add_file(raw_url(hit, hit["path"]), origin):
                    log(f"  + 发现可用音乐源：{hit['full_name']}/{hit['path']}")
        log("")
        repos = []
        for kw in SEARCH_KEYWORDS:
            log(f"[搜索] 关键词：{kw}")
            for r in discover_repos(kw, token=self.token):
                if (r["provider"], r["full_name"]) not in [
                    (x["provider"], x["full_name"]) for x in repos
                ]:
                    repos.append(r)
            if len(repos) >= max_repos:
                break
        repos = repos[:max_repos]
        log(f"[搜索] 共 {len(repos)} 个候选仓库\n")
        for r in repos:
            if len(self.sources) >= max_candidates:
                break
            log(f"[扫描] {r['provider']} {r['full_name']}")
            try:
                self.scan_repo(r)
            except Exception as e:
                warn(f"扫描 {r['full_name']} 失败：{e}")

    def finalize(self):
        """去重后写出到 sources/ 目录，返回保存的条目列表。"""
        OUTPUT_DIR.mkdir(exist_ok=True)
        used_names = set()
        results = []
        for item in self.sources.values():
            src, origin = item["source"], item["origin"]
            base = sanitize_filename(src["name"])
            name = base
            n = 2
            while name in used_names:
                name = f"{base}_{n}"
                n += 1
            used_names.add(name)
            if self.test:
                ok, count = test_source(src)
                status = f"可用({count}条)" if ok else "不可用"
            else:
                status = "未测试"
            path = OUTPUT_DIR / f"{name}.json"
            path.write_text(
                json.dumps(src, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            results.append((src, origin, status, path))
        return results


def print_summary(results):
    log("\n" + "=" * 64)
    log(f"共找到 {len(results)} 个音乐源，已保存到 {OUTPUT_DIR}")
    log("=" * 64)
    for src, origin, status, path in results:
        log(f"名称   : {src['name']}")
        log(f"地址   : {src['baseUrl']}{src['search']['path']}")
        log(f"来源   : {origin}")
        log(f"状态   : {status}")
        log(f"文件   : {path.name}")
        log("-" * 64)


def print_jsons(results):
    log("\n以下 JSON 可直接粘贴到 App「我的 → 导入音乐源 → 粘贴 JSON 文本」：")
    for src, _, _, _ in results:
        log("\n" + json.dumps(src, ensure_ascii=False, indent=2))


def lan_ips():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                ips.add(ip)
    except OSError:
        pass
    return sorted(ips)


def serve_sources(port, results):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(OUTPUT_DIR), **kwargs)

        def log_message(self, fmt, *args):
            print(f"[HTTP] {self.client_address[0]} {fmt % args}", flush=True)

    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    log(f"\n本地音乐源服务已启动：http://0.0.0.0:{port}")
    for ip in lan_ips():
        log(f"  手机与电脑处于同一局域网时，可用「从链接导入」：")
        for src, _, _, path in results:
            log(f"    http://{ip}:{port}/{path.name}")
    log("按 Ctrl+C 停止服务")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("\n服务已停止")
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(
        description="搜索并抓取 musicTool 音乐源 JSON（GitHub/Gitee）"
    )
    parser.add_argument("--repo", help="扫描指定仓库，如 owner/name")
    parser.add_argument("--url", help="抓取并校验单个音乐源 JSON 文件")
    parser.add_argument("--test", action="store_true", help="对找到的源做真实搜索测试")
    parser.add_argument("--search", metavar="KEYWORD",
                        help="用 sources/ 中的音乐源搜索歌曲，结果存 scraped_songs.json")
    parser.add_argument("--download", action="store_true",
                        help="与 --search 联用：下载试听音频到 scraped_files/")
    parser.add_argument("--app-assets", action="store_true",
                        help="把 sources/ 中的音乐源同步到 App 内置资源 assets/sources/")
    parser.add_argument("--print", action="store_true", help="打印每个源的 JSON 文本")
    parser.add_argument("--serve", nargs="?", const=8000, type=int, metavar="PORT",
                        help="启动本地 HTTP 服务（默认端口 8000）")
    parser.add_argument("--token", help="GitHub Token（提高限流额度）")
    parser.add_argument("--no-templates", action="store_true",
                        help="不生成内置公开 API 模板")
    parser.add_argument("--max-repos", type=int, default=MAX_REPOS_PER_RUN)
    parser.add_argument("--verbose", action="store_true", help="输出更多调试信息")
    args = parser.parse_args()

    if args.download and not args.search:
        parser.error("--download 需要与 --search 联用")
    if args.app_assets:
        return sync_app_assets()
    if args.search:
        return run_search_songs(args.search, download=args.download)

    collector = SourceCollector(token=args.token, test=args.test, verbose=args.verbose)

    if args.url:
        if not collector.add_file(args.url, args.url):
            log("该文件不是有效的 musicTool 音乐源")
            return 1
    elif args.repo:
        repo = {
            "provider": "github",
            "full_name": args.repo,
            "branch": repo_default_branch(args.repo, "github"),
        }
        tree = repo_tree(repo)
        if tree is None:
            repo = {
                "provider": "gitee",
                "full_name": args.repo,
                "branch": repo_default_branch(args.repo, "gitee"),
            }
            tree = repo_tree(repo)
        if tree is None:
            log("无法访问该仓库（GitHub/Gitee 均失败）")
            return 1
        log(f"[扫描] {repo['provider']} {repo['full_name']}")
        collector.scan_repo(repo, max_files=MAX_FILES_PER_REPO * 2)
    else:
        collector.run_search(max_repos=args.max_repos)

    if not args.no_templates:
        log("\n[模板] 生成内置公开 API 音乐源")
        collector.add_templates()

    results = collector.finalize()
    if not results:
        log("没有找到有效的音乐源。可尝试：--repo 指定仓库 / --url 指定文件 / --verbose 查看原因")
        return 1

    print_summary(results)
    if args.print:
        print_jsons(results)
    if args.serve:
        serve_sources(args.serve, results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
