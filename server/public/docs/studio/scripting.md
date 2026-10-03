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

**Humanoid** controls the character: `WalkSpeed`, `SprintSpeed`, `JumpPower`, `CanJump`, `StepHeight`, `StepSpeed`, `Health`, `MaxHealth`, `AutoHeal` + `HealthRegen` (health per second) and `EmotesEnabled`. Change them on the server.

Sprinting (Shift on a computer, the run button on a phone) uses up stamina, shown as a bar under health. `CanSprint = false` turns sprinting off. `MaxStamina` is how much there is (0 = endless, and the bar hides), `StaminaDrain` how much a second of sprinting costs and `StaminaRegen` how much comes back each second after a short rest. Set them on StarterPlayer for everyone, or on one Humanoid:

```lua
humanoid.MaxStamina = 200   -- a potion that lets you run twice as long
humanoid.CanSprint = false  -- a stealth level: walking only
```

`Traction` is how hard the feet grip. At 1 (the default) fast characters slide a little when they turn or stop, like on the Playground; raise it for sharp, exact movement (10 or more: no drift at all), lower it for ice.

```lua
humanoid.WalkSpeed = 40
humanoid.Traction = 12      -- fast, but turns on the spot
```

`Bhop = true` turns on bunny hopping: holding jump hops again the moment you land, every hop keeps your speed and adds a little, and you can steer in the air, up to `BhopMaxSpeed` (studs per second, 24 by default). Give it to everyone on StarterPlayer, or as a reward:

```lua
humanoid.Bhop = true
humanoid.BhopMaxSpeed = 40
```

Characters walk up small ledges without jumping, like stairs. `StepHeight` is how high a ledge can be (0.65 studs by default; 0 turns it off), `StepSpeed` how quickly it goes: at 1 there's a short pause between steps, at 2 or more a staircase is walked up in one go. The anti-cheat knows both, so high steps aren't taken for flying.

```lua
humanoid.StepHeight = 1.5   -- big blocky stairs
humanoid.StepSpeed = 3      -- straight up them, no stops
```

### Reshaping the body

