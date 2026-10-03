#!/usr/bin/env python3
"""Builds Midnight Hotel: a game of two places.

    python3 build.py                # writes ../hotel_lobby.melt and ../hotel_rooms.melt

The lobby (the game's main place) is built here from parts; the hotel (a sub-place) is
built by its own script as players open its doors. Pictures and sounds are uploads: their
asset://ids go in assets.json ({"Howl": "asset://12", ...}); the two places' ids (for
TeleportService) in places.json ({"lobby": "p...", "hotel": "p..."}). Everything works
with neither, just silent and without the skull. make_images.py and make_audio.py draw
and synthesize the uploads into assets/.
"""
import json
import math
import os
import random

here = os.path.dirname(os.path.abspath(__file__))
R = random.Random(20261003)


def src(name):
    with open(os.path.join(here, name), encoding='utf-8') as f:
        return f.read()


def jload(name, default):
    p = os.path.join(here, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding='utf-8') as f:
        return json.load(f)


ASSETS = jload('assets.json', {})
PLACES = jload('places.json', {})


def v3(x, y, z):
    return {'$v3': [round(x, 3), round(y, 3), round(z, 3)]}


def c3(h):
    return {'$c3': h}


def part(name, size, pos, color, mat='SmoothPlastic', rot=(0, 0, 0), shape=None, collide=True, transp=0.0, kids=None, cls='Part', extra=None):
    p = {'Size': v3(*size), 'Position': v3(*pos), 'Color': c3(color), 'Material': mat}
    if any(abs(r) > 1e-6 for r in rot):
        p['Rotation'] = v3(*rot)
    if shape:
        p['Shape'] = shape
    if not collide:
        p['CanCollide'] = False
    if transp:
        p['Transparency'] = transp
    p.update(extra or {})
    node = {'c': cls, 'n': name, 'p': p}
    if kids:
        node['k'] = kids
    return node


def model(name, kids):
    return {'c': 'Model', 'n': name, 'k': kids}


def light(color, brightness=1.5, rng=16, offset=None):
    p = {'Color': c3(color), 'Brightness': brightness, 'Range': rng}
    if offset:
        p['Offset'] = v3(*offset)
    return {'c': 'PointLight', 'n': 'PointLight', 'p': p}


def text3d(name, text, pos, color='#f2d48a', size=48, rot=(0, 0, 0), font='Black'):
    return {'c': 'Text3D', 'n': name, 'p': {'Text': text, 'Position': v3(*pos), 'Rotation': v3(*rot), 'TextColor': c3(color), 'TextSize': size, 'Font': font, 'OutlineColor': c3('#120d0a')}}


def sound(name, asset, volume=0.6, looped=True, playing=False):
    return {'c': 'Sound', 'n': name, 'p': {'SoundId': ASSETS.get(asset, ''), 'Volume': volume, 'Looped': looped, 'Playing': playing}}


def value(cls, name, v):
    return {'c': cls, 'n': name, 'p': {'Value': v}}


def assets_folder():
    return {'c': 'Folder', 'n': 'Assets', 'k': [value('StringValue', k, ASSETS.get(k, '')) for k in
                                                 ['Howl', 'Eye', 'Door', 'Drawer', 'HowlScream', 'HowlNear', 'Sting', 'Chase', 'Hum', 'Lobby']]}


def config():
    return {'c': 'Folder', 'n': 'Config', 'k': [value('StringValue', 'LobbyPlaceId', PLACES.get('lobby', '')), value('StringValue', 'HotelPlaceId', PLACES.get('hotel', ''))]}


# --------------------------------------------------------------------------------------
# The lobby
# --------------------------------------------------------------------------------------

W, L, HT = 44.0, 36.0, 14.0  # the hall: x from -22 to 22, z from 18 (front) to -18 (back)
MARBLE = ['#e9e2d6', '#2b2630']
GOLD = '#c9a14a'
WALLC = '#3b2a3a'
WOOD = '#4a2c1a'


