"""英语口语教练 App 图标生成器（Pillow）。

设计：圆角方形渐变底 + 白色麦克风 + 声波 + 暖色星点。
输出：
- icon_master_1024.png      主图标（圆角，用于商店/文档/AppScope）
- icon_foreground_1024.png  鸿蒙分层图标前景（透明，安全区内）
- icon_background_1024.png  鸿蒙分层图标背景（满幅渐变）
- icon_square_1024.png      满幅方图（部分商店要求无圆角）
- icon_216.png / 128 / 64   小尺寸检查
- preview_sheet.png         多尺寸/明暗底预览
- icon_book_*.png           备选方案（书本 + 声波）
"""
from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.abspath(__file__))
SS = 3  # 超采样倍数


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def gradient(size: int, top: str, bottom: str, angle_deg: float = 35.0) -> Image.Image:
    """线性渐变（角度制，0=向右，90=向下）。"""
    w = h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    c1 = hex_rgb(top)
    c2 = hex_rgb(bottom)
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    max_proj = abs(dx) * w + abs(dy) * h
    for y in range(h):
        for x in range(w):
            proj = (x * dx + y * dy) + (max_proj - (dx * w + dy * h)) / 2
            t = min(1.0, max(0.0, proj / max_proj))
            t = t * t * (3 - 2 * t)
            px[x, y] = (
                int(lerp(c1[0], c2[0], t)),
                int(lerp(c1[1], c2[1], t)),
                int(lerp(c1[2], c2[2], t)),
            )
    return img


def squircle_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def arc_with_caps(draw: ImageDraw.ImageDraw, box, start, end, fill, width, caps=True):
    draw.arc(box, start=start, end=end, fill=fill, width=width)
    if not caps:
        return
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    r = (x1 - x0) / 2
    for ang in (start, end):
        a = math.radians(ang)
        px = cx + r * math.cos(a)
        py = cy + r * math.sin(a)
        draw.ellipse(
            [px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=fill
        )


def sparkle(draw: ImageDraw.ImageDraw, cx: float, cy: float, s: float, fill):
    """四角星（暖色点缀）。"""
    inner = s * 0.26
    pts = []
    for i in range(8):
        ang = math.radians(-90 + i * 45)
        r = s if i % 2 == 0 else inner
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    draw.polygon(pts, fill=fill)


def draw_mic_foreground(size: int, content_scale: float = 0.72) -> Image.Image:
    """透明前景：白色麦克风 + 声波 + 星点（居中，安全区内）。"""
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    s = size * content_scale
    ox = (size - s) / 2

    def P(fx: float) -> float:
        """内容坐标（0..1 比例）→ 画布坐标。"""
        return ox + fx * s

    def L(fr: float) -> float:
        """长度比例 → 画布长度。"""
        return fr * s

    white = (255, 255, 255, 255)

    # 声波（右侧，从麦克风向外）
    wcx, wcy = P(0.500), P(0.372)
    for rr, alpha, wid in ((0.215, 235, 0.052), (0.305, 175, 0.046), (0.395, 118, 0.040)):
        r = L(rr)
        arc_with_caps(
            d,
            [wcx - r, wcy - r, wcx + r, wcy + r],
            -58,
            58,
            (255, 255, 255, alpha),
            max(2, int(L(wid))),
        )

    # 麦克风主体（圆角胶囊）
    body_w = L(0.170)
    cx = P(0.380)
    d.rounded_rectangle(
        [cx - body_w / 2, P(0.135), cx + body_w / 2, P(0.520)],
        radius=body_w / 2,
        fill=white,
    )
    # 网罩细线
    line_color = (198, 194, 242, 235)
    for i in range(3):
        y = P(0.135 + 0.055 + i * 0.045)
        pad = body_w * 0.26
        d.line(
            [cx - body_w / 2 + pad, y, cx + body_w / 2 - pad, y],
            fill=line_color,
            width=max(2, int(L(0.011))),
        )

    # 支架圆弧
    stand_r = L(0.170)
    scx, scy = P(0.380), P(0.505)
    arc_with_caps(
        d,
        [scx - stand_r, scy - stand_r, scx + stand_r, scy + stand_r],
        20,
        160,
        white,
        max(3, int(L(0.046))),
    )
    # 竖杆 + 底座
    d.rounded_rectangle(
        [cx - L(0.026), P(0.660), cx + L(0.026), P(0.790)],
        radius=L(0.026),
        fill=white,
    )
    d.rounded_rectangle(
        [cx - L(0.135), P(0.790), cx + L(0.135), P(0.850)],
        radius=L(0.045),
        fill=white,
    )

    # 暖色星点（右上）
    sparkle(d, P(0.795), P(0.185), L(0.075), (255, 176, 128, 255))
    sparkle(d, P(0.700), P(0.105), L(0.036), (255, 214, 170, 220))

    return fg


def compose_icon(size: int, radius_ratio: float = 0.225) -> Image.Image:
    ss = size * SS
    bg = gradient(ss, "#7B68FF", "#4A34D8", angle_deg=52).convert("RGBA")
    # 左上柔光 + 右下压暗
    glow = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        [-ss * 0.35, -ss * 0.45, ss * 0.75, ss * 0.55],
        fill=(255, 255, 255, 26),
    )
    gd.ellipse(
        [ss * 0.25, ss * 0.65, ss * 1.35, ss * 1.55],
        fill=(20, 10, 70, 30),
    )
    bg = Image.alpha_composite(bg, glow)

    fg = draw_mic_foreground(ss, content_scale=0.70)
    icon = Image.alpha_composite(bg, fg)

    # 内侧高光描边
    stroke = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stroke)
    sd.rounded_rectangle(
        [1, 1, ss - 2, ss - 2],
        radius=ss * radius_ratio,
        outline=(255, 255, 255, 46),
        width=max(2, int(ss * 0.004)),
    )
    icon = Image.alpha_composite(icon, stroke)

    mask = squircle_mask(ss, ss * radius_ratio)
    out = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def compose_square(size: int) -> Image.Image:
    ss = size * SS
    bg = gradient(ss, "#7B68FF", "#4A34D8", angle_deg=52).convert("RGBA")
    fg = draw_mic_foreground(ss, content_scale=0.70)
    icon = Image.alpha_composite(bg, fg)
    return icon.resize((size, size), Image.LANCZOS)


