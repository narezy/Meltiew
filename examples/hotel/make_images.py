#!/usr/bin/env python3
"""Draws the hotel's pictures: the Howl's screaming skull and the Watcher's eye (PNG with
transparency), and nothing else. Seeded, so every run draws the same."""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

here = os.path.dirname(os.path.abspath(__file__))
R = random.Random(7)
S = 1024  # drawn big, then shrunk (smooth edges)


def skull():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # A smoky black aura around it.
    aura = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(aura)
    for i in range(140):
        a = R.uniform(0, math.tau)
        r = R.uniform(250, 430)
        x, y = S / 2 + math.cos(a) * r * 0.9, S / 2 + math.sin(a) * r * 0.95 + 30
        w = R.uniform(40, 110)
        d.ellipse([x - w, y - w, x + w, y + w], fill=R.randint(120, 220))
    d.ellipse([S * 0.2, S * 0.17, S * 0.8, S * 0.9], fill=255)
    aura = aura.filter(ImageFilter.GaussianBlur(38))
    img.paste((8, 4, 10, 255), (0, 0), aura)
    # The skull: a cranium and a long jaw, bone white with a cold tint.
    bone = Image.new('L', (S, S), 0)
    b = ImageDraw.Draw(bone)
    b.ellipse([S * 0.27, S * 0.16, S * 0.73, S * 0.62], fill=255)  # cranium
    b.polygon([(S * 0.31, S * 0.5), (S * 0.69, S * 0.5), (S * 0.64, S * 0.86), (S * 0.5, S * 0.9), (S * 0.36, S * 0.86)], fill=255)  # jaw
    b.ellipse([S * 0.25, S * 0.42, S * 0.36, S * 0.6], fill=255)  # cheekbones
    b.ellipse([S * 0.64, S * 0.42, S * 0.75, S * 0.6], fill=255)
    bone = bone.filter(ImageFilter.GaussianBlur(3))
    shade = Image.new('RGBA', (S, S))
    sd = ImageDraw.Draw(shade)
    for y in range(S):
        t = y / S
        c = (int(232 - 90 * t), int(226 - 96 * t), int(214 - 70 * t), 255)
        sd.line([(0, y), (S, y)], fill=c)
    # Rounded: darker toward its edges, and grainy like old bone.
    edge = ImageChops.invert(bone.filter(ImageFilter.GaussianBlur(70)))
    dark = Image.new('RGBA', (S, S), (40, 30, 34, 255))
    shade.paste(dark, (0, 0), edge.point(lambda v: int(v * 0.85)))
    noise = Image.effect_noise((S, S), 40).convert('L')
    shade = Image.composite(shade, Image.new('RGBA', (S, S), (90, 80, 76, 255)), noise.point(lambda v: 255 if v > 70 else 210))
    img.paste(shade, (0, 0), bone)
    d = ImageDraw.Draw(img)
    # Deep eye sockets (uneven) with small burning pupils.
    for cx in (0.4, 0.6):
        x, y = S * cx, S * 0.43
        pts = []
        for k in range(14):
            a = k / 14 * math.tau
            r = R.uniform(70, 92)
            pts.append((x + math.cos(a) * r * 1.05, y + 8 + math.sin(a) * r * 0.95))
        sock = Image.new('L', (S, S), 0)
        ImageDraw.Draw(sock).polygon(pts, fill=255)
        sock = sock.filter(ImageFilter.GaussianBlur(9))
        img.paste((6, 2, 4, 255), (0, 0), sock)
        glow = Image.new('L', (S, S), 0)
        ImageDraw.Draw(glow).ellipse([x - 26, y - 6, x + 26, y + 40], fill=255)
        glow = glow.filter(ImageFilter.GaussianBlur(18))
        img.paste((255, 40, 20, 255), (0, 0), glow)
        d.ellipse([x - 11, y + 8, x + 11, y + 30], fill=(255, 230, 200, 255))
    # The nose: a dark upside-down heart.
    d.polygon([(S * 0.5, S * 0.52), (S * 0.465, S * 0.6), (S * 0.5, S * 0.585), (S * 0.535, S * 0.6)], fill=(10, 4, 6, 255))
    # A screaming mouth, wide open, with long jagged teeth.
    mouth = [(S * 0.37, S * 0.66), (S * 0.63, S * 0.66), (S * 0.6, S * 0.85), (S * 0.5, S * 0.88), (S * 0.4, S * 0.85)]
    d.polygon(mouth, fill=(4, 1, 2, 255))
    for i in range(8):
        x = S * (0.385 + i * 0.033) + R.uniform(-5, 5)
        w = S * R.uniform(0.022, 0.032)
        d.polygon([(x, S * 0.655), (x + w, S * 0.655), (x + w * R.uniform(0.3, 0.7), S * (0.70 + R.uniform(0, 0.07)))], fill=(222, 214, 196, 255))
    for i in range(7):
        x = S * (0.40 + i * 0.03) + R.uniform(-5, 5)
        w = S * R.uniform(0.02, 0.03)
        d.polygon([(x, S * 0.865), (x + w, S * 0.865), (x + w * R.uniform(0.3, 0.7), S * (0.79 - R.uniform(0, 0.05)))], fill=(196, 186, 170, 255))
    # Cracks over the bone.
    for _ in range(9):
        x, y = S * R.uniform(0.33, 0.67), S * R.uniform(0.2, 0.36)
        pts = [(x, y)]
        for _ in range(R.randint(4, 8)):
            x += R.uniform(-28, 28)
            y += R.uniform(8, 30)
            pts.append((x, y))
        d.line(pts, fill=(60, 40, 40, 255), width=R.randint(3, 6))
    # Red drips from the eyes.
    for cx in (0.4, 0.6):
        for k in range(2):
            x = S * cx + R.uniform(-30, 30)
            d.line([(x, S * 0.5), (x + R.uniform(-6, 6), S * R.uniform(0.6, 0.7))], fill=(150, 10, 12, 230), width=7)
    return img.resize((512, 512), Image.LANCZOS)


