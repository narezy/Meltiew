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

**Methods:** `FindFirstChild(name, recursive)`, `FindFirstChildOfClass(className)`, `FindFirstChildWhichIsA(className, recursive)`, `FindFirstAncestor(name)`, `FindFirstAncestorOfClass(className)`, `FindFirstAncestorWhichIsA(className)`, `WaitForChild(name, timeout)`, `GetChildren()`, `GetDescendants()`, `IsA(className)`, `IsDescendantOf(other)`, `IsAncestorOf(other)`, `GetFullName()`, `Destroy()`, `Remove()`, `Clone()`, `ClearAllChildren()`, `GetPropertyChangedSignal(prop)`, `SetAttribute(name, value)`, `GetAttribute(name)`

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

**Methods:** `GetMouse()`, `Kick(message)`, `LoadCharacter()`, `Teleport(pos)`

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
| AutoHeal | bool | true |  |
| HealthRegen | number | 1 | min 0 |
| EmotesEnabled | bool | true |  |

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

**Methods:** `Raycast(origin, direction, params)`, `GetPartBoundsInRadius(position, radius, params)`

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

**Methods:** `GetPlayers()`, `GetPlayerByUserId(id)`, `GetPlayerFromCharacter(model)`

**Events:** `PlayerAdded`, `PlayerRemoving`

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

### Text3D

*can be created with `Instance.new`*

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

**Methods:** `PlayAnimation(anim)`, `StopAnimation()`

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

`:D`, `:)`, `:3`, `:P`, `;)`, `:O`, `xD`, `B)`, `^_^`, `owo`, `uwu`, `>_<`, `T_T`, `-_-`, `:|`, `<3`

### EmoteSlot

`wave`, `dance`, `cheer`, `sit`, `clap`, `laugh`
