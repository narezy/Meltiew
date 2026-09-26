#!/usr/bin/env python3
"""Packs the BlockCraft scripts into examples/blockcraft.melt (open it in Studio: File -> Import)."""
import json
import os

here = os.path.dirname(os.path.abspath(__file__))


def src(name):
    with open(os.path.join(here, name), encoding='utf-8') as f:
        return f.read()


def v3(x, y, z):
    return {'$v3': [x, y, z]}


def c3(hex_):
    return {'$c3': hex_}


def part(name, size, pos, color, material='Plastic', **extra):
    p = {'Size': v3(*size), 'Position': v3(*pos), 'Color': c3(color), 'Material': material, 'CanCollide': False, 'CastShadow': False}
    p.update(extra)
    return {'c': 'Part', 'n': name, 'p': p}


# Same colors as World.BLOCKS, for the little cubes you hold.
BLOCK_TOOLS = [
    ('Dirt', '#8a5a36', 'Sand'),
    ('Stone', '#8d8d93', 'Concrete'),
    ('Planks', '#c08e55', 'Wood'),
    ('Glass', '#cfefff', 'Glass'),
    ('Brick', '#a4513a', 'Brick'),
    ('Grass', '#6cbf49', 'Grass'),
    ('Wood', '#6b4a2b', 'Wood'),
    ('Leaves', '#3f8f3a', 'Grass'),
    ('Sand', '#e6d59a', 'Sand'),
    ('Cobblestone', '#6f6f76', 'Brick'),
    ('Snow', '#f4f7fb', 'SmoothPlastic'),
    ('Pumpkin', '#e8871e', 'Plastic'),
    ('Gold', '#f2c94c', 'Metal'),
    ('Diamond', '#5ce1e6', 'Neon'),
]

pickaxe = {
    'c': 'Tool',
    'n': 'Pickaxe',
    'p': {'ToolTip': 'Dig'},
    'k': [
        part('Handle', (0.16, 0.16, 1.6), (0, 0, 0), '#7a5230', 'Wood'),
        part('Head', (1.3, 0.18, 0.2), (0, 0, -0.75), '#9aa3ad', 'Metal'),
    ],
}
tools = [pickaxe] + [
    {'c': 'Tool', 'n': name, 'p': {'ToolTip': name}, 'k': [part('Handle', (0.55, 0.55, 0.55), (0, 0, -0.2), color, mat)]}
    for name, color, mat in BLOCK_TOOLS
]

hint = {
    'c': 'ScreenGui',
    'n': 'Hint',
    'k': [{
        'c': 'TextLabel',
        'n': 'Label',
        'p': {
            'Text': '$hint',
            'Position': {'$u2': [0.5, -200, 0, 12]},
            'Size': {'$u2': [0, 400, 0, 30]},
            'BackgroundTransparency': 0.45,
            'BackgroundColor': c3('#16141d'),
            'TextColor': c3('#f4f1ec'),
            'TextSize': 15,
            'Font': 'Bold',
            'TextWrapped': True,
        },
        'k': [{'c': 'UICorner', 'n': 'UICorner', 'p': {'CornerRadius': {'$u': [0, 12]}}}],
    }],
}

melt = {
    'format': 'melt',
    'version': 1,
    'meta': {
        'name': 'BlockCraft',
        'description': 'Dig, build and explore a world of blocks. Pickaxe digs, blocks build: pick them in the hotbar or the inventory.',
        'i18n': {
            'name': {'ru': 'Блоккрафт'},
            'description': {'ru': 'Копай, строй и исследуй мир из блоков. Кирка копает, блоки строят: выбирай их в хотбаре или в инвентаре.'},
        },
    },
    'strings': {
        'hint': {
            'en': 'Pickaxe digs, blocks build. More blocks in the bag',
            'ru': 'Кирка копает, блоки строят. Ещё блоки в рюкзаке',
        },
    },
    'tree': {
        'c': 'DataModel',
        'k': [
            {'c': 'Workspace', 'n': 'Workspace', 'p': {'FallHeight': -20},
             'k': [{'c': 'SpawnLocation', 'n': 'SpawnLocation', 'p': {'Position': v3(0.5, 20, 0.5), 'Size': v3(3, 0.4, 3)}}]},
            {'c': 'Lighting', 'n': 'Lighting', 'p': {'FogEnabled': True, 'FogEnd': 70, 'FogColor': c3('#d9ecff'), 'ClockTime': 10},
             'k': [{'c': 'Sky', 'n': 'Sky'}]},
            {'c': 'ReplicatedStorage', 'n': 'ReplicatedStorage', 'k': [
                {'c': 'ModuleScript', 'n': 'World', 'p': {'Source': src('World.luau')}},
                {'c': 'RemoteEvent', 'n': 'BlockEvent'},
                {'c': 'RemoteFunction', 'n': 'GetEdits'},
            ]},
            {'c': 'ServerScriptService', 'n': 'ServerScriptService', 'k': [
                {'c': 'Script', 'n': 'Server', 'p': {'Source': src('Server.luau')}},
            ]},
            {'c': 'ServerStorage', 'n': 'ServerStorage'},
            {'c': 'StarterGui', 'n': 'StarterGui', 'k': [hint]},
            {'c': 'StarterPlayer', 'n': 'StarterPlayer', 'p': {'CameraMaxZoom': 18, 'WalkSpeed': 5, 'SprintSpeed': 8},
             'k': [{'c': 'StarterPlayerScripts', 'n': 'StarterPlayerScripts', 'k': [
                 {'c': 'LocalScript', 'n': 'Blocks', 'p': {'Source': src('Blocks.luau')}},
                 {'c': 'LocalScript', 'n': 'Build', 'p': {'Source': src('Build.luau')}},
             ]}]},
            {'c': 'StarterPack', 'n': 'StarterPack', 'k': tools},
        ],
    },
}

out = os.path.join(here, '..', 'blockcraft.melt')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(melt, f, ensure_ascii=False, indent=1)
print('wrote', os.path.normpath(out))