def draw_book_icon(size: int) -> Image.Image:
    """备选：打开的书 + 声波。"""
    ss = size * SS
    bg = gradient(ss, "#2EC5B6", "#1F7AE0", angle_deg=45).convert("RGBA")
    d = ImageDraw.Draw(bg)
    s = ss * 0.66
    ox = (ss - s) / 2
    oy = (ss - s) / 2
    white = (255, 255, 255, 255)
    # 两页书
    d.rounded_rectangle(
        [ox + 0.06 * s, oy + 0.30 * s, ox + 0.48 * s, oy + 0.82 * s],
        radius=0.05 * s,
        fill=white,
    )
    d.rounded_rectangle(
        [ox + 0.52 * s, oy + 0.30 * s, ox + 0.94 * s, oy + 0.82 * s],
        radius=0.05 * s,
        fill=white,
    )
    # 书脊
    d.rounded_rectangle(
        [ox + 0.465 * s, oy + 0.28 * s, ox + 0.535 * s, oy + 0.84 * s],
        radius=0.035 * s,
        fill=(226, 222, 255, 255),
    )
    # 文字线
    for side in (0, 1):
        base = 0.18 if side == 0 else 0.60
        for i in range(3):
            y = oy + (0.42 + i * 0.075) * s
            d.rounded_rectangle(
                [ox + (base + 0.05) * s, y, ox + (base + 0.33) * s, y + 0.022 * s],
                radius=0.011 * s,
                fill=(120, 110, 220, 255),
            )
    # 上方声波
    cx, cy = ss / 2, oy + 0.12 * s
    for idx, (rr, alpha, wid) in enumerate(((0.10, 240, 0.030), (0.16, 170, 0.026))):
        r = rr * s
        arc_with_caps(
            d,
            [cx - r, cy - r * 0.7, cx + r, cy + r * 0.7],
            -60,
            60,
            (255, 255, 255, alpha),
            max(2, int(wid * s)),
        )
    sparkle(d, ox + 0.86 * s, oy + 0.16 * s, 0.06 * s, (255, 214, 120, 255))
    mask = squircle_mask(ss, ss * 0.225)
    out = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def contact_sheet(master: Image.Image, path: str) -> None:
    sizes = [216, 128, 64]
    sheet = Image.new("RGB", (1400, 760), (245, 246, 252))
    d = ImageDraw.Draw(sheet)
    d.text((40, 30), "English Coach icon — master 1024 / sizes / light & dark", fill=(40, 40, 70))
    big = master.resize((360, 360), Image.LANCZOS)
    sheet.paste(big, (40, 90), big)
    x = 440
    for s in (216, 128, 64):
        img = master.resize((s, s), Image.LANCZOS)
        sheet.paste(img, (x, 90), img)
        x += s + 40
    # 暗底
    dark = Image.new("RGB", (400, 200), (18, 18, 30))
    img = master.resize((160, 160), Image.LANCZOS)
    dark.paste(img, (20, 20), img)
    sheet.paste(dark, (40, 500))
    light = Image.new("RGB", (400, 200), (255, 255, 255))
    light.paste(img, (20, 20), img)
    sheet.paste(light, (480, 500))
    sheet.save(path)


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def export_platform_assets(master: Image.Image, square: Image.Image,
                           fg: Image.Image, bg: Image.Image) -> None:
    """把图标写到三个平台的项目资源里（HOS / Android / iOS）。"""
    repo = os.path.abspath(os.path.join(OUT, "..", "english-coach-app"))
    kit = os.path.join(repo, "design", "icon")
    ensure_dir(kit)

    # ---------- 通用资产包 ----------
    master.save(os.path.join(kit, "icon_1024.png"))
    square.save(os.path.join(kit, "icon_1024_square.png"))
    for s in (512, 256, 216, 192, 180, 167, 152, 144, 128, 96, 72, 64, 48, 32):
        master.resize((s, s), Image.LANCZOS).save(os.path.join(kit, f"icon_{s}.png"))

    # ---------- HarmonyOS ----------
    # 鸿蒙分层图标（DevEco 模板约定）：AppScope 与 entry 各放一份
    # background.png / foreground.png / layered_image.json，app.json5 与 module.json5 的
    # icon 都指向 $media:layered_image；启动页仍用 startIcon.png。
    hos_app = os.path.join(repo, "hos", "AppScope", "resources", "base", "media")
    hos_entry = os.path.join(repo, "hos", "entry", "src", "main", "resources", "base", "media")
    ensure_dir(hos_app)
    ensure_dir(hos_entry)
    bg.save(os.path.join(hos_app, "background.png"))
    fg.save(os.path.join(hos_app, "foreground.png"))
    bg.save(os.path.join(hos_entry, "background.png"))
    fg.save(os.path.join(hos_entry, "foreground.png"))
    square.save(os.path.join(hos_entry, "startIcon.png"))
    layered = (
        "{\n"
        "  \"layered-image\":\n"
        "  {\n"
        "    \"background\" : \"$media:background\",\n"
        "    \"foreground\" : \"$media:foreground\"\n"
        "  }\n"
        "}\n"
    )
    for folder in (hos_app, hos_entry):
        with open(os.path.join(folder, "layered_image.json"), "w", encoding="utf-8") as f:
            f.write(layered)
    # 清理上一版命名的多余资源
    for stale in ("icon_background.png", "icon_foreground.png", "app_icon.png"):
        p = os.path.join(hos_entry, stale)
        if os.path.exists(p):
            os.remove(p)

    # ---------- Android ----------
    ares = os.path.join(repo, "android", "app", "src", "main", "res")
    nodpi = os.path.join(ares, "drawable-nodpi")
    ensure_dir(nodpi)
    fg.save(os.path.join(nodpi, "ic_launcher_foreground.png"))
    bg.save(os.path.join(nodpi, "ic_launcher_background.png"))
    for folder, s in (
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ):
        d = os.path.join(ares, folder)
        ensure_dir(d)
        icon = master.resize((s, s), Image.LANCZOS)
        icon.save(os.path.join(d, "ic_launcher.png"))
        icon.save(os.path.join(d, "ic_launcher_round.png"))
    # 万一没有 values 里的 ic_launcher_background 颜色，补一个渐变图即可（adaptive XML 改引用）

    # ---------- iOS ----------
    assets = os.path.join(repo, "ios", "EnglishCoach", "Resources", "Assets.xcassets")
    appicon = os.path.join(assets, "AppIcon.appiconset")
    ensure_dir(appicon)
    # Apple 要求无 alpha 的 1024 方图
    square.convert("RGB").save(os.path.join(appicon, "icon_1024.png"))
    contents = (
        "{\n"
        "  \"images\" : [\n"
        "    {\n"
        "      \"filename\" : \"icon_1024.png\",\n"
        "      \"idiom\" : \"universal\",\n"
        "      \"platform\" : \"ios\",\n"
        "      \"size\" : \"1024x1024\"\n"
        "    }\n"
        "  ],\n"
        "  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n"
        "}\n"
    )
    with open(os.path.join(appicon, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(contents)
    with open(os.path.join(assets, "Contents.json"), "w", encoding="utf-8") as f:
        f.write("{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n")
    print("exported to", repo)


def main() -> None:
    master = compose_icon(1024)
    master.save(os.path.join(OUT, "icon_master_1024.png"))

    square = compose_square(1024)
    square.save(os.path.join(OUT, "icon_square_1024.png"))

    # 鸿蒙分层图标
    fg = draw_mic_foreground(1024, content_scale=0.72)
    fg.save(os.path.join(OUT, "icon_foreground_1024.png"))
    bg = gradient(1024, "#7B68FF", "#4A34D8", angle_deg=52).convert("RGB")
    bg.save(os.path.join(OUT, "icon_background_1024.png"))

    for s in (216, 128, 64, 32):
        master.resize((s, s), Image.LANCZOS).save(os.path.join(OUT, f"icon_{s}.png"))

    book = draw_book_icon(1024)
    book.save(os.path.join(OUT, "icon_book_1024.png"))

    contact_sheet(master, os.path.join(OUT, "preview_sheet.png"))
    export_platform_assets(master, square, fg, bg.convert("RGBA"))
    print("done")


if __name__ == "__main__":
    main()
