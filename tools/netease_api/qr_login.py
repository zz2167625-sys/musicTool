#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网易云扫码登录助手：生成二维码 PNG，轮询登录状态，成功后保存 Cookie。

二维码文件：tools/netease_api/登录二维码.png（过期会自动重新生成，重新打开即可）
登录成功后 Cookie 写入 tools/netease_api/.login_cookie.txt
"""
import base64
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = "http://127.0.0.1:3000"
PNG = Path(__file__).resolve().parent / "登录二维码.png"
COOKIE_FILE = Path(__file__).resolve().parent / ".login_cookie.txt"


def api_get(path):
    with urllib.request.urlopen(BASE + path, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def save_qr(data):
    raw = data.get("qrimg") or ""
    if "," in raw:
        raw = raw.split(",", 1)[1]
    PNG.write_bytes(base64.b64decode(raw))
    print(f"[QR] 二维码已保存：{PNG}", flush=True)


def main():
    deadline = time.time() + 1800
    while time.time() < deadline:
        key = api_get("/login/qr/key")["data"]["unikey"]
        create = api_get(
            "/login/qr/create?key=%s&qrimg=true" % urllib.parse.quote(key)
        )
        save_qr(create["data"])
        while time.time() < deadline:
            time.sleep(3)
            try:
                chk = api_get(
                    "/login/qr/check?key=%s&timestamp=%d"
                    % (urllib.parse.quote(key), int(time.time() * 1000))
                )
            except Exception:
                continue
            code = chk.get("code")
            if code == 803:
                cookie = chk.get("cookie") or ""
                COOKIE_FILE.write_text(cookie, encoding="utf-8")
                print("[OK] 扫码登录成功，Cookie 已保存", flush=True)
                return 0
            if code == 800:
                print("[QR] 二维码已过期，重新生成…", flush=True)
                break
            if code == 802:
                print("[QR] 已扫码，请在手机上点击确认…", flush=True)
    print("[TIMEOUT] 等待超时，未完成登录", flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())