def eye():
    W, H = 1024, 640
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    lid = Image.new('L', (W, H), 0)
    ImageDraw.Draw(lid).ellipse([60, 120, W - 60, H - 120], fill=255)
    lid = lid.filter(ImageFilter.GaussianBlur(10))
    # A dark smear around it (painted on the wall).
    smear = lid.filter(ImageFilter.GaussianBlur(60))
    img.paste((0, 0, 0, 230), (0, 0), smear)
    white = Image.new('RGBA', (W, H), (226, 220, 210, 255))
    img.paste(white, (0, 0), lid)
    d = ImageDraw.Draw(img)
    # Veins.
    for _ in range(26):
        a = R.uniform(0, math.tau)
        x, y = W / 2 + math.cos(a) * 380, H / 2 + math.sin(a) * 170
        pts = [(x, y)]
        for _ in range(6):
            x += (W / 2 - x) * 0.18 + R.uniform(-20, 20)
            y += (H / 2 - y) * 0.18 + R.uniform(-12, 12)
            pts.append((x, y))
        d.line(pts, fill=(170, 30, 30, 200), width=R.randint(2, 5))
    # Iris and pupil.
    cx, cy = W / 2 + 20, H / 2
    d.ellipse([cx - 150, cy - 150, cx + 150, cy + 150], fill=(30, 26, 22, 255))
    d.ellipse([cx - 120, cy - 120, cx + 120, cy + 120], fill=(70, 60, 50, 255))
    d.ellipse([cx - 62, cy - 62, cx + 62, cy + 62], fill=(0, 0, 0, 255))
    d.ellipse([cx - 52, cy - 70, cx - 22, cy - 40], fill=(255, 255, 255, 220))
    # Keep only what's on the eye and the smear.
    return img.resize((512, 320), Image.LANCZOS)


skull().save(os.path.join(here, 'assets', 'howl.png'))
eye().save(os.path.join(here, 'assets', 'eye.png'))
print('drawn')
