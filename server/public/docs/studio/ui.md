# User interface

Anything drawn over the game (score counters, shops, menus, buttons for phones) is a **ScreenGui** with UI objects inside it. Put ScreenGuis in **StarterGui**: when a player joins they get their own copy in `Players.<name>.PlayerGui`, and LocalScripts inside it run for them.

Turn on **UI** in the Studio top bar to see and drag your UI over the 3D view.

## Objects

| Class | What it is |
|---|---|
| `ScreenGui` | A layer on the screen. `Enabled` shows or hides it, higher `DisplayOrder` draws on top. |
| `Frame` | A box, to group and color things. |
| `ScrollingFrame` | A box that scrolls when its `CanvasSize` is bigger than itself. |
| `TextLabel` | Text. |
| `TextButton` | Text you can press. |
| `TextBox` | A field players type into. |
| `ImageLabel` / `ImageButton` | One of your uploaded images, still or pressable. |
| `UICorner` | Rounds the corners of its parent (`CornerRadius` in pixels). |
| `UIStroke` | An outline around its parent (`Color`, `Thickness`, `Transparency`). |
| `UIPadding` | Space inside its parent before the children start. |
| `UIListLayout` | Lines up its siblings in a row or a column. |
| `UIGridLayout` | Lines up its siblings in a grid of `CellSize` cells. |

The last five are decorations: put them **inside** the object they change.

## Size and position: UDim2

`Position` and `Size` are `UDim2` values: a **scale** (part of the parent's size, 0 to 1) plus an **offset** in pixels, for X and then Y.

```lua
frame.Size = UDim2.new(0.5, 0, 0, 80)        -- half the parent's width, 80 px tall
frame.Position = UDim2.new(0.5, 0, 1, -20)  -- middle, 20 px above the bottom
frame.AnchorPoint = Vector2.new(0.5, 1)     -- ...measured from the frame's bottom center
button.Size = UDim2.fromOffset(160, 48)
bar.Size = UDim2.fromScale(health / maxHealth, 1)
```

`AnchorPoint` says which point of the object `Position` places: `(0, 0)` is the top-left corner (the default), `(0.5, 0.5)` the center, `(1, 1)` the bottom-right.

Other things every UI object has: `BackgroundColor`, `BackgroundTransparency`, `Visible`, `ZIndex` (higher is on top), `LayoutOrder` (order inside a list or grid) and `Rotation` in degrees.

## Text

`Text`, `TextColor`, `TextSize`, `Font` (`Regular`, `Bold`, `Black`), `TextXAlignment` / `TextYAlignment`, `TextWrapped`, `TextTransparency`. A TextBox also has `PlaceholderText` and `ClearTextOnFocus`.

Write `$key` as the text to show a [translation](strings.md) in each player's language, or set it from a script with `Strings.get("key")`.

## Events

```lua
-- LocalScript inside the button
local button = script.Parent
button.Activated:Connect(function()
	game.ReplicatedStorage.Jump:FireServer()
end)
button.MouseEnter:Connect(function() button.BackgroundTransparency = 0.2 end)
button.MouseLeave:Connect(function() button.BackgroundTransparency = 0 end)

-- LocalScript inside a TextBox
local box = script.Parent
box.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		print("typed:", box.Text)
	end
end)
```

`Activated` (and `MouseButton1Click`, the same thing) fires for mouse clicks and taps alike.

## Example: a coin counter

In StarterGui: `ScreenGui → Frame (with a UICorner) → TextLabel "Coins"`, and a LocalScript in the ScreenGui:

```lua
local label = script.Parent.Frame.Coins
game.ReplicatedStorage.CoinsChanged.OnClientEvent:Connect(function(coins)
	label.Text = Strings.get("coins", coins) -- "Coins: {0}" / "Монеты: {0}"
end)
```

## Tips

- Players on phones have small, wide screens. Use scale for big layout and offset for things like button height, and keep buttons at least 44 px.
- Keep important UI away from the top corners: the menu and chat buttons live there.
- LocalScripts change only that player's screen. To show everyone something, have the server `FireAllClients` and let each LocalScript update its own UI.
