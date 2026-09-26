"""Writes server/src/accessories.json, the accessory catalog the app and the website
draw from. Edit this (or the JSON directly) to add accessories; no app update needed.

Coordinates are melly.glb model units relative to the bone (Head or Torso),
+Y up, +Z Melly's front. Head: box x ±0.69, z ±0.67, y 0..1.33 above the bone.
Torso: y 0..2.0 above the bone (hips), z ±0.4 (front/back)."""
import json, math, os

TOP = 1.33

def part(shape, pos, color, rot=None, **kw):
    p = {"shape": shape, "pos": [round(v, 3) for v in pos], "color": color}
    if rot: p["rot"] = rot
    p.update(kw)
    return p

def ext(outline, pos, color, depth=0.1, bevel=0.03, rot=None, **kw):
    """An outline (x, y) pushed out along z, with a rounded edge."""
    return part("extrude", pos, color, rot=rot, outline=[[round(x, 3), round(y, 3)] for x, y in outline],
                depth=depth, bevel=bevel, **kw)

def chaikin(pts, rounds=3):
    """Rounds the corners of a closed polygon by cutting them (Chaikin's algorithm)."""
    for _ in range(rounds):
        out = []
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        pts = out
    return pts

def heart(w, steps=48):
    """The classic heart curve, `w` wide, centered."""
    pts = []
    for i in range(steps):
        t = math.tau * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x * w / 34, (y + 2.5) * w / 34))
    return pts

def ellipse(rx, ry, steps=24):
    return [(rx * math.cos(math.tau * i / steps), ry * math.sin(math.tau * i / steps)) for i in range(steps)]

def rounded_rect(w, h, r, steps=5):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

items = []

# --- hats ------------------------------------------------------------------------
items.append({"id": "cap", "name": {"en": "Cap", "ru": "Кепка"}, "slot": "hat", "bone": "Head", "parts": [
    part("sphere", [0, TOP - 0.2, 0], "#ff6b6b", r=0.74, h=0.8, half=True),
    part("box", [0, TOP - 0.17, 0.85], "#ff6b6b", rot=[-6, 0, 0], size=[1.1, 0.07, 0.6]),
    part("sphere", [0, TOP + 0.2, 0], "#f4f1ec", r=0.08, h=0.16),
]})

crown = [part("cylinder", [0, TOP + 0.12, 0], "#ffd166", top=0.5, bottom=0.47, h=0.28, rough=0.3, metal=0.8)]
gems = ["#ff6b6b", "#4cc9f0", "#7ee0c3", "#e056fd", "#ff8fb1"]
for i in range(5):
    a = math.tau * i / 5
    d = (math.sin(a), 0, math.cos(a))
    crown.append(part("prism", [d[0] * 0.47, TOP + 0.4, d[2] * 0.47], "#ffd166", rot=[0, round(math.degrees(a), 2), 0], size=[0.22, 0.3, 0.08], rough=0.3, metal=0.8))
    crown.append(part("sphere", [d[0] * 0.51, TOP + 0.12, d[2] * 0.51], gems[i], r=0.06, h=0.12, rough=0.2, glow=0.6))
items.append({"id": "crown", "name": {"en": "Crown", "ru": "Корона"}, "slot": "hat", "bone": "Head", "parts": crown})

items.append({"id": "tophat", "name": {"en": "Top hat", "ru": "Цилиндр"}, "slot": "hat", "bone": "Head", "rot": [0, 0, -6], "parts": [
    part("cylinder", [0, TOP + 0.03, 0], "#1f1c27", top=0.82, bottom=0.82, h=0.06, rough=0.5),
    part("cylinder", [0, TOP + 0.48, 0], "#1f1c27", top=0.5, bottom=0.46, h=0.85, rough=0.5),
    part("cylinder", [0, TOP + 0.16, 0], "#b89cff", top=0.475, bottom=0.47, h=0.14),
]})

