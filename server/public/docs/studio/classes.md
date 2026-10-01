# Class reference

> Generated from the runtime by `tools/gen_class_docs.mjs`. Every property here can be read and set from scripts;
> "read-only" ones only read. Enum values are plain strings: `part.Material = "Neon"` and `Enum.Material.Neon` are the same.

Every object is an **Instance**, so everything listed under Instance works on all of them.

## Base classes and runtime objects

### Instance

*abstract*

| Property | Type | Default | Notes |
|---|---|---|---|
| Name | string | "Instance" |  |
| Tags | string | "" |  |

**Methods:** `FindFirstChild(name, recursive)`, `FindFirstChildOfClass(className)`, `FindFirstChildWhichIsA(className, recursive)`, `FindFirstAncestor(name)`, `FindFirstAncestorOfClass(className)`, `FindFirstAncestorWhichIsA(className)`, `WaitForChild(name, timeout)`, `GetChildren()`, `GetDescendants()`, `IsA(className)`, `IsDescendantOf(other)`, `IsAncestorOf(other)`, `GetFullName()`, `Destroy()`, `Remove()`, `Clone()`, `ClearAllChildren()`, `GetPropertyChangedSignal(prop)`, `SetAttribute(name, value)`, `GetAttribute(name)`, `AddTag(tag)`, `RemoveTag(tag)`, `HasTag(tag)`, `GetTags()`

**Events:** `Changed`, `ChildAdded`, `ChildRemoved`, `Destroying`, `AncestryChanged`

### Player

