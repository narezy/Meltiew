#!/usr/bin/env python3
"""Builds examples/monkeytag.melt: Monkey Tag, tag played with your arms in VR.

    python3 build.py              # writes ../monkeytag.melt

A jungle clearing generated here from parts (seeded, so every build is the same). The
game is in the .luau files next to this script: Hands.luau moves players by their arms
(VRService hand positions + raycasts + the character's AssemblyLinearVelocity), so any
place can copy it and change how it feels; Server.luau runs the rounds of tag.
"""
import json
import math
import os
import random

here = os.path.dirname(os.path.abspath(__file__))
R = random.Random(20261002)


def src(name):
    with open(os.path.join(here, name), encoding='utf-8') as f:
        return f.read()


def v3(x, y, z):
    return {'$v3': [round(x, 3), round(y, 3), round(z, 3)]}


def c3(h):
    return {'$c3': h}


def part(name, size, pos, color, mat='Plastic', rot=(0, 0, 0), shape=None, shadow=True):
    p = {'Size': v3(*size), 'Position': v3(*pos), 'Color': c3(color), 'Material': mat}
    if any(abs(r) > 1e-6 for r in rot):
        p['Rotation'] = v3(*rot)
    if shape:
        p['Shape'] = shape
    if not shadow:
        p['CastShadow'] = False
    return {'c': 'Part', 'n': name, 'p': p}


def model(name, kids):
    return {'c': 'Model', 'n': name, 'k': kids}


BARK = ['#5b3f2a', '#654631', '#4f3624']
LEAVES = ['#2f7a3a', '#3a8a40', '#2a6b35', '#46944a']
ROCK = ['#7d7a82', '#6c6972', '#8a8690']
RADIUS = 46  # the clearing

world = []

# The ground, and a ring of rock walls around it (good for climbing out of reach).
world.append(part('Ground', (RADIUS * 2 + 6, 2, RADIUS * 2 + 6), (0, -1, 0), '#4c8a3c', 'Grass', shape='Cylinder'))
walls = []
n = 28
for i in range(n):
    a = i / n * math.tau
    h = R.uniform(7, 12)
    w = 2 * math.pi * RADIUS / n + 1.2
    walls.append(part('Rock%d' % i, (w, h, R.uniform(3, 5)), (math.sin(a) * RADIUS, h / 2 - 0.5, math.cos(a) * RADIUS),
                      R.choice(ROCK), 'Concrete', rot=(R.uniform(-4, 4), math.degrees(a), R.uniform(-3, 3))))
world.append(model('Walls', walls))

# Trees: a trunk, branches sticking out to hang from, and a canopy of leaf balls on top.
trees = []
spots = []
for i in range(11):
    for _ in range(50):
        a = R.uniform(0, math.tau)
        d = R.uniform(10, RADIUS - 8)
        x, z = math.sin(a) * d, math.cos(a) * d
        if all(math.hypot(x - sx, z - sz) > 9 for sx, sz in spots):
            break
    spots.append((x, z))
    h = R.uniform(14, 22)
    w = R.uniform(2.4, 3.4)
    kids = [part('Trunk', (w, h, w), (x, h / 2, z), R.choice(BARK), 'Wood', shape='Cylinder')]
    for b in range(R.randint(2, 4)):
        ang = R.uniform(0, 360)
        y = R.uniform(4, h - 4)
        length = R.uniform(4, 7)
        dx, dz = math.sin(math.radians(ang)), math.cos(math.radians(ang))
        kids.append(part('Branch%d' % b, (1.1, 0.8, length), (x + dx * (length / 2 + w / 2 - 0.3), y, z + dz * (length / 2 + w / 2 - 0.3)),
                         R.choice(BARK), 'Wood', rot=(R.uniform(-12, 6), ang, 0)))
    for l in range(3):
        s = R.uniform(7, 11)
        kids.append(part('Leaves%d' % l, (s, s, s), (x + R.uniform(-2.5, 2.5), h + R.uniform(-1, 2.5), z + R.uniform(-2.5, 2.5)),
                         R.choice(LEAVES), 'Grass', shape='Ball'))
    trees.append(model('Tree%d' % i, kids))
world.append(model('Trees', trees))

# A log bridge between two trees, and boulders to bounce off.
(ax, az), (bx, bz) = spots[0], spots[1]
mx, mz = (ax + bx) / 2, (az + bz) / 2
length = math.hypot(bx - ax, bz - az)
yaw = math.degrees(math.atan2(bx - ax, bz - az))
world.append(part('LogBridge', (1.6, length, 1.6), (mx, 9, mz), BARK[0], 'Wood', rot=(90, yaw, 0), shape='Cylinder'))
rocks = []
for i in range(9):
    a = R.uniform(0, math.tau)
    d = R.uniform(6, RADIUS - 6)
    s = R.uniform(3, 6.5)
    rocks.append(part('Boulder%d' % i, (s, s, s), (math.sin(a) * d, s * 0.3, math.cos(a) * d), R.choice(ROCK), 'Concrete', shape='Ball'))
world.append(model('Boulders', rocks))

# A hut up on stilts near the middle: a roof to run across, walls to climb.
hx, hz = 6, -9
hut = [
    part('Floor', (8, 0.6, 8), (hx, 4, hz), '#8a6a45', 'Wood'),
    part('WallBack', (8, 4, 0.5), (hx, 6.3, hz - 3.75), '#7a5a3a', 'Wood'),
    part('WallLeft', (0.5, 4, 8), (hx - 3.75, 6.3, hz), '#7a5a3a', 'Wood'),
    part('WallRight', (0.5, 4, 8), (hx + 3.75, 6.3, hz), '#7a5a3a', 'Wood'),
    part('Roof', (9.5, 0.6, 9.5), (hx, 8.6, hz), '#5d7f3a', 'Grass'),
]
for i, (sx, sz) in enumerate([(-3.5, -3.5), (3.5, -3.5), (-3.5, 3.5), (3.5, 3.5)]):
    hut.append(part('Stilt%d' % i, (0.6, 4, 0.6), (hx + sx, 2, hz + sz), BARK[1], 'Wood'))
