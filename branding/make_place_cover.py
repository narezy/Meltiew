"""Default cover for studio places without their own: a gradient with soft
floating blocks and the wordmark. Writes server/public/img/place-cover.png."""
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 800, 450
TOP, BOTTOM = (139, 108, 239), (190, 122, 204)

img = Image.new("RGB", (W, H))
px = ImageDraw.Draw(img)
for y in range(H):
    t = y / (H - 1)
    px.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

rng = random.Random(7)
blocks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(blocks)
for _ in range(16):
    s = rng.randint(34, 96)
    x, y = rng.randint(-20, W - 20), rng.randint(-20, H - 20)
    # Keep the middle clear for the wordmark.
    if 170 < x + s / 2 < 630 and 150 < y + s / 2 < 330:
        continue
    d.rounded_rectangle([x, y, x + s, y + s], radius=s // 4, fill=(255, 255, 255, rng.randint(28, 60)))
blocks = blocks.filter(ImageFilter.GaussianBlur(1.2))
img = Image.alpha_composite(img.convert("RGBA"), blocks)

font = "client/assets/fonts/Nunito.ttf"
draw = ImageDraw.Draw(img)
big = ImageFont.truetype(font, 112)
big.set_variation_by_axes([900])
small = ImageFont.truetype(font, 40)
small.set_variation_by_axes([800])
for text, f, y, a in [("meltiew", big, 205, 255), ("studio", small, 300, 210)]:
    w = draw.textlength(text, font=f)
    draw.text(((W - w) / 2, y), text, font=f, fill=(255, 255, 255, a), anchor="ls")
img.convert("RGB").save("server/public/img/place-cover.png", optimize=True)
