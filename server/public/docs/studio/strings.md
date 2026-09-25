# Translations

Meltiew is played in many languages. A place can carry its own translations, and every player sees the one for the language they picked in the app (English when there's none for it).

## The place name and description

In **Publish → Translations**, add a language and fill in the name and description for it. Lists, search and the place page show the translated ones.

## Text inside the place

**Place → Translations** holds text keys. Each key has a text per language:

| Key | English | Русский |
|---|---|---|
| `hello` | Hello, world! | Привет, мир! |
| `coins` | Coins: {0} | Монеты: {0} |

Use them in two ways:

1. **As text.** Set any `Text` (a TextLabel, a button, a Text3D in the world) to `$hello`. Each player sees their language, nothing to script.
2. **From scripts.** `Strings.get("coins", 12)` returns `Coins: 12` for an English player and `Монеты: 12` for a Russian one. `{0}`, `{1}` and so on are replaced by the extra arguments.

```lua
-- LocalScript: the player's own language
label.Text = Strings.get("coins", coins)

-- Script (server): pick the language of a specific player
local text = Strings.forPlayer(player, "welcome", player.DisplayName)
game.ReplicatedStorage.Notify:FireClient(player, text)
```

A key with no text for the player's language falls back to English, then to any text it has, then to the key itself. `player.Language` is the player's language code (`en`, `ru`, `es`, `ja`...), and `LocalizationService:GetString(key, ...)` is the same as `Strings.get`.