items.append({"id": "halo", "name": {"en": "Halo", "ru": "Нимб"}, "slot": "halo", "bone": "Head", "parts": [
    part("torus", [0, TOP + 0.45, 0], "#fff3b0", inner=0.42, outer=0.55, rough=0.2, glow=2.2, shadow=False,
         anim={"type": "bob", "amp": 0.13, "period": 2.4}),
]})

# --- ears, hair --------------------------------------------------------------------
ears = []
for side in (-1, 1):
    x = side * 0.42
    ears.append(part("prism", [x, TOP + 0.2, -0.05], "#433d4f", rot=[0, 0, -side * 14], size=[0.5, 0.55, 0.2]))
    ears.append(part("prism", [x + side * 0.02, TOP + 0.16, 0.06], "#ff8fb1", rot=[0, 0, -side * 14], size=[0.3, 0.34, 0.06]))
items.append({"id": "catears", "name": {"en": "Cat ears", "ru": "Кошачьи ушки"}, "slot": "ears", "bone": "Head", "parts": ears})

phones = [part("torus", [0, 0.62, 0], "#2e2940", rot=[90, 0, 0], inner=0.72, outer=0.82, rough=0.4)]
for side in (-1, 1):
    phones.append(part("cylinder", [side * 0.78, 0.62, 0], "#2e2940", rot=[0, 0, 90], top=0.26, bottom=0.26, h=0.2, rough=0.4))
    phones.append(part("cylinder", [side * 0.8, 0.62, 0], "#7ee0c3", rot=[0, 0, 90], top=0.18, bottom=0.18, h=0.22))
items.append({"id": "headphones", "name": {"en": "Headphones", "ru": "Наушники"}, "slot": "ears", "bone": "Head", "parts": phones})

flower = [part("sphere", [math.cos(math.tau * i / 5) * 0.17, 0, math.sin(math.tau * i / 5) * 0.17], "#ff8fb1", r=0.16, h=0.12) for i in range(5)]
flower.append(part("sphere", [0, 0.04, 0], "#ffd166", r=0.12, h=0.18))
items.append({"id": "flower", "name": {"en": "Flower", "ru": "Цветочек"}, "slot": "hair", "bone": "Head", "parts": [
    {"shape": "group", "pos": [0.5, TOP - 0.05, 0.25], "rot": [20, 0, -35], "parts": flower},
]})

# --- back ------------------------------------------------------------------------
# Cat tail: one smooth tapering tube in the ears' fur color, from the lower back:
# out and slightly down first, then curving up with the tip hooked a little.
# "tube": a curve through `points` with `r` at the base narrowing to `r_end`.
items.append({"id": "cattail", "name": {"en": "Cat tail", "ru": "Кошачий хвост"}, "slot": "back", "bone": "Torso", "parts": [
    {"shape": "group", "pos": [0, 0.3, -0.36], "anim": {"type": "sway", "axis": "y", "deg": 12, "period": 2.2}, "parts": [
        part("tube", [0, 0, 0], "#433d4f", r=0.1, r_end=0.065, points=[
            [0, 0, 0], [0, -0.12, -0.35], [0, -0.1, -0.75], [0, 0.2, -1.05],
            [0, 0.65, -1.15], [0, 1.05, -1.02], [0, 1.25, -0.8],
        ]),
    ]},
]})

# --- more hats, faces, neck, back ---------------------------------------------------
items.append({"id": "partyhat", "name": {"en": "Party hat", "ru": "Праздничный колпак"}, "slot": "hat", "bone": "Head", "rot": [0, 0, 8], "parts": [
    part("cone", [0, TOP + 0.42, 0], "#7ee0c3", bottom=0.36, h=0.85),
    part("torus", [0, TOP + 0.08, 0], "#ff8fb1", inner=0.3, outer=0.4),
    part("sphere", [0, TOP + 0.88, 0], "#ffd166", r=0.12, h=0.24),
]})

