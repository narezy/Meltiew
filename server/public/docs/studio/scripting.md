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

**Humanoid** controls the character: `WalkSpeed`, `SprintSpeed`, `JumpPower`, `CanJump`, `Health`, `MaxHealth`, `AutoHeal` + `HealthRegen` (health per second) and `EmotesEnabled`. Change them on the server.

Sprinting (Shift on a computer, the run button on a phone) uses up stamina, shown as a bar under health. `CanSprint = false` turns sprinting off. `MaxStamina` is how much there is (0 = endless, and the bar hides), `StaminaDrain` how much a second of sprinting costs and `StaminaRegen` how much comes back each second after a short rest. Set them on StarterPlayer for everyone, or on one Humanoid:

```lua
humanoid.MaxStamina = 200   -- a potion that lets you run twice as long
humanoid.CanSprint = false  -- a stealth level: walking only
```

`Traction` is how hard the feet grip. At 1 (the default) fast characters slide a little when they turn or stop, like on the Playground; raise it for sharp, exact movement (10 or more: no drift at all), lower it for ice.

```lua
humanoid.WalkSpeed = 40
humanoid.Traction = 12      -- fast, but turns on the spot
``` `humanoid:TakeDamage(20)` hurts; at 0 health the player dies and respawns after `StarterPlayer.RespawnTime`.

Defaults for every new character come from **StarterPlayer**: the same humanoid settings plus `RespawnTime`, `ChatEnabled`, `CameraMode` (`Classic` or `LockFirstPerson`) and `CameraMaxZoom`.

On the server a player can be sent somewhere with `player:Teleport(Vector3.new(0, 20, 0))`, respawned with `player:LoadCharacter()` or removed with `player:Kick("reason")`. `Workspace.FallHeight` is the void: fall below it and you respawn.

### Anti-cheat

The server checks how every character moves against the place's own rules: the Humanoid's `WalkSpeed`, `SprintSpeed` and `JumpPower` and `Workspace.Gravity`. Moving faster than that, jumping higher or teleporting puts the player back where they were, and players who keep doing it get kicked. Teleports from your Scripts (`player:Teleport`, respawns) are always fine; `Teleport` only works on the server for that reason. If your place moves players in ways the checks can't know about (fast moving platforms, launchers), set `StarterPlayer.AntiCheat` to false.

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
s.Parent = workspace.Chest -- inside a part: heard from there, louder up close
s:Play()
```

Your own sounds: in Studio open **Assets → Sounds**, upload an OGG, MP3 or WAV (up to 5 MB each, 40 MB in all per account) and pick it in a Sound's `SoundId` with the "…" button, or copy its `asset://...` and set it from a script. `Looped = true` repeats it (music), `sound:Stop()` stops it, `Pitch` makes it higher or lower. A Sound outside the Workspace's parts (in a LocalScript's folder, in the camera) plays for the whole screen.

## Tools

