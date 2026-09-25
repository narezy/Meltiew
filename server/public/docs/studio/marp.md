# The .marp file

A **.marp** file is a whole place in one JSON file: the object tree with every property, the scripts' source, the translations and the name and description. **File → Export** in Studio writes one, **Import** reads one. It's plain text, so it works fine in git and can be written by other tools.

## Shape

```json
{
  "format": "marp",
  "version": 1,
  "meta": {
    "name": "Obby",
    "description": "Jump to the top!",
    "i18n": {
      "name": { "ru": "Обби" },
      "description": { "ru": "Допрыгни до вершины!" }
    }
  },
  "strings": {
    "coins": { "en": "Coins: {0}", "ru": "Монеты: {0}" }
  },
  "tree": {
    "c": "DataModel",
    "k": [
      {
        "c": "Workspace", "n": "Workspace",
        "k": [
          { "c": "Part", "n": "Baseplate", "p": {
              "Size": { "$v3": [128, 1, 128] },
              "Position": { "$v3": [0, -0.5, 0] },
              "Color": { "$c3": "#8fd18a" },
              "Material": "Grass"
          } }
        ]
      },
      { "c": "ServerScriptService", "n": "ServerScriptService", "k": [
          { "c": "Script", "n": "Main", "p": { "Source": "print('hi')" } }
      ] }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `format`, `version` | Always `"marp"` and `1` for now. |
| `meta.name`, `meta.description` | The place's name (up to 60 characters) and description (up to 1000), in English or your main language. |
| `meta.i18n` | Translations of the name and description, by language code. |
| `strings` | [Translation keys](strings.md): `key → { language: text }`. |
| `tree` | The object tree, starting at `DataModel`. |

## Objects

Every object is `{ "c": class, "n": name, "p": { properties }, "k": [ children ] }`. Only `c` is required: a missing name is the class name, missing properties keep their defaults, and `k` can be left out when there are no children. The [class reference](classes.md) lists every class and property.

The services (`Workspace`, `Lighting`, `ReplicatedStorage`, `ServerScriptService`, `ServerStorage`, `StarterGui`, `StarterPlayer`) are direct children of `DataModel`. Missing ones are created when the place loads.

## Values

JSON has no vectors or colors, so those are written as small tagged objects:

| Type | In the file | In Luau |
|---|---|---|
| Vector3 | `{ "$v3": [x, y, z] }` | `Vector3.new(x, y, z)` |
| Vector2 | `{ "$v2": [x, y] }` | `Vector2.new(x, y)` |
| Color3 | `{ "$c3": "#rrggbb" }` | `Color3.fromHex("#rrggbb")` |
| UDim2 | `{ "$u2": [xScale, xOffset, yScale, yOffset] }` | `UDim2.new(...)` |
| UDim | `{ "$u": [scale, offset] }` | `UDim.new(scale, offset)` |
| Enum | `"Neon"` | `Enum.Material.Neon` |
| Image | `"asset://<id>"` | the same string |

Numbers, strings and booleans are plain JSON.

Images point to uploads by ID (`asset://…`). The file doesn't contain the images themselves, so on another account they won't load until that account uploads its own and swaps the IDs.

## Limits

A place file can be up to **8 MB** with at most **20,000 objects**, 64 levels deep. A script's `Source` can be up to 200 KB; other text properties up to 4,000 characters. Unknown classes are rejected; unknown properties are dropped.
