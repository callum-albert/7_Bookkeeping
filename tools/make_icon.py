#!/usr/bin/env python3
"""
7记账 App 图标 —— 英文「Seven」
- 满幅方形 / 不透明 / 无圆角（iOS 自己裁圆角，返回桌面动画无白边）
- 字体：Avenir Next Bold（苹果自带，优雅现代）
- 液态玻璃背景：numpy 平滑渐变 + 高斯光斑
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "build/icons"
os.makedirs(OUT, exist_ok=True)

# 若存在自定义源图，则直接用它生成全部尺寸（满幅、不透明、无圆角）
SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon-source.png")

S = 2048
FONT_PATH = "/System/Library/Fonts/Avenir Next.ttc"
FONT_INDEX = 0          # Bold
TEXT = "Seven"
TEXT_WIDTH_RATIO = 0.725   # 文字宽度占图标宽度


# ───────────────────────────── 背景
def background(size=S):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)

    c_top = np.array([105,  88, 235], np.float32)   # 靛蓝紫
    c_mid = np.array([138,  90, 246], np.float32)   # 明紫
    c_bot = np.array([ 88,  34, 176], np.float32)   # 深紫

    t = np.clip(xx * 0.42 + yy * 0.58, 0, 1)
    w1 = np.clip(t / 0.58, 0, 1)[..., None]
    base = c_top * (1 - w1) + c_mid * w1
    w2 = np.clip((t - 0.58) / 0.42, 0, 1)[..., None]
    base = base * (1 - w2) + c_bot * w2

    def blob(cx, cy, r, color, strength):
        d2 = (xx - cx) ** 2 + (yy - cy) ** 2
        g = np.exp(-d2 / (r * r))[..., None]
        return g * (np.array(color, np.float32) - base) * strength

    base = base + blob(0.88, 0.08, 0.52, ( 56, 205, 200), 0.42)
    base = base + blob(0.04, 0.96, 0.46, (255, 145,  70), 0.30)
    base = base + blob(0.38, 0.10, 0.46, (255, 255, 255), 0.16)

    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))


# ───────────────────────────── 文字
def fitted_font(size, text=TEXT):
    """按目标宽度反推字号"""
    base = 200
    f = ImageFont.truetype(FONT_PATH, base, index=FONT_INDEX)
    d = ImageDraw.Draw(Image.new("L", (10, 10)))
    bb = d.textbbox((0, 0), text, font=f)
    w = bb[2] - bb[0]
    target = size * TEXT_WIDTH_RATIO
    return ImageFont.truetype(FONT_PATH, max(10, int(base * target / w)), index=FONT_INDEX)


def text_mask(size):
    font = fitted_font(size)
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)

    bb = d.textbbox((0, 0), TEXT, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    x = (size - tw) / 2 - bb[0]
    # 视觉居中：文字重心略高于几何中心
    y = (size - th) / 2 - bb[1] - size * 0.030

    d.text((x, y), TEXT, font=font, fill=255)
    return mask, (x, y, tw, th)


def paint_text(img, size):
    mask, _ = text_mask(size)

    # 投影
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sm = mask.filter(ImageFilter.GaussianBlur(size * 0.020))
    sh.paste((22, 8, 58, 105), (0, 0), sm)
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -size * 0.012), resample=Image.BILINEAR)
    img.paste(sh, (0, 0), sh)

    # 渐变填充：纯白 → 淡紫
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / (size - 1)
        col = (int(255 - 26 * t), int(255 - 30 * t), 255, 255)
        gd.line([(0, y), (size, y)], fill=col)
    img.paste(grad, (0, 0), mask)

    # 顶部内高光
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.rectangle([0, 0, size, size * 0.47], fill=(255, 255, 255, 64))
    hl = hl.filter(ImageFilter.GaussianBlur(size * 0.045))
    a = Image.composite(hl.getchannel("A"), Image.new("L", (size, size), 0), mask)
    hl.putalpha(a)
    img.paste(hl, (0, 0), hl)

    # 柔边
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    em = mask.filter(ImageFilter.GaussianBlur(size * 0.0025))
    ImageDraw.Draw(edge).bitmap((0, 0), em, fill=(255, 255, 255, 60))
    img.paste(edge, (0, 0), edge)
    return img


def make(size=S):
    img = background(size).convert("RGBA")
    img = paint_text(img, size)

    # 左上角极淡反光
    ov = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(ov).polygon([(0, 0), (size * 0.55, 0), (0, size * 0.55)], fill=(255, 255, 255, 16))
    ov = ov.filter(ImageFilter.GaussianBlur(size * 0.07))
    img.paste(ov, (0, 0), ov)

    out = Image.new("RGB", (size, size))
    out.paste(img.convert("RGB"), (0, 0))
    return out


if os.path.exists(SOURCE):
    src = Image.open(SOURCE).convert("RGB")
    # 居中裁成正方形，再缩放到 1024，保证满幅
    w, h = src.size
    side = min(w, h)
    src = src.crop(((w - side) // 2, (h - side) // 2,
                    (w - side) // 2 + side, (h - side) // 2 + side))
    big = src.resize((2048, 2048), Image.LANCZOS)
    print(f"using source: {SOURCE}  {src.size} -> 2048")
else:
    big = make()

big.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon-1024.png"), optimize=True)
for s in (180, 120, 87, 80, 76, 60, 58, 40):
    big.resize((s, s), Image.LANCZOS).save(os.path.join(OUT, f"icon-{s}.png"))

im = Image.open(os.path.join(OUT, "icon-1024.png"))
print(f"icons -> {OUT}  mode={im.mode} size={im.size}  (RGB 无透明 + 满幅 = 动画无白边)")
