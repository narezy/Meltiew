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
    cx = side * 0.3
    hearts.append(part("sphere", [cx - 0.08, 0.83, 0.71], "#ff5c8a", r=0.13, h=0.1, glow=0.3))
    hearts.append(part("sphere", [cx + 0.08, 0.83, 0.71], "#ff5c8a", r=0.13, h=0.1, glow=0.3))
    hearts.append(part("prism", [cx, 0.68, 0.71], "#ff5c8a", rot=[0, 0, 180], size=[0.37, 0.24, 0.1], glow=0.3))
hearts.append(part("box", [0, 0.84, 0.7], "#ff8fb1", size=[0.14, 0.04, 0.04]))
items.append({"id": "heartglasses", "name": {"en": "Heart glasses", "ru": "Очки-сердечки"}, "slot": "face", "bone": "Head", "parts": hearts})

items.append({"id": "scarf", "name": {"en": "Scarf", "ru": "Шарф"}, "slot": "neck", "bone": "Torso", "parts": [
    part("torus", [0, 1.93, 0], "#4cc9f0", inner=0.42, outer=0.62, rough=0.95),
    part("box", [0.25, 1.45, 0.47], "#4cc9f0", rot=[0, 0, 6], size=[0.3, 0.8, 0.1], rough=0.95),
    part("box", [0.25, 1.1, 0.48], "#f4f1ec", rot=[0, 0, 6], size=[0.3, 0.1, 0.11], rough=0.95),
]})

items.append({"id": "bowtie", "name": {"en": "Bow tie", "ru": "Бабочка"}, "slot": "neck", "bone": "Torso", "parts": [
    part("prism", [-0.2, 1.82, 0.44], "#e05b6f", rot=[0, 0, 90], size=[0.32, 0.3, 0.1]),
    part("prism", [0.2, 1.82, 0.44], "#e05b6f", rot=[0, 0, -90], size=[0.32, 0.3, 0.1]),
    part("box", [0, 1.82, 0.47], "#c9485d", size=[0.12, 0.14, 0.1]),
]})

def wing(side):
    # Three long feathers fanning out from the shoulder blade, in the back's plane.
    feathers = []
    for ang, length, col in ((25, 1.35, "#f7f4ff"), (55, 1.2, "#efeaff"), (85, 0.95, "#e4dcff")):
        a = math.radians(ang)
        d = (side * math.sin(a), math.cos(a))
        feathers.append(part("capsule", [d[0] * length / 2, d[1] * length / 2, 0], col, rot=[0, 0, -side * ang],
                             r=0.17, h=length, rough=0.5, glow=0.12))
    return {"shape": "group", "pos": [side * 0.28, 1.45, -0.5], "rot": [0, side * 18, 0],
            "anim": {"type": "sway", "axis": "y", "deg": 7, "period": 1.6}, "parts": feathers}
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
