#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_icons.py —— 生成 zephyr 应用图标（Android mipmap 全套 + 自适应图标）

用法：
  python tools/make_icons.py <源图片.jpg/png> [--res 路径]

功能：
  1. 去掉源图黑色背景（黑边），按亮度生成透明通道并做羽化
  2. 裁剪图标主体并居中到正方形画布，输出 1024x1024 母版 PNG
  3. 生成传统启动图标 ic_launcher.png（mdpi~xxxhdpi）
  4. 生成自适应图标 ic_launcher_foreground.png（Android 8+，内容缩放到安全区）
  5. 采样渐变背景色写入 values/ic_launcher_background.xml，
     并生成 mipmap-anydpi-v26/ic_launcher.xml

仅依赖 Pillow：pip install pillow
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageFilter

DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
LEGACY_BASE = 48        # 传统图标 mdpi 尺寸
ADAPTIVE_BASE = 108     # 自适应画布 mdpi 尺寸
ADAPTIVE_CONTENT_SCALE = 0.68  # 内容占画布比例（自适应图标安全区约 66%）
FOREGROUND_SAFE_SCALE = 0.62   # 母版用于前景时再收缩一点，避免被圆形蒙版裁切


def load_rgba(path):
    return Image.open(path).convert("RGB")


def strip_black_background(rgb):
    """黑色背景 → 透明：按亮度做线性羽化的 alpha 通道。"""
    r, g, b = rgb.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    # 亮度 <= 24 全透明，>= 64 不透明，中间线性过渡
    alpha = lum.point(lambda v: 0 if v <= 24 else (255 if v >= 64 else (v - 24) * 255 // 40))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    return Image.merge("RGBA", (r, g, b, alpha))


def crop_and_square(img):
    bbox = img.getbbox()
    if bbox is None:
        raise SystemExit("源图中未找到图标内容")
    img = img.crop(bbox)
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2), img)
    return canvas


def sample_background_color(img):
    """采样所有不透明像素的中位数，作为自适应图标背景色。"""
    small = img.resize((256, 256), Image.LANCZOS)
    samples = [
        (r, g, b)
        for r, g, b, a in small.getdata()
        if a > 200
    ]
    if not samples:
        return (30, 90, 200)
    n = len(samples)
    return tuple(sorted(v[i] for v in samples)[n // 2] for i in range(3))


def main():
    parser = argparse.ArgumentParser(description="生成 zephyr 应用图标")
    parser.add_argument("source", help="源图片路径（jpg/png，图标居中于黑色背景）")
    parser.add_argument(
        "--res",
        default=str(Path(__file__).resolve().parent.parent
                    / "android" / "app" / "src" / "main" / "res"),
        help="Android res 目录（默认自动定位）",
    )
    parser.add_argument(
        "--out-master",
        default=str(Path(__file__).resolve().parent / "icon_master.png"),
        help="1024x1024 透明母版输出路径",
    )
    args = parser.parse_args()

    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    res = Path(args.res)
    if not res.exists():
        raise SystemExit(f"res 目录不存在：{res}")

    src = load_rgba(args.source)
    icon = strip_black_background(src)
    icon = crop_and_square(icon)
    master = icon.resize((1024, 1024), Image.LANCZOS)

    master_path = Path(args.out_master)
    master_path.parent.mkdir(parents=True, exist_ok=True)
    master.save(master_path)
    print(f"母版已保存：{master_path} ({master.size[0]}x{master.size[1]})")

    # 传统启动图标（全出血）
    for name, scale in DENSITIES.items():
        size = round(LEGACY_BASE * scale)
        out = res / f"mipmap-{name}" / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.LANCZOS).save(out)
        print(f"  传统图标：{out.relative_to(res)} ({size}px)")

    # 自适应图标前景（内容收缩到安全区，透明留白）
    for name, scale in DENSITIES.items():
        size = round(ADAPTIVE_BASE * scale)
        content = round(size * ADAPTIVE_CONTENT_SCALE * FOREGROUND_SAFE_SCALE)
        fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        scaled = master.resize((content, content), Image.LANCZOS)
        fg.paste(scaled, ((size - content) // 2, (size - content) // 2), scaled)
        out = res / f"mipmap-{name}" / "ic_launcher_foreground.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        fg.save(out)
        print(f"  自适应前景：{out.relative_to(res)} ({size}px)")

    # 背景色资源
    bg = sample_background_color(master)
    color_xml = res / "values" / "ic_launcher_background.xml"
    color_xml.parent.mkdir(parents=True, exist_ok=True)
    color_xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print(f"  背景色：#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X} → {color_xml.relative_to(res)}")

    # 自适应图标描述
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    print(f"  自适应图标：{ (anydpi / 'ic_launcher.xml').relative_to(res) }")
    print("完成。")


if __name__ == "__main__":
    main()
