# Meltiew Studio

Studio is where you build your own places: put blocks in the world, script them in **Luau**, draw a UI, test it and publish it for friends or everyone.

It lives in the app, in the **Studio** tab. It's made for a computer with a mouse and keyboard; it works on a phone too, just slower to use.

**Guides**

- [Scripting](scripting.md): scripts, events, players and characters, remotes, tweens, input
- [User interface](ui.md): ScreenGui, frames, buttons, layouts, rounded corners
- [Translations](strings.md): one place in every player's language
- [The .melt file](melt.md): what a place looks like on disk
- [Class reference](classes.md): every object, property, method and event

## Your first place

1. Open **Studio** and press **New place**. You get a baseplate, a spawn and an empty script.
2. Pick **Insert → Part**. It appears where the camera looks.
3. Drag the arrows to move it, switch to **Scale** or **Rotate** for the other handles, and set the color and material in **Properties**.
4. Open `ServerScriptService → Main` and write:

```lua
local part = workspace.Part
part.Touched:Connect(function()
	part.Color = Color3.fromHSV(math.random(), 0.6, 1)
end)
```

5. Press **Test** (F5). You play the place right on your device, alone; the Output panel shows what scripts printed. Leave the place from the menu to go back to editing.
6. Press **Publish**, pick who can play and save. Your place is now on your profile and in search.

## The editor

| Area | What it's for |
|---|---|
| Explorer (left) | The tree of everything in the place. Drag to reparent, right-click for more. |
| View (center) | The 3D world. Scripts you open get their own tabs here. |
| Output (bottom) | Prints, warnings and errors from scripts, and syntax errors while you type. |
| Properties (right) | Everything about the selected objects. Select several to edit them together. |

### Camera and selection

| Do | How |
|---|---|
| Fly | Hold right mouse button + `W` `A` `S` `D`, `E` up, `Q` down, `Shift` faster |
| Look around | Hold right mouse button and move the mouse |
| Pan | Hold the middle mouse button |
| Zoom | Mouse wheel |
| Focus on the selection | `F` |
| Select | Click. `Ctrl` or `Shift` + click adds to the selection |
| Select a part inside a model | `Alt` + click (a plain click selects the whole model) |

### Shortcuts

| Key | Action |
|---|---|
| `1` `2` `3` `4` | Select, Move, Scale, Rotate tool |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `Ctrl+C` / `Ctrl+V` | Copy / paste (pastes next to the selection) |
| `Ctrl+D` | Duplicate |
| `Ctrl+G` | Group into a Model |
| `Delete` | Delete |
| `Ctrl+S` | Save |
| `F5` | Test |

**Snap** in the top bar sets the grid for moving and scaling (off, 0.25, 0.5, 1 or 2 studs). Rotation snaps to 15°.

**UI** in the top bar shows your ScreenGuis over the 3D view so you can move and resize them with the mouse.

Studio saves by itself every two minutes. A dot next to the name means there are unsaved changes.

## Where things go

| Container | What belongs there |
|---|---|
| `Workspace` | Everything in the 3D world: parts, models, 3D text, lights. Scripts here run on the server. |
| `Lighting` | Time of day, fog, ambient light and the **Sky**. |
| `ReplicatedStorage` | Things both the server and players need: RemoteEvents, ModuleScripts, templates to clone. |
| `ServerScriptService` | Server scripts. Players never receive them. |
| `ServerStorage` | Server-only objects (templates, data). Players never receive them. |
| `StarterGui` | ScreenGuis. Every player gets a copy in their `PlayerGui`. |
| `StarterPlayer` | Character settings (speed, jump, health, camera) and `StarterPlayerScripts` for LocalScripts. |

## Sky and 3D text

- **Insert → Sky** puts a Sky into Lighting (there's only one). Pick a preset: Day, Sunset, Night, Space, Overcast, Candy. `Custom` uses six of your images, one per side of the box.
- **Insert → Text3D** puts a floating label in the world. `Billboard` makes it always face the camera. Write `$key` as its text to show a [translation](strings.md).
- The sun and light follow `Lighting.ClockTime` (0 to 24).

## Images

**Place → Images** holds the images you uploaded. Use them as a part's `Texture`, an `ImageLabel`'s image or a custom sky. Each account can keep up to **100 images and 25 MB** (2 MB per image, PNG or JPG). Images belong to your account, not to one place, so every place of yours can use them.

## Publishing

**Publish** opens the place settings:

- **Name and description**, plus translations of both for other languages.
- **Who can play**: only you, your friends or everyone. Only "everyone" places show up in search.
- **Max players** per server (1 to 30; new places start at 10).
- **Comments** on the place page, on or off.
- **Covers**: a 16:9 one for lists and the place page and a 1:1 icon. Take them from the current view or upload an image.
- **Stats**: visits, unique and returning players, total and average playtime, who's playing now and a 30-day chart.

Players can like places, leave comments and report places or comments that break the rules.

## Import and export

**File → Export** saves the place as a `.melt` file: one JSON file with the whole place, scripts included. **Import** opens one in the current place (or as a new place from the Studio tab). Images are referenced by ID, so they only show up for places made on the same account.

## Limits

| What | Limit |
|---|---|
| Places per account | 50 |
| Objects in a place | 20,000 |
| Place file | 8 MB |
| One script | 200 KB |
| Script memory (per server) | 64 MB |
| One script run without yielding | 0.25 s, then it's stopped with an error |
| Players per server | 30 (10 by default) |