| Property | Type | Default | Notes |
|---|---|---|---|
| DisplayName | string | "" | read-only |
| UserId | number | 0 | read-only |
| Character | Instance |  | read-only |
| Language | string | "en" | read-only |
| CameraMode | [CameraMode](#cameramode) | "Classic" |  |
| CameraMinZoom | number | 0.5 | min 0, max 100 |
| CameraMaxZoom | number | 14 | min 0.5, max 100 |
| SyncAll | bool | false |  |
| VREnabled | bool | false | read-only |
| Team | Instance |  |  |
| TeamColor | Color3 | Color3.fromHex("#ffffff") |  |
| Neutral | bool | true |  |

**Methods:** `GetMouse()`, `ApplyAppearance(app)`, `ResetAppearance()`, `Kick(message)`, `LoadCharacter()`, `Glide(pos, seconds)`, `GetNetworkIdle()`, `Teleport(pos)`

**Events:** `CharacterAdded`

### PlayerGui

### PlayerScripts

### Backpack

The player's inventory: the Tools they carry but don't hold. `player.Backpack`. Refilled from StarterPack on every spawn.

### Humanoid

| Property | Type | Default | Notes |
|---|---|---|---|
| Health | number | 100 |  |
| MaxHealth | number | 100 | min 1 |
| WalkSpeed | number | 5 | min 0 |
| SprintSpeed | number | 7 | min 0 |
| Traction | number | 1 | min 0.1, max 50 |
| Bhop | bool | false |  |
| BhopMaxSpeed | number | 24 | min 1, max 200 |
| CanSprint | bool | true |  |
| MaxStamina | number | 100 | min 0 |
| StaminaDrain | number | 20 | min 0 |
| StaminaRegen | number | 15 | min 0 |
| JumpPower | number | 8.2 | min 0 |
| CanJump | bool | true |  |
| StepHeight | number | 0.65 | min 0, max 6 |
| StepSpeed | number | 1 | min 0.2, max 10 |
| AutoHeal | bool | true |  |
| HealthRegen | number | 1 | min 0 |
| EmotesEnabled | bool | true |  |
| Floating | bool | false |  |
| HeadAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| TorsoAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| LeftArmAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| RightArmAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| LeftLegAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| RightLegAngle | Vector3 | Vector3.new(0, 0, 0) |  |

**Methods:** `TakeDamage(amount)`, `EquipTool(tool)`, `UnequipTools()`, `PlayAnimation(anim)`, `StopAnimation()`

**Events:** `Died`, `HealthChanged`

### BasePart

*abstract*

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | Vector3 | Vector3.new(0, 0.5, 0) |  |
| Rotation | Vector3 | Vector3.new(0, 0, 0) |  |
| Size | Vector3 | Vector3.new(2, 1, 2) | min 0.05 |
| Color | Color3 | Color3.fromHex("#b7b3c9") |  |
| Material | [Material](#material) | "Plastic" |  |
| Transparency | number | 0 | min 0, max 1 |
| Anchored | bool | true |  |
| CanCollide | bool | true |  |
| CanTouch | bool | true |  |
| Climbable | bool | false |  |
| CastShadow | bool | true |  |
| Texture | asset | "" |  |
| TextureScale | number | 1 | min 0.05 |

**Events:** `Touched`, `TouchEnded`

### LuaSourceContainer

*abstract*

| Property | Type | Default | Notes |
|---|---|---|---|
| Source | source | "" |  |

### GuiObject

*abstract*

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | UDim2 | UDim2.new(0, 0, 0, 0) |  |
| Size | UDim2 | UDim2.new(0, 200, 0, 100) |  |
| AnchorPoint | Vector2 | Vector2.new(0, 0) |  |
| BackgroundColor | Color3 | Color3.fromHex("#ffffff") |  |
| BackgroundTransparency | number | 0 | min 0, max 1 |
| Visible | bool | true |  |
| ZIndex | number | 1 |  |
| LayoutOrder | number | 0 |  |
| Rotation | number | 0 |  |

**Events:** `MouseEnter`, `MouseLeave`

### Camera

`workspace.CurrentCamera` in LocalScripts. **CameraType** picks who moves it: `Custom` (the game: it orbits the player, and scripts can still turn and zoom it with SetRotation / SetZoom), `Scriptable` (stays at Position looking at Focus: cutscenes, menus), `Watch` (stays at Position and keeps looking at CameraSubject), `Track` (follows CameraSubject from CameraOffset, without turning: top-down, side-scrollers), `Follow` (like Track, but CameraOffset turns with the subject: chase cameras). CameraSubject is a Part, Model or Humanoid (empty: your character). Roll tilts the view in degrees, Smoothing (seconds) makes it glide into place instead of jumping.

| Property | Type | Default | Notes |
|---|---|---|---|
| CameraType | [CameraType](#cameratype) | "Custom" |  |
| FieldOfView | number | 70 | min 10, max 120 |
| Position | Vector3 | Vector3.new(0, 10, 10) |  |
| Focus | Vector3 | Vector3.new(0, 0, 0) |  |
| CameraSubject | Instance |  |  |
| CameraOffset | Vector3 | Vector3.new(0, 6, 12) |  |
| Roll | number | 0 | min -180, max 180 |
| Smoothing | number | 0 | min 0, max 5 |
| LookVector | Vector3 | Vector3.new(0, 0, -1) | read-only |

**Methods:** `LookAt(position, focus)`, `SetZoom(distance)`, `SetRotation(yaw, pitch)`, `Shake(strength, seconds)`

## Services

### Workspace

*service*

| Property | Type | Default | Notes |
|---|---|---|---|
| Gravity | number | 22 | min 0, max 200 |
| FallHeight | number | -60 |  |

**Methods:** `Raycast(origin, direction, params)`, `GetPartBoundsInRadius(position, radius, params)`, `GetPartBoundsInBox(where, size, params)`, `GetPartsInPart(part, params)`

### Lighting

*service*

| Property | Type | Default | Notes |
|---|---|---|---|
| ClockTime | number | 14 | min 0, max 24 |
| Brightness | number | 1 | min 0, max 4 |
| Ambient | Color3 | Color3.fromHex("#8d88a8") |  |
| SkyTop | Color3 | Color3.fromHex("#6fa8ef") |  |
| SkyHorizon | Color3 | Color3.fromHex("#d9ecff") |  |
| FogEnabled | bool | true |  |
| FogColor | Color3 | Color3.fromHex("#d9ecff") |  |
| FogEnd | number | 500 | min 10 |
| Shadows | bool | true |  |

### ReplicatedStorage

*service*

### ServerScriptService

*service · server only: never sent to players*

### ServerStorage

*service · server only: never sent to players*

### StarterGui

*service*

**Methods:** `SetCoreGuiEnabled(kind, enabled)`, `GetCoreGuiEnabled(kind)`

### StarterPlayer

*service*

| Property | Type | Default | Notes |
|---|---|---|---|
| WalkSpeed | number | 5 | min 0, max 60 |
| SprintSpeed | number | 7 | min 0, max 80 |
| Traction | number | 1 | min 0.1, max 50 |
| Bhop | bool | false |  |
| BhopMaxSpeed | number | 24 | min 1, max 200 |
| CanSprint | bool | true |  |
| MaxStamina | number | 100 | min 0 |
| StaminaDrain | number | 20 | min 0 |
| StaminaRegen | number | 15 | min 0 |
| JumpPower | number | 8.2 | min 0, max 60 |
| CanJump | bool | true |  |
| StepHeight | number | 0.65 | min 0, max 6 |
| StepSpeed | number | 1 | min 0.2, max 10 |
| MaxHealth | number | 100 | min 1, max 100000 |
| AutoHeal | bool | true |  |
| HealthRegen | number | 1 | min 0 |
| RespawnTime | number | 3 | min 0, max 60 |
| EmotesEnabled | bool | true |  |
| ChatEnabled | bool | true |  |
| CameraMode | [CameraMode](#cameramode) | "Classic" |  |
| CameraMinZoom | number | 0.5 | min 0, max 100 |
| CameraMaxZoom | number | 14 | min 1, max 100 |
| AntiCheat | bool | true |  |
| PlayerSyncRange | number | 0 | min 0, max 5000 |
| VRAllowed | bool | true |  |
| VRHandsVisible | bool | true |  |

### StarterPlayerScripts

*service*

### StarterPack

*service*

Tools put here are copied into every player's Backpack each time their character spawns.

### Players

*service*

| Property | Type | Default | Notes |
|---|---|---|---|
| MaxPlayers | number | 10 | read-only, min 1, max 30 |

**Methods:** `GetAppearanceAsync(userId)`, `GetUserAppearanceAsync(username)`, `GetPlayers()`, `GetPlayerByUserId(id)`, `GetPlayerFromCharacter(model)`

**Events:** `PlayerAdded`, `PlayerRemoving`

### Teams

*service*

Holds the place's Team objects. Players are put on an AutoAssignable team when they join (the one with the fewest players), spawn on SpawnLocations of their team's colour, and are grouped by team in the player list.

**Methods:** `GetTeams(teams)`

## 3D world

### Model

*can be created with `Instance.new`*

**Methods:** `MoveTo(pos)`, `GetCenter()`

### Tool

*can be created with `Instance.new`*

Something a player carries and holds in their right hand. Put a Part named **Handle** inside: that's where the hand grabs it, and every other part moves with it. Build it facing forward (−Z), the way it should point when held. Tools live in StarterPack (everyone gets one), in a player's Backpack, or lying in the Workspace (touching the Handle picks it up).

| Property | Type | Default | Notes |
|---|---|---|---|
| ToolTip | string | "" |  |
| TextureId | asset | "" |  |
| Enabled | bool | true |  |
| RequiresHandle | bool | true |  |
| GripOffset | Vector3 | Vector3.new(0, 0, 0) |  |
| GripRotation | Vector3 | Vector3.new(0, 0, 0) |  |
| CanBeDropped | bool | false |  |

**Methods:** `Activate()`, `Deactivate()`

**Events:** `Equipped`, `Unequipped`, `Activated`, `Deactivated`

### ProceduralMesh

*can be created with `Instance.new`*

A shape scripts build out of triangles: terrain, hills, rocks, a whole Minecraft chunk, a waving flag. However many triangles it has, it's one object and one draw. Points are in studs around Position (turned by Rotation). Add boxes, spheres, cylinders, quads or single triangles; change points later to animate. Up to 60,000 points and 60,000 triangles. Smooth shades it rounded instead of faceted.

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | Vector3 | Vector3.new(0, 0, 0) |  |
| Rotation | Vector3 | Vector3.new(0, 0, 0) |  |
| Color | Color3 | Color3.fromHex("#b7b3c9") |  |
| Material | [Material](#material) | "Plastic" |  |
| Transparency | number | 0 | min 0, max 1 |
| CanCollide | bool | true |  |
| CastShadow | bool | true |  |
| Smooth | bool | false |  |

**Methods:** `AddVertex(position, color)`, `AddTriangle(a, b, c)`, `AddQuad(a, b, c, d, color)`, `AddBox(center, size, color)`, `AddSphere(center, radius, color, segments)`, `AddCylinder(center, radius, height, color, segments)`, `GetVertexPosition(id)`, `SetVertexPosition(id, position)`, `SetVertexColor(id, color)`, `GetVertexCount()`, `GetTriangleCount()`, `Clear()`

### Part

*inherits [BasePart](#basepart) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Shape | [PartShape](#partshape) | "Block" |  |

### SpawnLocation

*inherits [BasePart](#basepart) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| TeamColor | Color3 | Color3.fromHex("#ffffff") |  |
| Neutral | bool | true |  |

### Text3D

*can be created with `Instance.new`*

Floating 3D text. Put it inside a character (a player's Model or a Rig) and it's worn on the head: **Position** becomes an offset from the middle of the head and it follows every move. With **Billboard** on it always faces the camera, so a big `■` in black makes a mysterious "censored" face.

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | Vector3 | Vector3.new(0, 0.5, 0) |  |
| Rotation | Vector3 | Vector3.new(0, 0, 0) |  |
| Text | string | "Hello!" |  |
| TextColor | Color3 | Color3.fromHex("#ffffff") |  |
| OutlineColor | Color3 | Color3.fromHex("#1c1a22") |  |
| TextSize | number | 64 | min 4, max 512 |
| Font | [Font](#font) | "Black" |  |
| Billboard | bool | false |  |
| Visible | bool | true |  |

### PointLight

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Color | Color3 | Color3.fromHex("#ffe9b0") |  |
| Brightness | number | 1.5 | min 0, max 16 |
| Range | number | 12 | min 0.5, max 100 |
| Enabled | bool | true |  |
| Offset | Vector3 | Vector3.new(0, 0, 0) |  |

### ClickDetector

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| MaxDistance | number | 16 | min 1, max 100 |

**Events:** `MouseClick`

### Sound

*can be created with `Instance.new`*

A sound. **SoundId** is a built-in sound (`pop`, `click`, `jump`, `coin`, `hurt`, `win`, `boing`, `whoosh`) or one you uploaded in Studio (`asset://...`, OGG, MP3 or WAV). Inside a part it's heard from that part (louder up close); anywhere else it plays for the whole screen. `sound:Play()`, `sound:Stop()`; `Looped` repeats it, `Volume` 0..2, `Pitch` makes it higher or lower.

| Property | Type | Default | Notes |
|---|---|---|---|
| SoundId | sound | "pop" |  |
| Volume | number | 0.8 | min 0, max 2 |
| Pitch | number | 1 | min 0.1, max 4 |
| Looped | bool | false |  |
| Playing | bool | false |  |

**Methods:** `Play()`, `Stop()`

**Events:** `Ended`

### Sky

*can be created with `Instance.new`*

Put inside Lighting. Pick a preset or set Preset=Custom and six images (up, down, front, back, left, right).

| Property | Type | Default | Notes |
|---|---|---|---|
| Preset | [SkyPreset](#skypreset) | "Day" |  |
| SkyboxUp | asset | "" |  |
| SkyboxDown | asset | "" |  |
| SkyboxFront | asset | "" |  |
| SkyboxBack | asset | "" |  |
| SkyboxLeft | asset | "" |  |
| SkyboxRight | asset | "" |  |
| StarsVisible | bool | false |  |
| SunVisible | bool | true |  |
| CloudsVisible | bool | true |  |

### Rig

*can be created with `Instance.new`*

A Melly that stands in your place: shopkeepers, guards, dancers. Paint it like in the avatar editor, put on any accessories (**Accessories**, the "…" button), pick a **Face**, and give it an **Animation**: one of Melly's own moves (idle, walk, run, wave, dance, cheer, sit, clap, laugh) or one you made in the Animator (`anim://12`). Position is where its feet stand. From scripts: `rig:PlayAnimation("anim://12")`, `rig:StopAnimation()`, move it by setting Position (TweenService makes it walk smoothly).

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | Vector3 | Vector3.new(0, 0, 0) |  |
| Rotation | Vector3 | Vector3.new(0, 0, 0) |  |
| DisplayName | string | "" |  |
| HeadColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| TorsoColor | Color3 | Color3.fromHex("#baa4e2") |  |
| LeftArmColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| RightArmColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| LeftLegColor | Color3 | Color3.fromHex("#302d38") |  |
| RightLegColor | Color3 | Color3.fromHex("#302d38") |  |
| Face | [Face](#face) | ":D" |  |
| Accessories | accessories | "" |  |
| Animation | animation | "idle" |  |
| AnimationSpeed | number | 1 | min 0, max 5 |
| CanCollide | bool | true |  |
| Visible | bool | true |  |
| HeadAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| TorsoAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| LeftArmAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| RightArmAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| LeftLegAngle | Vector3 | Vector3.new(0, 0, 0) |  |
| RightLegAngle | Vector3 | Vector3.new(0, 0, 0) |  |

**Methods:** `PlayAnimation(anim)`, `StopAnimation()`

### Seat

*inherits [BasePart](#basepart) · can be created with `Instance.new`*

A seat: touch it and you sit down, jump to get up. Paint it like any part, or set Transparency to 1 to hide it inside a chair you built. It faces its front (−Z). `Occupant` is the Humanoid sitting on it (or nil): `seat:GetPropertyChangedSignal("Occupant"):Connect(...)`. `seat:Sit(humanoid)` sits a player down from a script; Disabled = true stops anyone sitting.

| Property | Type | Default | Notes |
|---|---|---|---|
| Disabled | bool | false |  |
| Occupant | Instance |  | read-only |

**Methods:** `Sit(humanoid)`

### Highlight

*can be created with `Instance.new`*

Outlines and tints what it's inside: a Part, a Model, a player's character or a Rig. With **DepthMode** AlwaysOnTop it shows through walls.

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| FillColor | Color3 | Color3.fromHex("#ff3b4f") |  |
| FillTransparency | number | 0.5 | min 0, max 1 |
| OutlineColor | Color3 | Color3.fromHex("#ffffff") |  |
| OutlineTransparency | number | 0 | min 0, max 1 |
| DepthMode | [HighlightDepthMode](#highlightdepthmode) | "AlwaysOnTop" |  |

### ProximityPrompt

*can be created with `Instance.new`*

Put it in a Part: players who come close see "[E] ActionText" and press (or hold for **HoldDuration** seconds) to use it; on phones they tap it. **Triggered**(player) fires on the server, and in the player's own LocalScripts.

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| ActionText | string | "Interact" |  |
| ObjectText | string | "" |  |
| KeyboardKeyCode | string | "E" |  |
| HoldDuration | number | 0 | min 0, max 30 |
| MaxActivationDistance | number | 10 | min 1, max 100 |

**Events:** `Triggered`

### ParticleEmitter

*can be created with `Instance.new`*

Sparks, smoke, snow, confetti: particles from the Part (or character) it's in. **Rate** per second; each lives **LifetimeMin**-**LifetimeMax** seconds and fades from **Color**/**Transparency**/**Size** to the *End* values. **Texture** is one of your uploaded images (a soft dot without one). **LightEmission** 1 makes them glow. `:Emit(n)` throws out a burst.

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| Rate | number | 20 | min 0, max 400 |
| LifetimeMin | number | 1 | min 0.05, max 20 |
| LifetimeMax | number | 2 | min 0.05, max 20 |
| SpeedMin | number | 4 | min 0, max 200 |
| SpeedMax | number | 6 | min 0, max 200 |
| SpreadAngle | number | 15 | min 0, max 180 |
| EmitDirection | [EmitDirection](#emitdirection) | "Top" |  |
| Shape | [ParticleShape](#particleshape) | "Box" |  |
| Acceleration | Vector3 | Vector3.new(0, 0, 0) |  |
| Drag | number | 0 | min 0, max 20 |
| Color | Color3 | Color3.fromHex("#ffffff") |  |
| ColorEnd | Color3 | Color3.fromHex("#ffffff") |  |
| Transparency | number | 0 | min 0, max 1 |
| TransparencyEnd | number | 1 | min 0, max 1 |
| Size | number | 1 | min 0.02, max 50 |
| SizeEnd | number | 1 | min 0, max 50 |
| Rotation | number | 0 | min 0, max 360 |
| RotSpeed | number | 0 | min -1000, max 1000 |
| Texture | asset | "" |  |
| LightEmission | number | 0 | min 0, max 1 |
| LockedToPart | bool | false |  |

**Methods:** `Emit(count)`, `Clear()`

### Trail

*can be created with `Instance.new`*

A ribbon left behind by the Part or character it's in as it moves, fading over **Lifetime** seconds from **Width**/**Color** to the *End* values. **Offset** moves where it comes from.

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| Lifetime | number | 0.6 | min 0.05, max 10 |
| Width | number | 1 | min 0, max 20 |
| WidthEnd | number | 0 | min 0, max 20 |
| Color | Color3 | Color3.fromHex("#ffffff") |  |
| ColorEnd | Color3 | Color3.fromHex("#ffffff") |  |
| Transparency | number | 0.2 | min 0, max 1 |
| TransparencyEnd | number | 1 | min 0, max 1 |
| Texture | asset | "" |  |
| LightEmission | number | 0 | min 0, max 1 |
| Offset | Vector3 | Vector3.new(0, 0, 0) |  |

### Clothing

*can be created with `Instance.new`*

Clothing on the character or Rig it's inside, over its body colours: one of your uploaded images laid out like the shirt template (**Texture**), or a piece from the catalog (**CatalogId**, the number in the shop). Several are worn at once, later ones on top.

| Property | Type | Default | Notes |
|---|---|---|---|
| Texture | asset | "" |  |
| CatalogId | number | 0 | min 0 |

### Decal

*can be created with `Instance.new`*

A picture stuck on one **Face** of the Part it's in (Front, Back, Top, Bottom, Left, Right), stretched over the whole face. **Texture** is one of your uploaded images.

| Property | Type | Default | Notes |
|---|---|---|---|
| Texture | asset | "" |  |
| Face | [NormalId](#normalid) | "Front" |  |
| Color3 | Color3 | Color3.fromHex("#ffffff") |  |
| Transparency | number | 0 | min 0, max 1 |

### SpotLight

*can be created with `Instance.new`*

A cone of light from the Part it's in, shining out of **Face**, **Angle** degrees wide and **Range** studs long.

| Property | Type | Default | Notes |
|---|---|---|---|
| Color | Color3 | Color3.fromHex("#ffe9b0") |  |
| Brightness | number | 2 | min 0, max 16 |
| Range | number | 16 | min 0.5, max 100 |
| Angle | number | 60 | min 1, max 170 |
| Face | [NormalId](#normalid) | "Front" |  |
| Enabled | bool | true |  |
| Shadows | bool | false |  |

### Explosion

*can be created with `Instance.new`*

Put in the Workspace (by a server Script) to blow up at **Position**: characters within **BlastRadius** × **DestroyJointRadiusPercent** die, and **Hit** fires for every part in the blast `(part, distance)`. It's gone a moment later.

| Property | Type | Default | Notes |
|---|---|---|---|
| Position | Vector3 | Vector3.new(0, 0, 0) |  |
| BlastRadius | number | 4 | min 0, max 100 |
| BlastPressure | number | 500000 | min 0 |
| DestroyJointRadiusPercent | number | 1 | min 0, max 1 |
| Visible | bool | true |  |

**Events:** `Hit`

## User interface

### ScreenGui

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| DisplayOrder | number | 0 |  |

### Frame

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

### ScrollingFrame

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| CanvasSize | UDim2 | UDim2.new(0, 0, 2, 0) |  |
| ScrollingDirection | [ScrollingDirection](#scrollingdirection) | "Vertical" |  |
| ScrollBarThickness | number | 6 | min 0, max 30 |

### TextLabel

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Text | string | "Label" |  |
| TextColor | Color3 | Color3.fromHex("#1c1a22") |  |
| TextSize | number | 20 | min 4, max 200 |
| Font | [Font](#font) | "Bold" |  |
| TextXAlignment | [TextXAlignment](#textxalignment) | "Center" |  |
| TextYAlignment | [TextYAlignment](#textyalignment) | "Center" |  |
| TextWrapped | bool | true |  |
| TextTransparency | number | 0 | min 0, max 1 |

### TextButton

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Text | string | "Label" |  |
| TextColor | Color3 | Color3.fromHex("#1c1a22") |  |
| TextSize | number | 20 | min 4, max 200 |
| Font | [Font](#font) | "Bold" |  |
| TextXAlignment | [TextXAlignment](#textxalignment) | "Center" |  |
| TextYAlignment | [TextYAlignment](#textyalignment) | "Center" |  |
| TextWrapped | bool | true |  |
| TextTransparency | number | 0 | min 0, max 1 |
| AutoButtonColor | bool | true |  |

**Events:** `Activated`, `MouseButton1Click`

### TextBox

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Text | string | "Label" |  |
| TextColor | Color3 | Color3.fromHex("#1c1a22") |  |
| TextSize | number | 20 | min 4, max 200 |
| Font | [Font](#font) | "Bold" |  |
| TextXAlignment | [TextXAlignment](#textxalignment) | "Center" |  |
| TextYAlignment | [TextYAlignment](#textyalignment) | "Center" |  |
| TextWrapped | bool | true |  |
| TextTransparency | number | 0 | min 0, max 1 |
| PlaceholderText | string | "Type here..." |  |
| ClearTextOnFocus | bool | false |  |

**Events:** `FocusLost`, `Focused`

### ImageLabel

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Image | asset | "" |  |
| ImageColor | Color3 | Color3.fromHex("#ffffff") |  |
| ImageTransparency | number | 0 | min 0, max 1 |
| ScaleType | [ScaleType](#scaletype) | "Fit" |  |

### ImageButton

*inherits [GuiObject](#guiobject) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Image | asset | "" |  |
| ImageColor | Color3 | Color3.fromHex("#ffffff") |  |
| ImageTransparency | number | 0 | min 0, max 1 |
| ScaleType | [ScaleType](#scaletype) | "Fit" |  |

**Events:** `Activated`, `MouseButton1Click`

### UICorner

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| CornerRadius | number | 12 | min 0, max 500 |

### UIStroke

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Color | Color3 | Color3.fromHex("#1c1a22") |  |
| Thickness | number | 2 | min 0, max 40 |
| Transparency | number | 0 | min 0, max 1 |

### UIPadding

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Left | number | 8 |  |
| Right | number | 8 |  |
| Top | number | 8 |  |
| Bottom | number | 8 |  |

### UIListLayout

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| FillDirection | [FillDirection](#filldirection) | "Vertical" |  |
| Padding | number | 8 |  |
| HorizontalAlignment | [HorizontalAlignment](#horizontalalignment) | "Left" |  |
| VerticalAlignment | [VerticalAlignment](#verticalalignment) | "Top" |  |
| SortOrder | [SortOrder](#sortorder) | "LayoutOrder" |  |

### UIGridLayout

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| CellSize | UDim2 | UDim2.new(0, 100, 0, 100) |  |
| CellPadding | UDim2 | UDim2.new(0, 8, 0, 8) |  |
| SortOrder | [SortOrder](#sortorder) | "LayoutOrder" |  |

### BillboardGui

*can be created with `Instance.new`*

A GUI that floats over the Part or Model it's in and always faces the camera: put Frames, TextLabels and ImageLabels in it. **Size** is in pixels; **StudsOffset** lifts it; with **AlwaysOnTop** off, walls hide it.

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |
| Size | UDim2 | UDim2.new(0, 200, 0, 50) |  |
| StudsOffset | Vector3 | Vector3.new(0, 2, 0) |  |
| AlwaysOnTop | bool | false |  |
| MaxDistance | number | 100 | min 1, max 2000 |

## Scripts

### Script

*inherits [LuaSourceContainer](#luasourcecontainer) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |

### LocalScript

*inherits [LuaSourceContainer](#luasourcecontainer) · can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Enabled | bool | true |  |

### ModuleScript

*inherits [LuaSourceContainer](#luasourcecontainer) · can be created with `Instance.new`*

## Logic and values

### Folder

*can be created with `Instance.new`*

### RemoteEvent

*can be created with `Instance.new`*

**Methods:** `FireServer(...)`, `FireClient(player, ...)`, `FireAllClients(...)`

**Events:** `OnServerEvent`, `OnClientEvent`

### RemoteFunction

*can be created with `Instance.new`*

**Methods:** `InvokeServer(...)`

**Callbacks:** `OnServerInvoke`

### BindableEvent

*can be created with `Instance.new`*

**Methods:** `Fire(...)`

**Events:** `Event`

### StringValue

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | string | "" |  |

### NumberValue

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | number | 0 |  |

### BoolValue

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | bool | false |  |

### EmoteOverride

*can be created with `Instance.new`*

Put it in StarterPlayer to swap one of the emote wheel's moves for your own animation in this place. **Slot** is the move it replaces (wave, dance, cheer, sit, clap, laugh), **Animation** the one to play instead (made in the Animator, `anim://12`), **Title** the name shown on the wheel.

| Property | Type | Default | Notes |
|---|---|---|---|
| Slot | [EmoteSlot](#emoteslot) | "dance" |  |
| Animation | animation | "" |  |
| Title | string | "" |  |

### Appearance

*can be created with `Instance.new`*

How players look **in this place only**: body colors, a **Face** and any **Accessories** (even ones they don't own), without touching their real avatar. Put one in StarterPlayer and everyone wears it when they join; turn on **KeepColors**, **KeepFace** or **KeepAccessories** to leave that part as the player's own. From a Script: `player:ApplyAppearance(app)` dresses one player, `player:ResetAppearance()` gives their own look back, and `game.Players:GetAppearanceAsync(player.UserId)` returns an Appearance with what they wear now, to change and apply.

| Property | Type | Default | Notes |
|---|---|---|---|
| HeadColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| TorsoColor | Color3 | Color3.fromHex("#baa4e2") |  |
| LeftArmColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| RightArmColor | Color3 | Color3.fromHex("#f5f1ec") |  |
| LeftLegColor | Color3 | Color3.fromHex("#302d38") |  |
| RightLegColor | Color3 | Color3.fromHex("#302d38") |  |
| Face | [Face](#face) | ":D" |  |
| Accessories | accessories | "" |  |
| KeepColors | bool | false |  |
| KeepFace | bool | false |  |
| KeepAccessories | bool | false |  |

### DynamicImage

*can be created with `Instance.new`*

A picture your scripts draw, pixel by pixel (up to 128x128): `:Fill`, `:SetPixel`, `:DrawRect`, `:DrawCircle`, `:DrawLine`, `:Clear`, `:GetPixel`. Show it with `label.Image = img:GetContent()` (also a Part's or a ParticleEmitter's Texture). Drawn on the server, everyone sees it; in a LocalScript, only you.

| Property | Type | Default | Notes |
|---|---|---|---|
| Width | number | 64 | min 1, max 128 |
| Height | number | 64 | min 1, max 128 |
| Data | string | "" | read-only |

**Methods:** `Fill(color, transparency)`, `Clear()`, `SetPixel(x, y, color, transparency)`, `GetPixel(x, y)`, `DrawRect(x, y, width, height, color, transparency)`, `DrawCircle(cx, cy, radius, color, transparency)`, `DrawLine(x1, y1, x2, y2, color, transparency)`, `GetContent()`

### IntValue

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | number | 0 |  |

### Vector3Value

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | Vector3 | Vector3.new(0, 0, 0) |  |

### Color3Value

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | Color3 | Color3.fromHex("#ffffff") |  |

### ObjectValue

*can be created with `Instance.new`*

| Property | Type | Default | Notes |
|---|---|---|---|
| Value | Instance |  |  |

### Team

*can be created with `Instance.new`*

A team inside the Teams service. **TeamColor** marks its players and its SpawnLocations; **AutoAssignable** teams take new players. `:GetPlayers()` lists who's on it.

| Property | Type | Default | Notes |
|---|---|---|---|
| TeamColor | Color3 | Color3.fromHex("#4f8cff") |  |
| AutoAssignable | bool | true |  |

**Methods:** `GetPlayers(team)`

**Events:** `PlayerAdded`, `PlayerRemoved`

## Enums

### PartShape

`Block`, `Ball`, `Cylinder`, `Wedge`

### Material

`Plastic`, `SmoothPlastic`, `Neon`, `Wood`, `Metal`, `Glass`, `Grass`, `Brick`, `Concrete`, `Fabric`, `Ice`, `Sand`

### Font

`Regular`, `Bold`, `Black`

### TextXAlignment

`Left`, `Center`, `Right`

### TextYAlignment

`Top`, `Center`, `Bottom`

### FillDirection

`Vertical`, `Horizontal`

### HorizontalAlignment

`Left`, `Center`, `Right`

### VerticalAlignment

`Top`, `Center`, `Bottom`

### SortOrder

`LayoutOrder`, `Name`

### ScaleType

`Stretch`, `Fit`, `Crop`

### ScrollingDirection

`Vertical`, `Horizontal`, `XY`

### CameraMode

`Classic`, `LockFirstPerson`, `LockThirdPerson`

### EasingStyle

`Linear`, `Quad`, `Cubic`, `Sine`, `Back`, `Bounce`, `Elastic`

### EasingDirection

`In`, `Out`, `InOut`

### SurfaceSide

`Front`, `Back`, `Top`, `Bottom`, `Left`, `Right`, `All`

### BuiltinSound

`pop`, `click`, `jump`, `coin`, `hurt`, `win`, `boing`, `whoosh`

### SkyPreset

`Day`, `Sunset`, `Night`, `Space`, `Overcast`, `Candy`, `Custom`

### CameraType

`Custom`, `Scriptable`, `Watch`, `Track`, `Follow`

### MouseBehavior

`Default`, `LockCenter`, `LockCurrentPosition`

### CoreGuiType

`Backpack`, `Health`, `Chat`, `Emotes`, `All`

### RaycastFilterType

`Exclude`, `Include`

### Face

`:D`, `:)`, `:3`, `:P`, `;)`, `:O`, `xD`, `B)`, `^_^`, `owo`, `uwu`, `>_<`, `T_T`, `-_-`, `:|`, `<3`, `>:)`

### EmoteSlot

`wave`, `dance`, `cheer`, `sit`, `clap`, `laugh`

### HighlightDepthMode

`AlwaysOnTop`, `Occluded`

### ParticleShape

`Box`, `Sphere`, `Point`

### EmitDirection

`Top`, `Bottom`, `Front`, `Back`, `Left`, `Right`

### NormalId

`Front`, `Back`, `Top`, `Bottom`, `Left`, `Right`