items.append({"id": "beanie", "name": {"en": "Beanie", "ru": "Шапка-бини"}, "slot": "hat", "bone": "Head", "parts": [
    part("sphere", [0, TOP - 0.28, 0], "#e05b6f", r=0.78, h=0.8, half=True, rough=0.9),
    part("cylinder", [0, TOP - 0.2, 0], "#c9485d", top=0.79, bottom=0.79, h=0.26, rough=0.9),
    part("sphere", [0, TOP + 0.55, 0], "#f4f1ec", r=0.16, h=0.32, rough=0.95),
]})

items.append({"id": "bunnyears", "name": {"en": "Bunny ears", "ru": "Заячьи ушки"}, "slot": "ears", "bone": "Head", "parts": [
    part("capsule", [side * 0.3, TOP + 0.5, -0.05], "#f4f1ec", rot=[0, 0, -side * 10], r=0.14, h=1.0) for side in (-1, 1)
] + [
    part("capsule", [side * 0.31, TOP + 0.5, 0.06], "#ff8fb1", rot=[0, 0, -side * 10], r=0.08, h=0.8) for side in (-1, 1)
]})

items.append({"id": "horns", "name": {"en": "Little horns", "ru": "Рожки"}, "slot": "halo", "bone": "Head", "parts": [
    part("cone", [side * 0.4, TOP + 0.18, 0.1], "#d94f5c", rot=[0, 0, -side * 22], bottom=0.14, h=0.42, rough=0.4) for side in (-1, 1)
]})

items.append({"id": "sunglasses", "name": {"en": "Sunglasses", "ru": "Солнечные очки"}, "slot": "face", "bone": "Head", "parts": [
    part("box", [-0.3, 0.78, 0.7], "#15131c", size=[0.46, 0.26, 0.05], rough=0.15, metal=0.4),
    part("box", [0.3, 0.78, 0.7], "#15131c", size=[0.46, 0.26, 0.05], rough=0.15, metal=0.4),
    part("box", [0, 0.84, 0.7], "#15131c", size=[0.2, 0.05, 0.05]),
    part("box", [-0.68, 0.84, 0.35], "#15131c", size=[0.04, 0.05, 0.7]),
    part("box", [0.68, 0.84, 0.35], "#15131c", size=[0.04, 0.05, 0.7]),
]})

hearts = []
for side in (-1, 1):
    cx = side * 0.31
    # A glossy pink heart lens in a thin darker rim, with a little shine.
    hearts.append(ext(heart(0.5), [cx, 0.79, 0.69], "#c2185b", depth=0.05, bevel=0.02, rough=0.35))
    hearts.append(ext(heart(0.42), [cx, 0.8, 0.715], "#ff5c95", depth=0.04, bevel=0.018, rough=0.12, glow=0.25))
    hearts.append(ext(ellipse(0.055, 0.035), [cx - 0.07, 0.88, 0.735], "#ffe3ee", rot=[0, 0, 30], depth=0.012, bevel=0.005, rough=0.1, glow=0.4))
    hearts.append(part("box", [side * 0.66, 0.86, 0.36], "#c2185b", size=[0.035, 0.045, 0.66], rough=0.35))
hearts.append(ext(chaikin([(-0.09, 0.0), (0.0, 0.035), (0.09, 0.0), (0.09, -0.03), (0.0, 0.005), (-0.09, -0.03)], 2), [0, 0.87, 0.705], "#c2185b", depth=0.04, bevel=0.012, rough=0.35))
items.append({"id": "heartglasses", "name": {"en": "Heart glasses", "ru": "Очки-сердечки"}, "slot": "face", "bone": "Head", "parts": hearts})


def neck_loop(y, rx, rz, tilt):
    """A ring of points round the neck (a little overlap hides the tube's ends)."""
    pts = []
    for i in range(15):
        a = math.tau * i / 14 + 0.3
        pts.append([round(rx * math.sin(a), 3), round(y + tilt * math.cos(a), 3), round(rz * math.cos(a), 3)])
    return pts

