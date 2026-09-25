# Scripting

Places are scripted in **[Luau](https://luau.org)**, the Lua dialect Roblox uses. If you've written Roblox scripts, most of it will feel familiar: `game`, `workspace`, `Instance.new`, `:Connect`, `task.wait`, RemoteEvents. This page covers what's here and how it behaves. Every class, property and event is in the [class reference](classes.md).

## Three kinds of scripts

| Kind | Runs on | Runs when it's in |
|---|---|---|
| **Script** | the server, once for the whole place | `Workspace` or `ServerScriptService` |
| **LocalScript** | each player's device, for that player | their `PlayerGui` or `PlayerScripts` (copied from `StarterGui` and `StarterPlayer → StarterPlayerScripts`) |
| **ModuleScript** | wherever it's `require`d | anywhere; usually `ReplicatedStorage` |

The server is the boss: it owns health, can kick and teleport players, and what it changes in the world is sent to everyone. A LocalScript can change things too, but only that player sees those changes. Use a LocalScript for UI, input and effects; use a Script for rules, scores and anything players shouldn't be able to fake.

Set `Enabled = false` on a script to keep it from running; setting it back to `true` starts it.

```lua
-- ReplicatedStorage.Util (ModuleScript)
local Util = {}
function Util.shout(text)
	return string.upper(text) .. "!"
end
return Util

-- ServerScriptService.Main (Script)
local Util = require(game.ReplicatedStorage.Util)
print(Util.shout("hello")) --> HELLO!
```

## What scripts can use

- `game`, `workspace`, `script` (the running script), `Instance.new(className, parent?)`
- `game:GetService(name)`: any service in the Explorer, plus `RunService`, `TweenService`, `UserInputService` and `LocalizationService`. `game.Players`, `game.Lighting` and so on work too.
- Values: `Vector3`, `Vector2`, `Color3`, `UDim`, `UDim2`, `TweenInfo`, `Enum`
- `task.wait`, `task.spawn`, `task.defer`, `task.delay`, `task.cancel` (and the old `wait`, `spawn`, `delay`)
- `print`, `warn`, `error`: they show up in Output with the script's name
- `require`, `typeof`, `tick()`, `time()` (seconds since the place started), `Strings`
- The standard Luau libraries: `math`, `string`, `table`, `coroutine`, `utf8`, `bit32`, `buffer`, `os.clock/time/date`, `pcall`, `setmetatable` and friends

Not available: `loadstring`, `getfenv`/`setfenv`, file or network access. Each script has its own globals; to share, use a ModuleScript.

## Objects

```lua
local part = Instance.new("Part")
part.Name = "Lava"
part.Size = Vector3.new(8, 1, 8)
part.Position = Vector3.new(0, 0.5, 12)
part.Color = Color3.fromRGB(255, 80, 40)
part.Material = Enum.Material.Neon -- or just "Neon"
part.Parent = workspace

local copy = part:Clone()
copy.Position += Vector3.new(10, 0, 0)
copy.Parent = workspace

for _, child in workspace:GetChildren() do
	if child:IsA("BasePart") then
		child.Transparency = 0.5
	end
end

part:Destroy()
```

Find things with `FindFirstChild(name)`, `WaitForChild(name, timeout?)`, `FindFirstChildOfClass`, `FindFirstAncestor` and `GetDescendants()`. `SetAttribute(name, value)` / `GetAttribute(name)` keep your own values on any object.

Positions are in studs, rotations are in degrees (`part.Rotation = Vector3.new(0, 45, 0)`). Unanchored parts fall and roll with physics; anchored ones stay put.

## Events

Every event has `:Connect(fn)`, `:Once(fn)` and `:Wait()`. `Connect` returns a connection with `:Disconnect()`.

```lua
local conn = workspace.Button.Touched:Connect(function(hit)
	print(hit.Name, "touched the button")
end)
task.wait(10)
conn:Disconnect()

part:GetPropertyChangedSignal("Color"):Connect(function()
	print("new color", part.Color)
end)
```

Common ones: `Touched` / `TouchEnded` on parts, `MouseClick` on a ClickDetector, `PlayerAdded` / `PlayerRemoving` on Players, `Died` / `HealthChanged` on a Humanoid, `Activated` on buttons, `Changed` and `ChildAdded` on everything.

## Players and characters

```lua
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	print(player.DisplayName, player.Name, player.UserId, player.Language)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		humanoid.WalkSpeed = 8
		humanoid.JumpPower = 12
		humanoid.MaxHealth = 150
		humanoid.Health = 150
	end)
end)
```

A character is a Model named after the player with a `HumanoidRootPart` (where they stand; its `Position` updates as they move) and a `Humanoid`.

**Humanoid** controls the character: `WalkSpeed`, `SprintSpeed`, `JumpPower`, `CanJump`, `Health`, `MaxHealth`, `AutoHeal` + `HealthRegen` (health per second) and `EmotesEnabled`. Change them on the server. `humanoid:TakeDamage(20)` hurts; at 0 health the player dies and respawns after `StarterPlayer.RespawnTime`.

Defaults for every new character come from **StarterPlayer**: the same humanoid settings plus `RespawnTime`, `ChatEnabled`, `CameraMode` (`Classic` or `LockFirstPerson`) and `CameraMaxZoom`.

On the server a player can be sent somewhere with `player:Teleport(Vector3.new(0, 20, 0))`, respawned with `player:LoadCharacter()` or removed with `player:Kick("reason")`. `Workspace.FallHeight` is the void: fall below it and you respawn.

In a LocalScript, `game.Players.LocalPlayer` is you.

### A kill brick

```lua
local lava = workspace.Lava
lava.Touched:Connect(function(hit)
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if player then
		hit.Parent.Humanoid.Health = 0
	end
end)
```

`Touched` gets the part that touched, for players that's their `HumanoidRootPart`, so `hit.Parent` is the character.

## Remotes: talking between players and the server

A **RemoteEvent** sends a message one way; a **RemoteFunction** asks the server and waits for the answer. Put them in `ReplicatedStorage` so both sides can see them.

```lua
-- LocalScript in a button
local remote = game.ReplicatedStorage.BuyCoin
script.Parent.Activated:Connect(function()
	remote:FireServer("gold", 3)
end)

-- Script on the server
local coins = {}
game.ReplicatedStorage.BuyCoin.OnServerEvent:Connect(function(player, kind, amount)
	-- The server always gets who sent it first. Check everything else: players can send anything.
	if type(amount) ~= "number" or amount < 1 or amount > 10 then return end
	coins[player] = (coins[player] or 0) + amount
	game.ReplicatedStorage.CoinsChanged:FireClient(player, coins[player])
end)
```

| From | Call | Arrives as |
|---|---|---|
| LocalScript | `remote:FireServer(...)` | `remote.OnServerEvent(player, ...)` on the server |
| Script | `remote:FireClient(player, ...)` | `remote.OnClientEvent(...)` on that player |
| Script | `remote:FireAllClients(...)` | `remote.OnClientEvent(...)` on everyone |

```lua
-- Server
game.ReplicatedStorage.GetScore.OnServerInvoke = function(player)
	return 42
end
-- LocalScript
local score = game.ReplicatedStorage.GetScore:InvokeServer()
```

Arguments can be numbers, strings, booleans, tables of those, vectors, colors and objects in the place. Each player can send up to 40 messages per server tick; the rest are dropped.

A **BindableEvent** is the same idea inside one side: `:Fire(...)` and `.Event:Connect(...)`.

## Waiting and timing

```lua
task.wait(2)                     -- pause this script for 2 seconds
task.spawn(function() ... end)   -- run now, alongside
task.delay(5, function() ... end)
local thread = task.delay(60, endRound)
task.cancel(thread)

game:GetService("RunService").Heartbeat:Connect(function(dt)
	spinner.Rotation += Vector3.new(0, 90 * dt, 0)
end)
```

`RunService:IsServer()` / `IsClient()` tell you where you are.

## Tweens

Smoothly animate any number, Vector3, Vector2, Color3, UDim or UDim2 property.

```lua
local TweenService = game:GetService("TweenService")
local info = TweenInfo.new(1.5, "Sine", "InOut", -1, true) -- time, style, direction, repeats (-1 = forever), reverses, delay
local tween = TweenService:Create(workspace.Platform, info, { Position = Vector3.new(0, 10, 0) })
tween:Play()
tween.Completed:Connect(function() print("done") end)
```

Styles: `Linear`, `Quad`, `Cubic`, `Sine`, `Back`, `Bounce`, `Elastic`. Directions: `In`, `Out`, `InOut`. Also `tween:Pause()` and `tween:Cancel()`.

## Input (LocalScripts)

```lua
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input)
	if input.KeyCode == "E" then
		print("E pressed")
	end
end)
print(UIS:IsKeyDown("Shift"))
```

`KeyCode` is the key's name as a string: `"A"` … `"Z"`, `"0"` … `"9"`, `"Space"`, `"Shift"`, `"Ctrl"`, `"Enter"`, `"Up"`, `"F1"` and so on. Keys typed into the chat or a TextBox don't reach scripts. Phones have no keyboard: give them a UI button instead.

For clicking things in the world, put a **ClickDetector** in a part; its `MouseClick(player)` fires on the server.

## Sounds

```lua
local s = Instance.new("Sound")
s.SoundId = "coin" -- built in: pop, click, jump, coin, hurt, win, boing, whoosh
s.Volume = 0.8
s.Parent = workspace.Chest
s:Play()
```

## Errors and limits

Errors show up in Output with the script name and line. While playing, the Console tab of the game menu shows them too, and `F9` mirrors the console into the chat. One broken script doesn't stop the others.

- A script can run for **0.25 s** without yielding (`task.wait`, waiting on an event). Longer than that, for example an endless `while true do end` without a wait, and it's stopped with an error.
- All scripts of a server share **64 MB** of memory.
- A place's server shuts down if its scripts keep crashing it.
