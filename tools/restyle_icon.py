#!/usr/bin/env python3
"""
把图标背景从绿色换成与 App UI 一致的蓝紫色，保留「7」的造型与颜色。
做法：用亮度阈值把「7」从纯色背景中分离成 alpha 蒙版，再与新的蓝紫渐变合成。
"""
import numpy as np
from PIL import Image, ImageFilter

SRC = "tools/icon-source.png"
OUT = "tools/icon-source.png"

src = Image.open(SRC).convert("RGB")
w, h = src.size
a = np.asarray(src).astype(np.float32)

# 亮度：背景绿 ~140，米白「7」~240
lum = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
lo, hi = 168.0, 212.0
alpha = np.clip((lum - lo) / (hi - lo), 0.0, 1.0)
alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                   .filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255.0
alpha = alpha[..., None]

# 「7」的原始颜色（取最亮区域的中位数，保持米白质感）
bright = a[lum > 235]
fg = np.median(bright, axis=0) if len(bright) else np.array([247, 242, 228], np.float32)

# 蓝紫渐变（与 App 主题 brand #5A5CE8 → brandSoft #8C73FF 一致）
yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
t = np.clip((xx / (w - 1)) * 0.35 + (yy / (h - 1)) * 0.65, 0, 1)[..., None]
c1 = np.array([0x5A, 0x5C, 0xE8], np.float32)   # 靛蓝
c2 = np.array([0x8C, 0x73, 0xFF], np.float32)   # 亮紫
bg = c1 * (1 - t) + c2 * t

# 顶部极淡高光，贴近 iOS 玻璃质感
glow = np.exp(-(((xx / w - 0.25) ** 2 + (yy / h - 0.1) ** 2) / 0.10))[..., None]
bg = np.clip(bg + glow * 26, 0, 255)

out = bg * (1 - alpha) + fg * alpha
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(OUT)
print("已生成蓝紫版图标:", OUT)