Every body part of a character (and of a Rig) can be changed by scripts, on its own: `Head`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`.

- `<Part>Scale` resizes it (`Vector3.new(1, 1, 1)` is normal), `<Part>Offset` moves it (studs), `<Part>Angle` turns it, `<Part>Visible = false` hides it. Without legs (hidden or tiny) the character stands on its torso; longer legs make it taller.
- `<Part>Part` swaps the part for any Part or Model of yours (keep it in ReplicatedStorage): it's drawn in the part's place with its own colors, materials and textures, and moves with the body. A new head can keep the face (`HeadPartKeepsFace`) and the hats (`HeadPartKeepsAccessories`); other parts can keep the shirt (`<Part>PartKeepsClothing`). Swapped legs set the height too.

```lua
-- A werewolf: a wolf head that keeps the hats, furry arms that keep the shirt.
local wolf = game.ReplicatedStorage.Wolf
humanoid.HeadPart = wolf.Head
humanoid.HeadPartKeepsAccessories = true
humanoid.LeftArmPart = wolf.Arm
humanoid.RightArmPart = wolf.Arm
humanoid.LeftArmPartKeepsClothing = true
humanoid.RightArmPartKeepsClothing = true
humanoid.TorsoScale = Vector3.new(1.3, 1.2, 1.2)
-- and back to normal:
humanoid.HeadPart = nil
```

`humanoid:TakeDamage(20)` hurts; at 0 health the player dies and respawns after `StarterPlayer.RespawnTime`.

Defaults for every new character come from **StarterPlayer**: the same humanoid settings plus `RespawnTime`, `ChatEnabled`, `CameraMode` (`Classic` or `LockFirstPerson`) and `CameraMaxZoom`.

On the server a player can be sent somewhere with `player:Teleport(Vector3.new(0, 20, 0))`, respawned with `player:LoadCharacter()` or removed with `player:Kick("reason")`. `Workspace.FallHeight` is the void: fall below it and you respawn.

### Anti-cheat

The server checks how every character moves against the place's own rules: the Humanoid's `WalkSpeed`, `SprintSpeed` and `JumpPower` and `Workspace.Gravity`. Moving faster than that, jumping higher than a jump can reach from where the player took off, climbing walls that aren't `Climbable` or teleporting puts the player back where they were, and players who keep doing it get kicked. What they stand on is checked against the place's own parts. Teleports from your Scripts (`player:Teleport`, respawns) are always fine; `Teleport` only works on the server for that reason. If your place moves players in ways the checks can't know about (launchers, a world your LocalScripts build), set `StarterPlayer.AntiCheat` to false.

Ways to move players the anti-cheat understands:

- `player:Glide(Vector3.new(0, 50, 0), 2)` (server) flies them there in a straight line over 2 seconds: dashes, ziplines, cannons.
- `humanoid.Floating = true` lets them hang in the air and move around freely until you set it back.
- `player:GetNetworkIdle()` (server): seconds since their app last reported where they are. A few seconds means their connection froze, so don't land a hit on where they were.

Players hidden behind the place's walls aren't sent to the others at all, so wallhacks have nothing to show. `StarterPlayer.PlayerSyncRange` (studs, 0 = everywhere) also leaves out players further away than that. `player.SyncAll = true` lets one player see everyone anyway: spectators, abilities that show all players.

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

## Gamepads, TV remotes and VR controllers

What the player is playing on, in a LocalScript:

```lua
local UIS = game:GetService("UserInputService")
print(UIS:GetPlatform())        -- Windows, OSX, Linux, Android, AndroidTV, IOS, MetaOS
print(UIS.PreferredInput)       -- KeyboardAndMouse, Gamepad or Touch (changes as they switch)
print(UIS.GamepadEnabled, UIS.VREnabled)
UIS.LastInputTypeChanged:Connect(function(kind) print("now using", kind) end)
```

On the server, `player.VREnabled` says who's in a headset.

Gamepad buttons arrive in `InputBegan` / `InputEnded` like keys, with `KeyCode` `"ButtonA"`, `"ButtonB"`, `"ButtonX"`, `"ButtonY"`, `"ButtonL1"`, `"ButtonR1"`, `"ButtonL2"`, `"ButtonR2"`, `"ButtonL3"`, `"ButtonR3"`, `"ButtonStart"`, `"ButtonSelect"` and `"DPadUp"` … `"DPadRight"`; the sticks and triggers come in `InputChanged` (`"Thumbstick1"`, `"Thumbstick2"`: `input.Position` X and Y; triggers: Z). `UIS:IsGamepadButtonDown("Gamepad1", "ButtonA")` asks right now. A TV remote's OK is `"ButtonA"`, its Back `"ButtonB"`. VR controllers count as a gamepad: A, B, X, Y as on one, the grips are `ButtonL1` / `ButtonR1`, the triggers `ButtonL2` / `ButtonR2`, stick clicks `ButtonL3` / `ButtonR3`, the menu button `ButtonSelect`.

To give an input a job of your own, bind it with **ContextActionService**: the function gets it before anything else, the game's own use of that button (jumping on A, say) stops, and on phones you can ask for an on-screen button too:

```lua
local CAS = game:GetService("ContextActionService")
CAS:BindAction("Dash", function(name, state, input)
	if state == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Sink   -- or Pass: let others have it too
end, true, "Q", "ButtonX")
CAS:SetTitle("Dash", "DASH")              -- the phone button's label
CAS:UnbindAction("Dash")
```

## VR

Players can join in a VR headset (a computer with SteamVR or WiVRn, or a standalone Pico): the app's screen floats in front of them, the controllers point and click, the left stick walks, the right one turns. Their hands show to players 13 and older, and their head turns for everyone. **StarterPlayer.VRAllowed** = false keeps headsets out of your place, **VRHandsVisible** = false hides everyone's hands. In VR, Climbable parts are climbed with the hands: hold the grip while a hand touches one and pull.

Where the headset and the hands are, in a LocalScript (world positions in studs, turns in degrees like a part's `Rotation`; `nil` when a hand isn't tracked):

```lua
local VRService = game:GetService("VRService")
if VRService.VREnabled then
	local hand = VRService:GetUserPosition(Enum.UserCFrame.RightHand)   -- "Head", "LeftHand", "RightHand", "Floor"
	local turn = VRService:GetUserRotation(Enum.UserCFrame.RightHand)