def lobby():
    k = []
    # A checkered marble floor.
    tile = 4.0
    tiles = []
    for i in range(int(W / tile)):
        for j in range(int(L / tile)):
            x = -W / 2 + tile * (i + 0.5)
            z = -L / 2 + tile * (j + 0.5)
            tiles.append(part('Tile', (tile, 1, tile), (x, -0.5, z), MARBLE[(i + j) % 2], 'Glass' if (i + j) % 2 else 'SmoothPlastic', extra={'CastShadow': False}))
    k.append(model('Floor', tiles))
    k.append(part('Rug', (10, 0.06, 22), (0, 0.03, 4), '#6b1e2a', 'Fabric', collide=False))
    k.append(part('RugTrim', (11, 0.04, 23), (0, 0.02, 4), GOLD, 'Fabric', collide=False))
    walls = [
        part('WallBack', (W, HT, 1), (0, HT / 2, -L / 2 - 0.5), WALLC),
        part('WallFront', (W, HT, 1), (0, HT / 2, L / 2 + 0.5), WALLC),
        part('WallLeft', (1, HT, L), (-W / 2 - 0.5, HT / 2, 0), WALLC),
        part('WallRight', (1, HT, L), (W / 2 + 0.5, HT / 2, 0), WALLC),
        part('Ceiling', (W, 1, L), (0, HT + 0.5, 0), '#1f1820'),
    ]
    for side in (-1, 1):
        walls.append(part('Panel', (0.3, 4, L), (side * (W / 2 - 0.15), 2, 0), WOOD, 'Wood', collide=False))
        walls.append(part('Trim', (0.4, 0.3, L), (side * (W / 2 - 0.2), 4.1, 0), GOLD, 'Metal', collide=False))
    walls.append(part('PanelFront', (W, 4, 0.3), (0, 2, L / 2 - 0.15), WOOD, 'Wood', collide=False))
    k.append(model('Walls', walls))
    # Columns along the sides.
    cols = []
    for side in (-1, 1):
        for z in (-10, 0, 10):
            cols.append(part('Column', (2, HT, 2), (side * 15, HT / 2, z), '#d8d0c2', 'SmoothPlastic', shape='Cylinder'))
            cols.append(part('ColumnBase', (2.8, 1, 2.8), (side * 15, 0.5, z), GOLD, 'Metal', shape='Cylinder'))
            cols.append(part('ColumnTop', (2.8, 0.8, 2.8), (side * 15, HT - 0.4, z), GOLD, 'Metal', shape='Cylinder'))
    k.append(model('Columns', cols))
    # Chandeliers.
    for z in (-6, 8):
        ch = [part('Chain', (0.2, 3, 0.2), (0, HT - 1.5, z), GOLD, 'Metal', collide=False),
              part('Ring', (5, 0.4, 5), (0, HT - 3, z), GOLD, 'Metal', shape='Cylinder', collide=False)]
        for i in range(8):
            a = i / 8 * math.tau
            ch.append(part('Candle', (0.35, 0.9, 0.35), (math.cos(a) * 2.2, HT - 2.5, z + math.sin(a) * 2.2), '#fff2c8', 'Neon', collide=False))
        ch.append(part('Glow', (1.4, 1.4, 1.4), (0, HT - 3.6, z), '#ffe7b0', 'Neon', shape='Ball', collide=False, kids=[light('#ffd9a0', 2.2, 34)]))
        k.append(model('Chandelier', ch))
    # The reception desk, left side, with a bell and a sign.
    desk = [part('Desk', (4, 3.6, 12), (-17, 1.8, 2), WOOD, 'Wood'),
            part('DeskTop', (4.6, 0.3, 12.6), (-17, 3.75, 2), '#2b2630', 'Glass'),
            part('Bell', (0.6, 0.4, 0.6), (-16.4, 4.1, 0), GOLD, 'Metal', shape='Ball'),
            part('Lamp', (0.5, 1.2, 0.5), (-17.5, 4.5, 6), GOLD, 'Metal', shape='Cylinder'),
            part('LampShade', (1.4, 0.9, 1.4), (-17.5, 5.4, 6), '#f5e2b8', 'Neon', shape='Cylinder', kids=[light('#ffd9a0', 1.2, 12)]),
            part('KeyBoard', (0.3, 5, 9), (-21.8, 7.5, 2), WOOD, 'Wood')]
    for i in range(12):
        desk.append(part('Hook', (0.3, 0.3, 0.3), (-21.5, 6 + (i // 4) * 1.4, -1 + (i % 4) * 2), GOLD, 'Metal', shape='Ball'))
    desk.append(text3d('Reception', '$reception', (-14.9, 5.2, 2), size=34, rot=(0, 90, 0)))
    k.append(model('Reception', desk))
    # Sofas and plants, right side.
    sofas = []
    for z in (-2, 8):
        sofas += [part('Seat', (4, 1.6, 7), (17, 0.8, z), '#6b1e2a', 'Fabric'),
                  part('Back', (1.2, 3, 7), (19.3, 1.5, z), '#6b1e2a', 'Fabric'),
                  part('ArmA', (4, 2.2, 1), (17.3, 1.1, z - 3.5), '#5a1824', 'Fabric'),
                  part('ArmB', (4, 2.2, 1), (17.3, 1.1, z + 3.5), '#5a1824', 'Fabric')]
    sofas.append(part('CoffeeTable', (3, 1.4, 4), (12.5, 0.7, 3), WOOD, 'Wood'))
    k.append(model('Sofas', sofas))
    plants = []
    for x, z in [(-20, 15), (20, 15), (-20, -15), (20, -15), (-9, -15), (9, -15)]:
        plants += [part('Pot', (2, 2, 2), (x, 1, z), GOLD, 'Metal', shape='Cylinder'),
                   part('Leaves', (3, 3, 3), (x, 3.2, z), '#2f6b3a', 'Grass', shape='Ball'),
                   part('Leaves', (2.2, 2.2, 2.2), (x + 0.6, 4.4, z - 0.4), '#3a7d45', 'Grass', shape='Ball')]
    k.append(model('Plants', plants))
    # The elevator, in the back wall.
    ez = -L / 2
    el = [
        part('FrameL', (1.2, 10, 1.4), (-4.6, 5, ez + 0.2), GOLD, 'Metal'),
        part('FrameR', (1.2, 10, 1.4), (4.6, 5, ez + 0.2), GOLD, 'Metal'),
        part('FrameTop', (10.4, 1.2, 1.4), (0, 10.6, ez + 0.2), GOLD, 'Metal'),
        part('DoorL', (4, 9.4, 0.4), (-2, 4.7, ez + 0.6), '#9aa0a8', 'Metal'),
        part('DoorR', (4, 9.4, 0.4), (2, 4.7, ez + 0.6), '#9aa0a8', 'Metal'),
        # The cabin behind the doors (they're open: walk in).
        part('CabinFloor', (8, 0.4, 8), (0, 0.2, ez - 4), '#3a3036', 'Metal'),
        part('CabinBack', (8, 10, 0.5), (0, 5, ez - 8.2), '#5a4a3a', 'Wood'),
        part('CabinL', (0.5, 10, 8), (-4.2, 5, ez - 4), '#5a4a3a', 'Wood'),
        part('CabinR', (0.5, 10, 8), (4.2, 5, ez - 4), '#5a4a3a', 'Wood'),
        part('CabinTop', (8, 0.5, 8), (0, 10.2, ez - 4), '#2b2630'),
        part('CabinLight', (3, 0.2, 3), (0, 9.9, ez - 4), '#ffe7b0', 'Neon', collide=False, kids=[light('#ffe0a8', 1.4, 14)]),
        part('Zone', (7.6, 6, 7.6), (0, 3, ez - 4), '#ffffff', transp=1, collide=False, extra={'CanTouch': False}),
        part('Arrow', (1.2, 1.2, 0.2), (0, 12, ez + 0.2), '#ff6b5a', 'Neon', collide=False),
        text3d('Title', '$elevator', (0, 13.1, ez + 0.95), size=40),
        text3d('Sign', '', (0, 11.2, ez + 0.95), color='#ff8a70', size=34),
    ]
    # (the doors start open: slid aside into the wall)
    el[3]['p']['Position'] = v3(-6.1, 4.7, ez + 0.6)
    el[4]['p']['Position'] = v3(6.1, 4.7, ez + 0.6)
    # A hole in the back wall for it.
    walls[0] = part('WallBackL', (W / 2 - 4, HT, 1), (-(W / 4 + 2), HT / 2, ez - 0.5), WALLC)
    walls.append(part('WallBackR', (W / 2 - 4, HT, 1), (W / 4 + 2, HT / 2, ez - 0.5), WALLC))
    walls.append(part('WallBackTop', (8, HT - 10, 1), (0, 10 + (HT - 10) / 2, ez - 0.5), WALLC))
    k.append(model('Elevator', el))
    # Title and how to play.
    k.append(text3d('Title', '$title', (0, 11.5, L / 2 - 0.1), size=96, rot=(0, 180, 0), color='#ffd36b'))
    k.append(part('Board', (16, 5, 0.3), (-8, 6, -L / 2 + 0.3), '#1c1418', 'Wood'))
    k.append(text3d('Hint', '$lobby_hint', (-8, 6, -L / 2 + 0.5), size=20, color='#f4f1ec', font='Bold'))
    k.append({'c': 'SpawnLocation', 'n': 'Spawn', 'p': {'Position': v3(0, 0.15, 12), 'Size': v3(6, 0.3, 6), 'Color': c3('#6b1e2a'), 'Material': 'Fabric'}})
    k.append(sound('LobbyMusic', 'Lobby', 0.45, True, True))
    return k


def lobby_melt(strings):
    return {
        'format': 'melt', 'version': 1,
        'meta': {
            'name': 'Midnight Hotel',
            'description': 'A hotel of 100 doors. Find the keys, hide from the Howl when the lights flicker, outrun the Watcher. Play with up to 6 friends: the elevator takes you in together.',
            'i18n': {'name': {'ru': 'Отель «Полночь»'},
                     'description': {'ru': 'Отель из 100 дверей. Ищи ключи, прячься от Вопля, когда мигает свет, убегай от Следящего. Играй с друзьями, до 6 человек: лифт увозит вас вместе.'}},
        },
        'strings': strings,
        'tree': {'c': 'DataModel', 'k': [
            {'c': 'Workspace', 'n': 'Workspace', 'p': {'Gravity': 22, 'FallHeight': -30}, 'k': lobby()},
            {'c': 'Lighting', 'n': 'Lighting', 'p': {'ClockTime': 21, 'Brightness': 0.6, 'Ambient': c3('#5a4c58'), 'FogEnabled': False,
                                                     'SkyTop': c3('#0e0b16'), 'SkyHorizon': c3('#2a1c2c')}, 'k': [{'c': 'Sky', 'n': 'Sky'}]},
            {'c': 'ReplicatedStorage', 'n': 'ReplicatedStorage', 'k': [
                {'c': 'ModuleScript', 'n': 'Shared', 'p': {'Source': src('Shared.luau')}},
                assets_folder(), config(),
                value('IntValue', 'Countdown', -1),
                {'c': 'RemoteEvent', 'n': 'Result'},
            ]},
            {'c': 'ServerScriptService', 'n': 'ServerScriptService', 'k': [{'c': 'Script', 'n': 'Lobby', 'p': {'Source': src('LobbyServer.luau')}}]},
            {'c': 'ServerStorage', 'n': 'ServerStorage'},
            {'c': 'StarterGui', 'n': 'StarterGui'},
            {'c': 'StarterPlayer', 'n': 'StarterPlayer', 'p': {'CameraMaxZoom': 14}, 'k': [
                {'c': 'StarterPlayerScripts', 'n': 'StarterPlayerScripts', 'k': [{'c': 'LocalScript', 'n': 'LobbyUI', 'p': {'Source': src('LobbyClient.luau')}}]}]},
            {'c': 'StarterPack', 'n': 'StarterPack'},
        ]},
    }


def hotel_melt(strings):
    return {
        'format': 'melt', 'version': 1,
        'meta': {'name': 'The Hotel', 'description': '', 'i18n': {'name': {'ru': 'Отель'}, 'description': {}}},
        'strings': strings,
        'tree': {'c': 'DataModel', 'k': [
            {'c': 'Workspace', 'n': 'Workspace', 'p': {'Gravity': 22, 'FallHeight': -40}, 'k': [
                {'c': 'Folder', 'n': 'Rooms'},
                {'c': 'SpawnLocation', 'n': 'Spawn', 'p': {'Position': v3(0, 0.2, -6), 'Size': v3(4, 0.4, 4), 'Transparency': 1, 'CanCollide': False}},
                sound('HotelHum', 'Hum', 0.5, True, False),
                sound('ChaseMusic', 'Chase', 0.8, True, False),
                sound('HowlNear', 'HowlNear', 1.2, False, False),
            ]},
            {'c': 'Lighting', 'n': 'Lighting', 'p': {'ClockTime': 0, 'Brightness': 0.25, 'Ambient': c3('#3a3040'), 'FogEnabled': True, 'FogColor': c3('#0b0910'), 'FogEnd': 140,
                                                     'SkyTop': c3('#05040a'), 'SkyHorizon': c3('#0b0910')}, 'k': [{'c': 'Sky', 'n': 'Sky'}]},
            {'c': 'ReplicatedStorage', 'n': 'ReplicatedStorage', 'k': [
                {'c': 'ModuleScript', 'n': 'Shared', 'p': {'Source': src('Shared.luau')}},
                assets_folder(), config(),
                {'c': 'Folder', 'n': 'Remotes', 'k': [{'c': 'RemoteEvent', 'n': n} for n in ['Notice', 'Died', 'Escaped']]},
                {'c': 'Folder', 'n': 'State', 'k': [value('IntValue', 'Door', 0)]},
            ]},
            {'c': 'ServerScriptService', 'n': 'ServerScriptService', 'k': [{'c': 'Script', 'n': 'Hotel', 'p': {'Source': src('HotelServer.luau')}}]},
            {'c': 'ServerStorage', 'n': 'ServerStorage'},
            {'c': 'StarterGui', 'n': 'StarterGui'},
            {'c': 'StarterPlayer', 'n': 'StarterPlayer', 'p': {'WalkSpeed': 9, 'SprintSpeed': 14, 'MaxStamina': 0, 'RespawnTime': 60, 'CameraMaxZoom': 10}, 'k': [
                {'c': 'StarterPlayerScripts', 'n': 'StarterPlayerScripts', 'k': [{'c': 'LocalScript', 'n': 'HotelUI', 'p': {'Source': src('HotelClient.luau')}}]}]},
            {'c': 'StarterPack', 'n': 'StarterPack'},
        ]},
    }


strings = jload('strings.json', {})
strings['reception'] = {'en': 'RECEPTION', 'ru': 'РЕСЕПШН'}
for name, melt in [('hotel_lobby', lobby_melt(strings)), ('hotel_rooms', hotel_melt(strings))]:
    out = os.path.join(here, '..', name + '.melt')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(melt, f, ensure_ascii=False, indent=1)
    print('wrote', os.path.normpath(out))
