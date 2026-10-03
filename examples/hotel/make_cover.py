#!/usr/bin/env python3
"""Midnight Hotel's covers from a corridor shot (client/tools/hotel_cover.tscn): the Howl's
skull in the doorway, a red glow, darkness at the edges and the title.

    python3 make_cover.py corridor.png      # writes assets/cover_wide.jpg, assets/cover_square.jpg
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

here = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(here, '..', '..', 'client', 'assets', 'fonts', 'Nunito.ttf')


def font(size, weight='Black'):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def compose(base, skull_center, skull_h, title_size, title_y):
    W, H = base.size
    img = ImageEnhance.Brightness(base).enhance(0.85).convert('RGBA')
    # A red glow where it comes from.
    glow = Image.new('L', (W, H), 0)
    cx, cy = skull_center
    ImageDraw.Draw(glow).ellipse([cx - skull_h * 0.75, cy - skull_h * 0.7, cx + skull_h * 0.75, cy + skull_h * 0.7], fill=200)
    glow = glow.filter(ImageFilter.GaussianBlur(skull_h * 0.25))
    img.paste((200, 20, 16, 255), (0, 0), glow.point(lambda v: int(v * 0.75)))
    skull = Image.open(os.path.join(here, 'assets', 'howl.png')).convert('RGBA')
    skull = skull.resize((skull_h, skull_h), Image.LANCZOS)
    img.alpha_composite(skull, (int(cx - skull_h / 2), int(cy - skull_h / 2)))
    # Dark around the edges.
    vig = Image.new('L', (W, H), 0)
    ImageDraw.Draw(vig).ellipse([-W * 0.15, -H * 0.2, W * 1.15, H * 1.2], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(min(W, H) * 0.18))
    dark = Image.new('RGBA', (W, H), (4, 2, 6, 255))
    img = Image.composite(img, dark, vig)
    # The title, with a shadow.
    d = ImageDraw.Draw(img)
    title = 'MIDNIGHT HOTEL'
    f = font(title_size)
    tw = d.textlength(title, font=f)
    while tw > W * 0.88:  # fits the width
        title_size = int(title_size * 0.94)
        f = font(title_size)
        tw = d.textlength(title, font=f)
    x = (W - tw) / 2
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + 6, title_y + 8), title, font=f, fill=(0, 0, 0, 230))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)))
    d = ImageDraw.Draw(img)
    d.text((x, title_y), title, font=f, fill=(255, 211, 107, 255), stroke_width=max(2, title_size // 30), stroke_fill=(40, 16, 8, 255))
    sub = '100 DOORS'
    fs = font(int(title_size * 0.32), 'Bold')
    sw = d.textlength(sub, font=fs)
    d.text(((W - sw) / 2, title_y + title_size * 1.12), sub, font=fs, fill=(244, 241, 236, 230), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    return img.convert('RGB')


base = Image.open(sys.argv[1]).convert('RGB')
W, H = base.size
wide = compose(base, (W * 0.462, H * 0.45), int(H * 0.42), int(H * 0.13), H * 0.70)
wide.save(os.path.join(here, 'assets', 'cover_wide.jpg'), quality=90)
side = H
sq = base.crop(((W - side) // 2, 0, (W - side) // 2 + side, side))
square = compose(sq, (side * 0.47, side * 0.42), int(side * 0.46), int(side * 0.115), side * 0.72)
square.resize((1024, 1024), Image.LANCZOS).save(os.path.join(here, 'assets', 'cover_square.jpg'), quality=90)
print('covers written')