end
```

They're fresh every frame (`RunService.Heartbeat`), so a place can move players its own way. The example **Monkey Tag** (`examples/monkeytag` in the Meltiew repository) is tag played with your arms, like the gorilla games: no legs, no stick, a hand that touches anything holds on, and moving it moves you. All of that is its own LocalScript, under a hundred lines: copy it and change how it feels.

### Moving a player from a script

`HumanoidRootPart.AssemblyLinearVelocity` is how fast the character is going (studs a second). Set it to send them off that way: a launch pad, a knock-back, a dash, or moving them by hand every frame.

```lua
-- server: a jump pad
pad.Touched:Connect(function(hit)
	local root = hit.Parent:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
	end
end)
```

From a LocalScript it works on your own character right away; from the server it's sent to that player's app. Gravity and the ground take over from there (`Traction` decides how fast it fades on the ground and in the air).

## Sounds

```lua
local s = Instance.new("Sound")
s.SoundId = "coin" -- built in: pop, click, jump, coin, hurt, win, boing, whoosh
s.Volume = 0.8
s.Parent = workspace.Chest -- inside a part: heard from there, louder up close
s:Play()
```

Your own sounds: in Studio open **Assets → Sounds**, upload an OGG, MP3 or WAV (up to 5 MB each, 40 MB in all per account) and pick it in a Sound's `SoundId` with the "…" button, or copy its `asset://...` and set it from a script. `Looped = true` repeats it (music), `sound:Stop()` stops it, `Pitch` makes it higher or lower. A Sound outside the Workspace's parts (in a LocalScript's folder, in the camera) plays for the whole screen.

## Climbing and steps

Players walk up ledges up to about 0.65 studs high without jumping (stairs, kerbs). Turn on **Climbable** on any part to make it a wall they can climb: walking into it climbs up, walking away climbs down, sideways moves along it, jump lets go, and at the top they step onto it. In VR it's climbed by hand instead: grip it and pull. From scripts: `part.Climbable = true`.

## Physics parts

Turn **Anchored** off and a part becomes a physics part: it falls, tumbles, stacks, and
players shove it by walking into it (heavy parts barely budge; mass comes from Size).
Every player sees the same thing: the player nearest to a part simulates it and the
others follow, and whoever bumps into a part takes it over. The server's scripts see
where it went (`part.Position`), and setting `Position` from a script teleports it.

```lua
local crate = workspace.Crate
crate.Anchored = false            -- let it fall
task.wait(3)
print(crate.Position)             -- where it landed
crate.Position = Vector3.new(0, 20, 0)  -- drop it again
```

## Seats

Insert a **Seat**: touching it sits the player down, jumping gets them up. It's a part, so paint it, resize it, or set `Transparency = 1` and hide it inside a chair or a car you built; players sit facing its front (−Z). Scripts see who's sitting:

```lua
local seat = workspace.Throne
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	if seat.Occupant then
		print(seat.Occupant.Parent.Name .. " sat on the throne")
	end
end)
seat:Sit(player.Character.Humanoid) -- sit someone down from a script
seat.Disabled = true                -- nobody can sit
```

## Vehicles

Insert a **VehicleSeat** into a **Model** with your car's parts (the body, the wheels, Seats for passengers). Whoever sits on it drives the whole Model: the movement keys, a gamepad's stick, a phone's joystick or a VR stick give gas and steering, jump gets out. Build it from Anchored parts (the default): while it drives, every part of the Model moves together as one.

- Parts with **Wheel** in their name roll as it goes, and the front ones turn when it steers.
- **MaxSpeed** (studs a second), **Torque** (how fast it speeds up; it brakes twice as hard), **TurnSpeed** (degrees a second), **Grip** (1 holds the road, lower drifts) and **HoverHeight** (above 0 it floats that high over whatever is under it, a hovercraft) tune it.
- It slides along walls, leans with slopes, falls off edges, and rolls to a stop after the driver gets out. Players in its Seats ride along.
- **HeadsUpDisplay** shows the driver a speedometer.

Scripts read what the driver does, for sounds, lights or rules:

```lua
local seat = workspace.Car.VehicleSeat
seat:GetPropertyChangedSignal("Throttle"):Connect(function()
	print("gas:", seat.Throttle, "steering:", seat.Steer, "speed:", seat.Speed)
end)
```

`Throttle` and `Steer` are -1, 0 or 1; `ThrottleFloat` and `SteerFloat` go in between (a stick pushed part way). The server checks the car can't go faster than its MaxSpeed allows.

## Dragging things

Put a **DragDetector** in a part and players can pick it up and drag it with the mouse, a finger or the VR laser. An anchored part goes where it's dragged, for everyone; an unanchored one is carried and thrown by physics. **DragStyle** TranslatePlane drags it along the ground, TranslateViewPlane up, down and sideways as the camera sees it. **MaxActivationDistance** is how close a player has to be. Set **ResponseStyle** to Custom to leave the part where it is and decide yourself:

```lua
local d = workspace.Lever.DragDetector
d.DragStart:Connect(function(player, cursor) print(player.Name, "grabbed it at", cursor) end)
d.DragContinue:Connect(function(player, cursor) end)
d.DragEnd:Connect(function(player) print("let go") end)
```

On the screen, any frame, label, button or image with **Draggable** = true can be dragged around by the player (their own screen only). A LocalScript hears it:

```lua
local window = script.Parent.Window
window.DragBegin:Connect(function(startPosition) end)
window.DragStopped:Connect(function(x, y) print("left at", window.Position) end)
```

## Sub-places and teleporting

A game can have more places than one: a lobby and the levels, a town and the houses you go into. In Studio, the **Places** panel under the Explorer lists the game's main place and its sub-places. **+** makes a new one; double-click one to edit it (what's open is saved first); **← Main place** at the top goes back. Right-click a place to rename it, delete it, or copy its id.

Sub-places aren't listed anywhere by themselves: players get there by teleporting. They're as open as the main place, and they all share its **DataStores**, badges, gamepasses and settings, so coins earned in a level are there in the lobby.

```lua
local TeleportService = game:GetService("TeleportService")
local LEVEL = "p1a2b3c4d5" -- the sub-place's id (Places panel > right-click > Copy id)

-- One player, to a server of that place with room:
TeleportService:Teleport(LEVEL, player, { checkpoint = 3 })

-- A group into a new server of their own (an elevator into a round):
TeleportService:TeleportPartyAsync(LEVEL, { player1, player2, player3 }, { mode = "hard" })

-- Over there, what came along:
game.Players.PlayerAdded:Connect(function(player)
	local join = player:GetJoinData()
	print(join.SourcePlaceId, join.TeleportData and join.TeleportData.checkpoint)
end)
```

`TeleportService:TeleportAsync(place, players, { TeleportData = ..., ShouldReserveServer = true })` does either. A LocalScript can teleport its own player (`TeleportService:Teleport(place, game.Players.LocalPlayer)`) and read `TeleportService:GetLocalPlayerTeleportData()`. `TeleportInitFailed(player, reason, message)` fires when the place isn't one of this game's. `game.PlaceId` is the place you're in, `game.GameId` the game's main place. Teleports work in a Studio test too, between the places of the game you're editing (with DataStores kept in memory across them).

## Appearance: dressing players in your place

An **Appearance** says how players look **in your place only**: body colors, a face and any
accessories, even ones they don't own. Their real avatar and profile never change.

- Put an Appearance in **StarterPlayer** and everyone wears it when they join (uniforms, teams, costumes).
  Turn on **KeepColors**, **KeepFace** or **KeepAccessories** to leave that part as the player's own.
- From a Script, dress one player:

```lua
local Players = game:GetService("Players")

-- a red team: red body, the player's own face and accessories
local red = Instance.new("Appearance")
red.TorsoColor = Color3.fromHex("#ff5a6e")
red.LeftArmColor = red.TorsoColor
red.RightArmColor = red.TorsoColor
red.KeepFace = true
red.KeepAccessories = true

Players.PlayerAdded:Connect(function(player)
	player:ApplyAppearance(red)
end)

-- add a crown to what someone wears now
local look = Players:GetAppearanceAsync(player.UserId)
look.Accessories = look.Accessories .. ",crown"
player:ApplyAppearance(look)

player:ResetAppearance()  -- their own look again
```