world.append(model('Hut', hut))

# Where you start: a tree stump, and the title and how to play on a board behind it.
world.append({'c': 'SpawnLocation', 'n': 'Stump', 'p': {'Position': v3(0, 0.3, 0), 'Size': v3(4, 0.6, 4),
                                                        'Color': c3('#6b4a2b'), 'Material': 'Wood', 'Shape': 'Cylinder'}})
world.append(part('Board', (12, 5, 0.4), (0, 3.5, 7), '#3b2a1c', 'Wood'))
for name, text, y, size, color in [('Title', '$title', 5, 96, '#ffd36b'), ('Hint', '$hint', 3.2, 28, '#f4f1ec')]:
    world.append({'c': 'Text3D', 'n': name, 'p': {'Text': text, 'Position': v3(0, y, 6.75), 'Rotation': v3(0, 180, 0),
                                                 'TextColor': c3(color), 'TextSize': size, 'Font': 'Black'}})

status_gui = {
    'c': 'ScreenGui', 'n': 'Status',
    'k': [{
        'c': 'TextLabel', 'n': 'Label',
        'p': {'Text': '', 'Position': {'$u2': [0.5, -260, 0, 14]}, 'Size': {'$u2': [0, 520, 0, 40]},
              'BackgroundTransparency': 0.35, 'BackgroundColor': c3('#16141d'), 'TextColor': c3('#f4f1ec'),
              'TextSize': 20, 'Font': 'Black', 'TextWrapped': True},
        'k': [{'c': 'UICorner', 'n': 'UICorner', 'p': {'CornerRadius': 14}}],
    }],
}

with open(os.path.join(here, 'strings.json'), encoding='utf-8') as f:
    strings = json.load(f)

melt = {
    'format': 'melt',
    'version': 1,
    'meta': {
        'name': 'Monkey Tag VR',
        'description': 'Tag in VR, played with your arms: no legs, no stick. Slap the ground to jump, pull on trees to climb, fly. One monkey is lava; whoever lava touches turns lava too. VR headset needed.',
        'i18n': {
            'name': {'ru': 'Обезьяньи салки VR'},
            'description': {'ru': 'Салки в ВР, где двигаешься руками: ни ног, ни стика. Толкни землю, чтобы прыгнуть, тяни деревья, чтобы лезть, лети. Одна обезьянка в лаве, кого она коснётся, тоже становится лавой. Нужен ВР-шлем.'},
        },
    },
    'strings': strings,
    'tree': {
        'c': 'DataModel',
        'k': [
            {'c': 'Workspace', 'n': 'Workspace', 'p': {'Gravity': 16, 'FallHeight': -30}, 'k': world},
            {'c': 'Lighting', 'n': 'Lighting', 'p': {'ClockTime': 15, 'FogEnabled': True, 'FogEnd': 160, 'FogColor': c3('#b9d8a8')},
             'k': [{'c': 'Sky', 'n': 'Sky'}]},
            {'c': 'ReplicatedStorage', 'n': 'ReplicatedStorage', 'k': [
                {'c': 'StringValue', 'n': 'State', 'p': {'Value': 'waiting'}},
                {'c': 'IntValue', 'n': 'Countdown'},
                {'c': 'RemoteEvent', 'n': 'Tag'},
            ]},
            {'c': 'ServerScriptService', 'n': 'ServerScriptService', 'k': [
                {'c': 'Script', 'n': 'Game', 'p': {'Source': src('Server.luau')}},
            ]},
            {'c': 'ServerStorage', 'n': 'ServerStorage', 'k': [
                {'c': 'Appearance', 'n': 'LavaLook', 'p': {
                    'HeadColor': c3('#ff7a2e'), 'TorsoColor': c3('#e2401c'), 'LeftArmColor': c3('#ff7a2e'),
                    'RightArmColor': c3('#ff7a2e'), 'LeftLegColor': c3('#b8321a'), 'RightLegColor': c3('#b8321a'),
                    'KeepFace': True, 'KeepAccessories': True}},
            ]},
            {'c': 'Teams', 'n': 'Teams', 'k': [
                {'c': 'Team', 'n': 'Monkeys', 'p': {'TeamColor': c3('#6cbf49'), 'AutoAssignable': True}},
                {'c': 'Team', 'n': 'Lava', 'p': {'TeamColor': c3('#ff5a1f'), 'AutoAssignable': False}},
            ]},
            {'c': 'StarterGui', 'n': 'StarterGui', 'k': [status_gui]},
            # Moving by hand flies about too freely for the usual movement check.
            {'c': 'StarterPlayer', 'n': 'StarterPlayer', 'p': {'AntiCheat': False, 'EmotesEnabled': False, 'CameraMaxZoom': 14},
             'k': [{'c': 'StarterPlayerScripts', 'n': 'StarterPlayerScripts', 'k': [
                 {'c': 'LocalScript', 'n': 'Hands', 'p': {'Source': src('Hands.luau')}},
                 {'c': 'LocalScript', 'n': 'Status', 'p': {'Source': src('Status.luau')}},
             ]}]},
        ],
    },
}

out = os.path.join(here, '..', 'monkeytag.melt')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(melt, f, ensure_ascii=False, indent=1)
print('wrote', os.path.normpath(out))