scarf = [
    # two soft knitted rolls wrapped round the neck
    part("tube", [0, 0, 0], "#3fb6e8", points=neck_loop(1.93, 0.6, 0.5, 0.05), r=0.15, rough=0.95),
    part("tube", [0, 0, 0], "#4cc9f0", points=neck_loop(1.79, 0.64, 0.53, -0.04), r=0.14, rough=0.95),
]
for x, top, length, tilt, z in ((0.2, 1.72, 0.8, 7, 0.52), (0.38, 1.7, 0.64, -5, 0.46)):
    # Hanging ends: a strip with two white stripes and a fringe, in its own group so it tilts as one.
    end = [ext(rounded_rect(0.26, length, 0.06), [0, -length / 2, 0], "#4cc9f0", depth=0.07, bevel=0.03, rough=0.95)]
    for k in (0.62, 0.76):
        end.append(ext(rounded_rect(0.272, 0.05, 0.02), [0, -length * k, 0], "#f4f1ec", depth=0.078, bevel=0.03, rough=0.95))
    for f in range(5):
        end.append(part("capsule", [-0.1 + f * 0.05, -length - 0.04, 0], "#f4f1ec", r=0.018, h=0.12, rough=0.95))
    scarf.append({"shape": "group", "pos": [x, top, z], "rot": [-10, 0, tilt], "parts": end})
items.append({"id": "scarf", "name": {"en": "Scarf", "ru": "Шарф"}, "slot": "neck", "bone": "Torso", "parts": scarf})


def bow_lobe(side):
    """One wing of the bow: narrow at the knot, wide and rounded at the end."""
    raw = [(0.05, 0.07), (0.18, 0.13), (0.31, 0.17), (0.37, 0.1), (0.38, 0.0), (0.37, -0.1), (0.31, -0.17), (0.18, -0.13), (0.05, -0.07)]
    return [(side * x, y) for x, y in chaikin(raw, 3)]

def crease(side, up):
    raw = [(0.08, 0.015 * up), (0.26, 0.07 * up), (0.27, 0.05 * up), (0.08, 0.0)]
    return [(side * x, y) for x, y in chaikin(raw, 2)]

bow = []
for side in (-1, 1):
    bow.append(ext(bow_lobe(side), [0, 0, 0], "#e0445f", rot=[0, side * 12, 0], depth=0.11, bevel=0.04, rough=0.55))
    for up in (1, -1):
        bow.append(ext(crease(side, up), [0, 0, 0.045], "#b8324b", rot=[0, side * 12, 0], depth=0.03, bevel=0.01, rough=0.6))
bow.append(ext(rounded_rect(0.14, 0.17, 0.05), [0, 0, 0.03], "#c23a53", depth=0.15, bevel=0.05, rough=0.55))
items.append({"id": "bowtie", "name": {"en": "Bow tie", "ru": "Бабочка"}, "slot": "neck", "bone": "Torso",
              "parts": [{"shape": "group", "pos": [0, 1.8, 0.46], "parts": bow}]})


def wing_outline(scale, feathers=7, depth=1.0):
    """An angel wing seen from behind, root at (0, 0), spreading out along +x:
    a curved leading edge up top and a row of rounded feather ends below, the
    longest ones out at the tip. `depth` scales how far the feathers hang."""
    top = [(0.0, 0.08), (0.2, 0.32), (0.55, 0.55), (0.92, 0.66), (1.2, 0.64), (1.36, 0.52)]
    pts = list(top)
    # the line the feathers hang from, tip back to root
    def base(t):
        return 1.36 - 1.2 * t, 0.46 - 0.62 * t
    for k in range(feathers):
        t0, t1 = k / feathers, (k + 1) / feathers
        ax, ay = base(t0)
        bx, by = base(t1)
        length = depth * (0.5 - 0.3 * (k / (feathers - 1)))
        # a feather: down one side, a round end, back up the other
        dx, dy = 0.28, -1.0  # hanging a little outward
        dl = math.hypot(dx, dy)
        dx, dy = dx / dl, dy / dl
        mx, my = (ax + bx) / 2, (ay + by) / 2
        half = math.hypot(bx - ax, by - ay) / 2 * 1.08
        ux, uy = (ax - bx) / (2 * half), (ay - by) / (2 * half)
        for q in range(9):
            a = math.pi * q / 8
            # from the tip side (a=0) round the end to the root side (a=pi)
            r = half
            cx, cy = mx + dx * length, my + dy * length
            pts.append((cx + ux * r * math.cos(a) + dx * r * math.sin(a), cy + uy * r * math.cos(a) + dy * r * math.sin(a)))
    pts.append((0.02, -0.08))
    return [(x * scale, y * scale) for x, y in chaikin(pts, 2)]