`Players:GetUserAppearanceAsync("username")` returns anyone's own look as an Appearance, even
if they aren't in your place: dress a boss as its creator, show a champion on a pedestal. It
always matches what they wear now.

`Accessories` is a list of accessory ids separated by commas (`"crown,halo"`, or `""` for none);
pick them with the "…" button in Studio's properties. Only Scripts (on the server) change looks.

## Animations, Rigs and the emote wheel

**Place → Animator** opens the Animator. Pick a body part, move the time slider and turn the part with the sliders: a key is set right there, and Melly moves smoothly from key to key. Set the length and whether it loops, then **Save**: the animation gets an id like `anim://12` (copied for you). Any place can play it.

```lua
-- a server Script: everyone sees this player do it
player.Character.Humanoid:PlayAnimation("anim://12")
player.Character.Humanoid:PlayAnimation("dance")  -- Melly's own moves work too
player.Character.Humanoid:StopAnimation()
```

Besides the emote wheel's moves there are two quick one-shot moves for games: `"punch"` and
`"throw"`. Melly goes back to idle when they finish, and they keep playing while running.

Moving stops an animation, like an emote. A LocalScript can animate its own player's character.

A **Rig** (Insert → Rig) is a Melly standing in your place: shopkeepers, guards, dancers. Paint it like in the avatar editor, choose a Face, put on any accessories (the Accessories property's button), give it a DisplayName, and an Animation: one of Melly's moves or one of yours. From scripts: `rig:PlayAnimation("anim://12")`, `rig:StopAnimation()`, and move it by setting `Position` (with TweenService it slides smoothly).

To give your place its own emotes, put an **EmoteOverride** in StarterPlayer: `Slot` is the wheel's move it replaces (wave, dance, cheer, sit, clap, laugh), `Animation` what plays instead, `Title` the name on the wheel.

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
-- Parts in a box (centre, size), and parts touching a part (a hitbox, a zone):
local inBox = workspace:GetPartBoundsInBox(Vector3.new(0, 5, 0), Vector3.new(10, 10, 10))
local touching = workspace:GetPartsInPart(workspace.Zone)
```

These three go by each part's bounding box. Rays go up to 5000 studs and also hit ProceduralMeshes. `params.RespectCanCollide = true` skips parts with CanCollide off.

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

## Player list stats (leaderstats)

A Folder called `leaderstats` inside a Player turns on the player list with stats, like on Roblox: every value in it (`IntValue`, `NumberValue`, `StringValue`, `BoolValue`) becomes a column, up to four, sorted by the first. Players open the list with **Tab** or the button at the top right.

```lua
game.Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = stats
end)

-- later: player.leaderstats.Coins.Value += 10
```

`IntValue` keeps whole numbers; there are also `Vector3Value`, `Color3Value` and `ObjectValue` (holds an Instance).

## Teams

Put **Team** objects into the **Teams** service. New players go onto the `AutoAssignable` team with the fewest players; set `player.Team = team` to move someone. A player's `TeamColor` follows their team (and `Neutral` is false while they're on one). They spawn on SpawnLocations whose `TeamColor` matches theirs and `Neutral` is off, or on neutral spawns if their team has none. The player list groups players by team.

```lua
local red = game.Teams.Red
red.PlayerAdded:Connect(function(player) print(player.Name, "joined red") end)
print(#red:GetPlayers(), "on red")
for _, team in game.Teams:GetTeams() do print(team.Name) end
```

## Tags (CollectionService)

Give many objects one behaviour without a script in each: tag them, then handle the tag once.

```lua
local CollectionService = game:GetService("CollectionService")
for _, part in CollectionService:GetTagged("Lava") do
	part.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
	end)