A **Tool** in StarterPack (or put into a player's Backpack) shows up in the backpack bar. Picking it moves it into the character; the part named `Handle` goes into the right hand.

```lua
local tool = script.Parent -- a Script inside the Tool
tool.Activated:Connect(function()
	local character = tool.Parent
	print(character.Name .. " swung the sword")
end)
tool.Equipped:Connect(function(mouse) end) -- mouse only in LocalScripts
tool.Unequipped:Connect(function() end)
```

`Activated` fires on the server too, so damage and the like go into a Script. `RequiresHandle = false` makes a tool without a Handle (spells, build tools). `GripOffset` and `GripRotation` move it in the hand, `ToolTip` and `TextureId` change how it looks in the bar, `CanBeDropped` lets players drop it with Backspace. `Humanoid:EquipTool(tool)` and `Humanoid:UnequipTools()` do it from a script.

## Mouse and cursor (LocalScripts)

```lua
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
mouse.Button1Down:Connect(function()
	print(mouse.Target, mouse.Hit) -- part under the pointer, the point it hits
end)
mouse.Icon = "rbxassetid://..." -- or "" for the normal cursor
```

Also `Button1Up`, `Button2Down/Up`, `Move`, `WheelForward/Backward`, `X`, `Y`, `Origin` and `UnitRay`. `UserInputService.MouseBehavior = "LockCenter"` locks the pointer in the middle of the screen (shooters), `"Default"` gives it back; `MouseIconEnabled = false` hides it. On phones `Hit` and `Target` follow the last tap.

## Camera (LocalScripts)

`workspace.CurrentCamera` is this device's camera. It has `Position`, `Focus`, `LookVector` and `FieldOfView`. **CameraType** decides who moves it:

| CameraType | What the camera does |
|---|---|
| `Custom` | The game's camera: orbits the player, who turns and zooms it. |
| `Scriptable` | Stays at `Position` looking at `Focus`, until you move it. Cutscenes, menus, fixed views. |
| `Watch` | Stays at `Position`, always looking at `CameraSubject`. Security cameras, arenas. |
| `Track` | Follows `CameraSubject` from `CameraOffset` without turning. Top-down and side-scrolling games. |
| `Follow` | Like Track, but the offset turns with the subject. Chase cameras for cars and boats. |

`CameraSubject` is a Part, a Model or a Humanoid; empty means your own character. `CameraOffset` defaults to `(0, 6, 12)`. `Roll` tilts the view in degrees, and `Smoothing` (seconds) makes the camera glide to where it should be instead of jumping.

```lua
local cam = workspace.CurrentCamera

-- a top-down game
cam.CameraType = "Track"
cam.CameraOffset = Vector3.new(0, 30, 0.1)

-- a chase camera behind a car, a bit lazy
cam.CameraType = "Follow"
cam.CameraSubject = workspace.Car
cam.CameraOffset = Vector3.new(0, 5, 12)
cam.Smoothing = 0.3

-- a cutscene shot: jump there, tilt, zoom in
cam:LookAt(Vector3.new(40, 10, 40), workspace.Castle.Position)
cam.Roll = 10
cam.FieldOfView = 45

-- and back to normal, facing east from above
cam.CameraType = "Custom"
cam:SetRotation(90, -30) -- yaw, pitch in degrees
cam:SetZoom(20)          -- 0 is first person
cam:Shake(3, 0.6)        -- strength, seconds
```

Position, Focus, FieldOfView, Roll and CameraOffset can be tweened with TweenService for smooth camera moves. StarterPlayer's `CameraMode` (`Classic`, `LockFirstPerson`, `LockThirdPerson`), `CameraMinZoom` and `CameraMaxZoom` set the player's own zoom limits; `SetZoom` from a script may go past them.

## Finding parts

```lua
local params = RaycastParams.new()
params.FilterDescendantsInstances = { player.Character }
params.FilterType = "Exclude" -- or "Include"
local hit = workspace:Raycast(origin, direction * 100, params)
if hit then
	print(hit.Instance, hit.Position, hit.Normal, hit.Distance, hit.Material)
end
for _, part in workspace:GetPartBoundsInRadius(position, 10) do
	print(part.Name)
end
```

Rays go up to 5000 studs and also hit ProceduralMeshes. `params.RespectCanCollide = true` skips parts with CanCollide off.

## Small helpers

- `Debris:AddItem(part, 5)` destroys `part` in 5 seconds.
- `HttpService:JSONEncode(t)`, `HttpService:JSONDecode(text)`, `HttpService:GenerateGUID()`.
- `StarterGui:SetCoreGuiEnabled("Backpack", false)` hides a part of the game's own UI: `Backpack`, `Health`, `Chat`, `Emotes` or `All`.

## Gamepasses

Create passes in the place's settings in Studio (name, picture, price in pieces). Each pass gets a number; use it in scripts. The creator gets 95% of the price.

```lua
local MarketplaceService = game:GetService("MarketplaceService")
local VIP = 12

local function giveVip(player)
	player.Character.Humanoid.WalkSpeed = 24
end

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		if MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP) then
			giveVip(player)
		end
	end)
end)

-- a shop button: from the server, or from a LocalScript for the LocalPlayer
MarketplaceService:PromptGamePassPurchase(player, VIP)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if bought and passId == VIP then
		giveVip(player)
	end
end)
```

`MarketplaceService:GetGamePassInfo(id)` returns `{ Id, Name, Price }`. Always check ownership on the server: a LocalScript can be changed by its player.

## Badges

A place can have up to 15 badges: make them in the place's settings in Studio (or on its page on the site) with a name, what they're for and a picture. Each gets a number. Players keep badges on their profile, in the app and on the site.

```lua
local BadgeService = game:GetService("BadgeService")
local FINISHED = 7

workspace.Finish.Touched:Connect(function(part)
	local player = game.Players:GetPlayerFromCharacter(part.Parent)
	if player and not BadgeService:UserHasBadgeAsync(player.UserId, FINISHED) then
		BadgeService:AwardBadge(player.UserId, FINISHED) -- "New badge!" pops up for them
	end
end)
```

`AwardBadge` works in server Scripts only and only with this place's own badges; giving one twice does nothing. `BadgeService:GetBadgeInfo(id)` returns `{ Id, Name, Description }`. In a Studio test the popup shows, but nothing is saved.

## Saving data (DataStores)

Server Scripts can save data that outlives the server: coins, levels, a built house.

```lua
local store = game:GetService("DataStoreService"):GetDataStore("Coins")

game.Players.PlayerAdded:Connect(function(player)
	local coins = store:GetAsync("u" .. player.UserId) or 0
	player:SetAttribute("Coins", coins)
end)

game.Players.PlayerRemoving:Connect(function(player)
	store:SetAsync("u" .. player.UserId, player:GetAttribute("Coins"))
end)
```

- `GetAsync(key)`, `SetAsync(key, value)`, `RemoveAsync(key)`.
- `IncrementAsync(key, 5)` adds to a number in one step and returns the result.
- `UpdateAsync(key, function(old) return new end)` changes a value based on the old one; return `nil` to leave it.
- `ListKeysAsync(after, limit)` lists up to 100 keys after `after`.

Values can be numbers, strings, booleans, tables and Vector3/Color3. Each call waits for the answer. Limits: keys and store names up to 50 characters, a value up to 64 KB, a place up to 4 MB and 20 000 keys in all, 20 requests per second per server. Studio's Play mode keeps the data only until you stop.

## Procedural meshes

A **ProceduralMesh** is one object whose shape a script builds from triangles: terrain, rocks, ropes, water, whatever. Ten thousand triangles are still one object and one draw, unlike ten thousand parts.

```lua
local mesh = Instance.new("ProceduralMesh")
mesh.Position = Vector3.new(0, 5, 0)
mesh.Smooth = true
local a = mesh:AddVertex(Vector3.new(0, 0, 0), Color3.new(1, 0, 0))
local b = mesh:AddVertex(Vector3.new(4, 0, 0), Color3.new(0, 1, 0))
local c = mesh:AddVertex(Vector3.new(0, 4, 0), Color3.new(0, 0, 1))
mesh:AddTriangle(a, b, c)
mesh:AddBox(Vector3.new(6, 0, 0), Vector3.new(2, 2, 2))
mesh:AddSphere(Vector3.new(-6, 0, 0), 2, nil, 24)
mesh:AddCylinder(Vector3.new(0, 0, 6), 1, 4)
mesh.Parent = workspace
```

- Points are in studs around `Position` and turn with `Rotation`. Colors are optional; without one a point takes the mesh's `Color`.
- `AddQuad(p1, p2, p3, p4, color)` adds a flat four-cornered face; `AddBox`, `AddSphere` and `AddCylinder` add whole shapes. Each returns the number of its first point.
- `SetVertexPosition(i, pos)`, `GetVertexPosition(i)` and `SetVertexColor(i, color)` change points later: move them every frame for waves or a flag. Only the changed points are sent.
- `GetVertexCount()`, `GetTriangleCount()`, `Clear()`. Up to 60 000 points per mesh.
- `Smooth = true` blends the light between faces (hills), `false` keeps them flat (crystals, low-poly). `CanCollide`, `Transparency`, `Material` and `CastShadow` work like on parts; players walk on the mesh's real shape.

## Making big places fast

Anchored, opaque, untextured parts that don't move are drawn together in 32×32-stud areas, so a thousand blocks cost a handful of draws. Moving a part often, or making it see-through, Neon, Glass or Ice, takes it out of that and it costs a draw of its own again. For worlds of blocks, create only the faces players can see and merge neighbours into bigger parts; for smooth ground, use one ProceduralMesh.

## Errors and limits

Errors show up in Output with the script name and line. While playing, the Console tab of the game menu shows them too, and `F9` mirrors the console into the chat. One broken script doesn't stop the others.

- A script can run for **0.25 s** without yielding (`task.wait`, waiting on an event). Longer than that, for example an endless `while true do end` without a wait, and it's stopped with an error.
- All scripts of a server share **64 MB** of memory.
- A place's server shuts down if its scripts keep crashing it.