def wing(side):
    """Long flight feathers at the back, a shorter lighter row over them, and a
    rounded bone along the top; the whole wing flaps gently."""
    flip = lambda pts: [(side * x, y) for x, y in pts]
    bone = [[side * x * 1.35, y * 1.35, 0.02] for x, y in ((0.0, 0.06), (0.3, 0.36), (0.7, 0.58), (1.05, 0.66), (1.32, 0.58))]
    return {"shape": "group", "pos": [side * 0.2, 1.5, -0.5], "rot": [0, -side * 28, side * 14],
            "anim": {"type": "sway", "axis": "y", "deg": 8, "period": 1.8}, "parts": [
                ext(flip(wing_outline(1.35)), [0, 0, 0], "#e7defc", depth=0.05, bevel=0.022, rough=0.6, glow=0.06),
                ext(flip(wing_outline(1.35, feathers=6, depth=0.45)), [0, 0.02, -0.04], "#f6f2ff", depth=0.05, bevel=0.022, rough=0.6, glow=0.08),
                ext(flip(wing_outline(1.35, feathers=5, depth=0.12)), [0, 0.04, -0.08], "#ffffff", depth=0.05, bevel=0.022, rough=0.6, glow=0.1),
                part("tube", [0, 0, -0.06], "#ffffff", points=bone, r=0.075, r_end=0.04, rough=0.6, glow=0.1),
            ]}
items.append({"id": "wings", "name": {"en": "Angel wings", "ru": "Крылья"}, "slot": "back", "bone": "Torso", "parts": [wing(-1), wing(1)]})

items.append({"id": "backpack", "name": {"en": "Backpack", "ru": "Рюкзак"}, "slot": "back", "bone": "Torso", "parts": [
    part("box", [0, 1.15, -0.62], "#ffb35c", size=[1.0, 1.1, 0.45], rough=0.85),
    part("box", [0, 1.62, -0.6], "#e8952f", size=[1.02, 0.28, 0.5], rough=0.85),
    part("box", [0, 0.95, -0.87], "#e8952f", size=[0.6, 0.4, 0.1], rough=0.85),
]})

# Prices: every item costs pieces (bought with money, 1 piece is about 1 rouble);
# the everyday ones can be taken for orbs (earned by playing) instead. Buyer picks.
PRICES = {
    "cap": {"pieces": 15, "orbs": 250}, "flower": {"pieces": 12, "orbs": 200},
    "headphones": {"pieces": 25, "orbs": 450}, "catears": {"pieces": 29, "orbs": 500},
    "partyhat": {"pieces": 15, "orbs": 300}, "beanie": {"pieces": 19, "orbs": 400},
    "scarf": {"pieces": 19, "orbs": 350}, "bowtie": {"pieces": 12, "orbs": 250},
    "heartglasses": {"pieces": 25, "orbs": 450}, "backpack": {"pieces": 35, "orbs": 600},
    "tophat": {"pieces": 35}, "crown": {"pieces": 99}, "halo": {"pieces": 79}, "cattail": {"pieces": 49},
    "sunglasses": {"pieces": 29}, "wings": {"pieces": 129}, "bunnyears": {"pieces": 45}, "horns": {"pieces": 59},
}
for it in items:
    it["price"] = PRICES[it["id"]]

catalog = {
    "version": 2,
    "max_worn": 4,
    "slots": ["hat", "halo", "ears", "hair", "face", "neck", "back"],
    "items": items,
}
out = os.path.join(os.path.dirname(__file__), "..", "server", "src", "accessories.json")
with open(out, "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=1)
    f.write("\n")
print("wrote", out, len(items), "items")