end
CollectionService:GetInstanceAddedSignal("Lava"):Connect(function(part) print("new lava", part) end)
```

`part:AddTag("Lava")`, `RemoveTag`, `HasTag`, `GetTags()` (or the same on CollectionService). Tags are also the **Tags** property in Studio (names separated by commas), saved with the place.

## Effects

- **ParticleEmitter** in a Part or a character: sparks, smoke, snow. `Rate`, lifetime, speed, colours and sizes over life, a `Texture` from your images. `emitter:Emit(30)` throws out a burst.
- **Trail**: a ribbon behind whatever it's in as it moves.
- **Highlight**: outlines and tints the Part, Model, character or Rig it's in; `DepthMode = "AlwaysOnTop"` shows it through walls.
- **PointLight** and **SpotLight** in a Part: a glow around it, or a cone out of one `Face` (`Angle`, `Range`).
- **Decal** in a Part: one of your images over a whole `Face` of it.
- **Explosion**: made by a server Script in the Workspace, it goes off at `Position`: characters within `BlastRadius` × `DestroyJointRadiusPercent` die, and `Hit(part, distance)` fires for every part in the blast.

```lua
local boom = Instance.new("Explosion")
boom.Position = Vector3.new(0, 5, 0)
boom.BlastRadius = 8
boom.Hit:Connect(function(part, distance) print(part.Name, distance) end)
boom.Parent = workspace
```

## Things over the world: BillboardGui and ProximityPrompt

- **BillboardGui** in a Part or Model floats a small GUI over it that always faces the camera: health bars, names, signs. Put Frames and labels inside, like in a ScreenGui. `StudsOffset` lifts it, `MaxDistance` hides it far away, `AlwaysOnTop` shows it through walls.
- **ProximityPrompt** in a Part: players who come close see "[E] ActionText" and press the key (tap on phones), or hold it for `HoldDuration` seconds. `Triggered(player)` fires on the server (which checks they really were close) and in that player's LocalScripts.

```lua
workspace.Door.ProximityPrompt.Triggered:Connect(function(player)
	workspace.Door.Transparency = 0.8
	workspace.Door.CanCollide = false
end)
```

## Drawing pictures (DynamicImage)

A **DynamicImage** is a picture your scripts draw, up to 128×128: `:Fill(color)`, `:SetPixel(x, y, color)`, `:DrawRect`, `:DrawCircle`, `:DrawLine`, `:Clear()`, `:GetPixel(x, y)`. Show it anywhere an image goes with `img:GetContent()`: an ImageLabel, a Part's or a ParticleEmitter's `Texture`. Drawn on the server, everyone sees it; in a LocalScript, only that player.

## Turning joints

Humanoids and Rigs have `HeadAngle`, `TorsoAngle`, `LeftArmAngle`, `RightArmAngle`, `LeftLegAngle` and `RightLegAngle` (degrees, a Vector3), added on top of whatever animation is playing: look at something, aim a tool, wave an arm.

```lua
humanoid.HeadAngle = Vector3.new(0, 30, 0) -- look to the side
```

## Clothing

Anyone can make shirts in **Studio → Accessories** and sell or give them away; players wear them from the shop. In a place, a **Clothing** object inside a character or a Rig dresses it, over its body colours: set `Texture` to one of your images laid out like the shirt template, or `CatalogId` to a shirt from the shop. Several are worn at once, later ones on top.

```lua
local shirt = Instance.new("Clothing")
shirt.CatalogId = 12
shirt.Parent = workspace.Shopkeeper -- a Rig
```

## Making big places fast

Anchored, opaque, untextured parts that don't move are drawn together in 32×32-stud areas, so a thousand blocks cost a handful of draws. Moving a part often, or making it see-through, Neon, Glass or Ice, takes it out of that and it costs a draw of its own again. For worlds of blocks, create only the faces players can see and merge neighbours into bigger parts; for smooth ground, use one ProceduralMesh.

## Errors and limits

Errors show up in Output with the script name and line. While playing, the Console tab of the game menu shows them too, and `F9` mirrors the console into the chat. One broken script doesn't stop the others.

- A script whose tasks run away (a `task.spawn` or `task.defer` that starts more of itself, again and again) is stopped after 10 000 of them at once, with a message in Output. The rest of the place goes on.
- A script can run for **0.25 s** without yielding (`task.wait`, waiting on an event). Longer than that, for example an endless `while true do end` without a wait, and it's stopped with an error.
- All scripts of a server share **64 MB** of memory.
- A place's server shuts down if its scripts keep crashing it.
