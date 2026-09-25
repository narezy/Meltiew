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
    ears.append(part("prism", [x, TOP + 0.2, -0.05], "#302d38", rot=[0, 0, -side * 14], size=[0.5, 0.55, 0.2]))
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
# Cat tail: from the lower back, out and curling up, dark with a pink tip; it sways.
def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return [u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d for a, b, c, d in zip(p0, p1, p2, p3)]
tail = []
n = 16
for i in range(n):
    t = i / (n - 1)
    p = bezier([0, 0.45, -0.38], [0, 0.1, -1.1], [0, 1.0, -1.45], [0.12, 1.55, -1.05], t)
    r = 0.15 - 0.05 * t
    tail.append(part("sphere", p, "#ff8fb1" if i >= n - 2 else "#302d38", r=round(r, 3), h=round(r * 2, 3)))
items.append({"id": "cattail", "name": {"en": "Cat tail", "ru": "Кошачий хвост"}, "slot": "back", "bone": "Torso", "parts": [
    {"shape": "group", "pos": [0, 0.45, -0.38], "anim": {"type": "sway", "axis": "y", "deg": 14, "period": 1.8},
     "parts": [dict(p, pos=[round(p["pos"][0], 3), round(p["pos"][1] - 0.45, 3), round(p["pos"][2] + 0.38, 3)]) for p in tail]},
]})

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
