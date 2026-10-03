-- ServerScriptService.Hotel: the hotel itself. Rooms are built as the doors open (a few
-- kept behind you), each with its door to the next one: open ones swing aside when you
-- come close, locked ones need the key that lies somewhere in the room. Drawers hold
-- coins, wardrobes hide you. Now and then the lights flicker and the Howl comes screaming
-- through every room: whoever isn't hiding dies. Twice the eyes appear on the walls and
-- the Watcher chases you through a run of halls. Door 100 is the way out.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)
local Assets = RS.Assets
local Remotes = RS.Remotes
local State = RS.State
local Store = game:GetService("DataStoreService"):GetDataStore("Hotel")

local LOBBY = RS.Config.LobbyPlaceId.Value
local H = 10 -- room height
local DOOR_W, DOOR_H = 4.4, 7.5
local KEEP_BEHIND = 4 -- rooms kept behind the newest one

local rng = Random.new()
local rooms = {} -- n -> room (see build)
local latest = 0 -- the newest room
local oldest = 0
local hidden = {} -- player -> wardrobe model
local coins = {} -- player -> coins this run
local alive = {} -- player -> true
local busy = false -- the Howl or the Watcher is out
local lastHowl = 0
local chaseAt = { rng:NextInteger(28, 36), rng:NextInteger(64, 72) }
local CHASE_LEN = 6
-- Studio tests: Config.Test = "howl" (it comes at door 2) or "chase" (the chase at door 3).
local testing = RS.Config:FindFirstChild("Test") and RS.Config.Test.Value or ""
if testing == "chase" then
	chaseAt = { 3, 64 }
end

local function isChase(n)
	for _, c in chaseAt do
		if n >= c and n < c + CHASE_LEN then
			return true
		end
	end
	return false
end

local function eyesBefore(n)
	for _, c in chaseAt do
		if n >= c - 3 and n < c then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------
-- Building blocks
-- ------------------------------------------------------------------------------------

local function part(parent, name, size, pos, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Anchored = true
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function sound(parent, id, volume, looped)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.Looped = looped == true
	s.Parent = parent
	return s
end

local function prompt(parent, action, object, dist)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.MaxActivationDistance = dist or 8
	p.Parent = parent
	return p
end

local function notice(player, key, ...)
	Remotes.Notice:FireClient(player, key, ...)
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local WALL = { Color3.fromHex("#5b4a5e"), Color3.fromHex("#4a5160"), Color3.fromHex("#5e5246"), Color3.fromHex("#3f5450") }
local CARPET = { Color3.fromHex("#6b2230"), Color3.fromHex("#2f3a5c"), Color3.fromHex("#4a3b2a"), Color3.fromHex("#2d4a3a") }
local WOOD = Color3.fromHex("#5a3b26")
local DARKWOOD = Color3.fromHex("#3a2618")

-- A ceiling lamp: a glowing shade and its light.
local function lamp(room, x, z, color)
	local m = room.model
	local shade = part(m, "Lamp", Vector3.new(1.6, 0.4, 1.6), Vector3.new(x, H - 0.4, z), color or Color3.fromHex("#ffd9a0"), { Material = "Neon", CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = color or Color3.fromHex("#ffcf8a")
	light.Brightness = room.kind == "dark" and 0.4 or 1.4
	light.Range = 18
	light.Offset = Vector3.new(0, -1, 0)
	light.Parent = shade
	table.insert(room.lights, light)
	return light
end

-- A wardrobe against a side wall, its front toward the middle of the room. Hide in it
-- (one at a time); the Howl walks past.
local function wardrobe(room, x, z, face)
	local m = Instance.new("Model")
	m.Name = "Wardrobe"
	m.Parent = room.model
	local d = 2.6 -- depth
	local w = 3.4
	local back = x - face * d / 2
	part(m, "Back", Vector3.new(0.3, 7, w), Vector3.new(back, 3.5, z), DARKWOOD)
	part(m, "SideA", Vector3.new(d, 7, 0.3), Vector3.new(x, 3.5, z - w / 2), DARKWOOD)
	part(m, "SideB", Vector3.new(d, 7, 0.3), Vector3.new(x, 3.5, z + w / 2), DARKWOOD)
	part(m, "Top", Vector3.new(d, 0.3, w), Vector3.new(x, 7, z), DARKWOOD)
	part(m, "Floor", Vector3.new(d, 0.3, w), Vector3.new(x, 0.15, z), DARKWOOD)
	local front = x + face * d / 2
	-- Two doors with a slit between them: you see out, the Howl doesn't see in.
	local doorA = part(m, "DoorA", Vector3.new(0.25, 6.6, w / 2 - 0.12), Vector3.new(front, 3.5, z - w / 4 - 0.06), WOOD)
	part(m, "DoorB", Vector3.new(0.25, 6.6, w / 2 - 0.12), Vector3.new(front, 3.5, z + w / 4 + 0.06), WOOD)
	part(m, "Knob", Vector3.new(0.3, 0.3, 0.3), Vector3.new(front + face * 0.2, 3.6, z - 0.3), Color3.fromHex("#c9a14a"), { Shape = "Ball", Material = "Metal" })
	local inside = Vector3.new(x, 1.2, z)
	local outside = Vector3.new(x + face * (d / 2 + 2.2), 1.2, z)
	local p = prompt(doorA, "$hide", "$wardrobe", 7)
	p.Triggered:Connect(function(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or not alive[player] then
			return
		end
		if hidden[player] == m then
			hidden[player] = nil
			m:SetAttribute("taken", false)
			player:Teleport(outside)
			hum.WalkSpeed = 9
			hum.CanJump = true
			player.CameraMaxZoom = 10
			p.ActionText = "$hide"
			return
		end
		if hidden[player] or m:GetAttribute("taken") then
			return
		end
		hidden[player] = m
		m:SetAttribute("taken", true)
		player:Teleport(inside)
		hum.WalkSpeed = 0
		hum.CanJump = false
		player.CameraMaxZoom = 0.5 -- inside: you look out through the slit
		p.ActionText = "$leave"
	end)
	table.insert(room.wardrobes, m)
end

-- A chest of drawers: each drawer has a few coins (or nothing).
local function drawers(room, x, z, face)
	local m = Instance.new("Model")
	m.Name = "Drawers"
	m.Parent = room.model
	part(m, "Body", Vector3.new(2, 3.2, 4), Vector3.new(x, 1.6, z), WOOD)
	for i = 1, 2 do
		local dr = part(m, "Drawer" .. i, Vector3.new(0.2, 1.1, 3.4), Vector3.new(x + face * 1.05, 0.85 + (i - 1) * 1.4, z), Color3.fromHex("#7a5434"))
		local p = prompt(dr, "$open", "$drawer", 6)
		p.Triggered:Connect(function(player)
			if not alive[player] then
				return
			end
			p:Destroy()
			sound(dr, Assets.Drawer.Value, 0.8):Play()
			dr.Position += Vector3.new(face * 0.8, 0, 0)
			local n = rng:NextInteger(0, 100) < 65 and rng:NextInteger(1, 4) or 0
			if n > 0 then
				coins[player] = (coins[player] or 0) + n
				local ls = player:FindFirstChild("leaderstats")
				if ls then
					ls.Coins.Value = coins[player]
				end
				notice(player, "got_coins", n)
			else
				notice(player, "empty")
			end
		end)
	end
end

-- The key to a locked door, lying on a little table.
local function key(room, x, z)
	part(room.model, "Table", Vector3.new(2.6, 2.6, 2.6), Vector3.new(x, 1.3, z), WOOD)
	local k = part(room.model, "Key", Vector3.new(0.4, 0.2, 1.2), Vector3.new(x, 2.75, z), Color3.fromHex("#f2c94c"), { Material = "Neon" })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex("#ffd36b")
	glow.Brightness = 1
	glow.Range = 6
	glow.Parent = k
	local p = prompt(k, "$take", "$key", 7)
	p.Triggered:Connect(function(player)
		if not alive[player] then
			return
		end
		k:Destroy()
		room.keyHolder = player
		local tool = Instance.new("Tool")
		tool.Name = "Key"
		tool.ToolTip = "$key"
		part(tool, "Handle", Vector3.new(0.3, 0.2, 1), Vector3.new(0, 0, 0), Color3.fromHex("#f2c94c"), { Material = "Neon", CanCollide = false })
		tool.Parent = player:FindFirstChildOfClass("Backpack")
		notice(player, "got_key", Shared.door(room.n + 1))
	end)
end

local function bed(room, x, z, face)
	part(room.model, "BedFrame", Vector3.new(6, 1.2, 4), Vector3.new(x + face * 1, 0.6, z), DARKWOOD)
	part(room.model, "Mattress", Vector3.new(5.8, 0.7, 3.8), Vector3.new(x + face * 1, 1.5, z), Color3.fromHex("#d8d2c4"))
	part(room.model, "Blanket", Vector3.new(3.8, 0.75, 3.9), Vector3.new(x + face * 2, 1.55, z), Color3.fromHex("#7a2a3a"))
	part(room.model, "Pillow", Vector3.new(1.2, 0.5, 3), Vector3.new(x - face * 1.2, 2.0, z), Color3.fromHex("#f0ece2"))
	part(room.model, "Headboard", Vector3.new(0.4, 3.4, 4.2), Vector3.new(x - face * 2, 1.7, z), DARKWOOD)
end

local function shelf(room, x, z, along)
	local size = along and Vector3.new(6, 6.5, 1.4) or Vector3.new(1.4, 6.5, 6)
	part(room.model, "Shelf", size, Vector3.new(x, 3.25, z), DARKWOOD)
	for i = 1, 3 do
		local bs = along and Vector3.new(5.4, 0.2, 1.5) or Vector3.new(1.5, 0.2, 5.4)
		part(room.model, "Board", bs, Vector3.new(x, i * 1.9, z), WOOD)
		for j = 1, rng:NextInteger(2, 5) do
			local off = rng:NextNumber(-2.4, 2.4)
			local bp = along and Vector3.new(x + off, i * 1.9 + 0.6, z) or Vector3.new(x, i * 1.9 + 0.6, z + off)
			part(room.model, "Book", Vector3.new(0.35, 1, 0.35) + (along and Vector3.new(0, 0, 0.6) or Vector3.new(0.6, 0, 0)), bp,
				Color3.fromHSV(rng:NextNumber(0, 1), 0.5, 0.45))
		end
	end
end

local function painting(room, x, y, z, face)
	local w = rng:NextNumber(2, 3.5)
	part(room.model, "Frame", Vector3.new(0.2, w * 0.8, w), Vector3.new(x, y, z), Color3.fromHex("#8a6a2a"), { Material = "Metal" })
	part(room.model, "Canvas", Vector3.new(0.22, w * 0.8 - 0.4, w - 0.4), Vector3.new(x + face * 0.02, y, z), Color3.fromHSV(rng:NextNumber(0, 1), 0.35, 0.3))
end

-- The Watcher's eyes, painted on the walls before it comes.
local function eyes(room)
	for i = 1, rng:NextInteger(3, 6) do
		local side = rng:NextInteger(0, 1) == 0 and -1 or 1
		local x = room.cx + side * (room.w / 2 - 0.15)
		local z = room.z0 - rng:NextNumber(2, room.len - 2)
		local y = rng:NextNumber(2.5, 7.5)
		local p = part(room.model, "Eye", Vector3.new(0.1, 1.6, 2.6), Vector3.new(x, y, z), room.wall, { CanCollide = false })
		local d = Instance.new("Decal")
		d.Texture = Assets.Eye.Value
		d.Face = side < 0 and "Right" or "Left"
		d.Parent = p
	end
end

-- ------------------------------------------------------------------------------------
-- Rooms
-- ------------------------------------------------------------------------------------

local function pickKind(n)
	if n == 0 then
		return "start"
	elseif n >= Shared.LAST_DOOR then
		return "exit"
	elseif isChase(n) then
		return "chase"
	end
	local r = rng:NextNumber()
	if r < 0.32 then
		return "hall"
	elseif r < 0.62 then
		return "bedroom"
	elseif r < 0.84 or n < 10 then
		return "storage"
	end
	return "dark"
end

-- Room n: from the doorway it's entered by (x, z0) away down -Z. Its own exit door, to
-- room n + 1, is in its far wall.
local function build(n, entranceX, z0)
	local kind = pickKind(n)
	local room = { n = n, kind = kind, z0 = z0, lights = {}, wardrobes = {}, opened = false }
	local w, len
	if kind == "hall" or kind == "chase" then
		w, len = 12, rng:NextInteger(30, 42)
	elseif kind == "bedroom" then
		w, len = rng:NextInteger(18, 22), rng:NextInteger(18, 24)
	elseif kind == "start" then
		w, len = 16, 20
	elseif kind == "exit" then
		w, len = 20, 24
	else
		w, len = rng:NextInteger(16, 20), rng:NextInteger(20, 28)
	end
	local room_margin = w / 2 - 3.2
	local cx = entranceX + (n == 0 and 0 or rng:NextNumber(-room_margin, room_margin))
	local exitX = cx + rng:NextNumber(-room_margin, room_margin)
	if kind == "exit" then
		exitX = cx
	end
	local z1 = z0 - len
	room.w, room.len, room.cx, room.z1, room.entranceX, room.exitX = w, len, cx, z1, entranceX, exitX
	room.wall = WALL[rng:NextInteger(1, #WALL)]
	local m = Instance.new("Model")
	m.Name = "Room" .. n
	m.Parent = workspace.Rooms
	room.model = m
	local mid = (z0 + z1) / 2
	local carpet = kind == "chase" and Color3.fromHex("#3a1418") or CARPET[rng:NextInteger(1, #CARPET)]
	part(m, "Floor", Vector3.new(w, 1, len), Vector3.new(cx, -0.5, mid), carpet, { Material = "Fabric" })
	part(m, "Ceiling", Vector3.new(w, 1, len), Vector3.new(cx, H + 0.5, mid), Color3.fromHex("#2a2530"))
	for _, side in { -1, 1 } do
		part(m, "Wall", Vector3.new(1, H, len), Vector3.new(cx + side * (w / 2 + 0.5), H / 2, mid), room.wall)
		-- Wood panels along the bottom, and a trim on top of them.
		part(m, "Panel", Vector3.new(0.2, 3, len), Vector3.new(cx + side * (w / 2 - 0.1), 1.5, mid), DARKWOOD, { CanCollide = false })
		part(m, "Trim", Vector3.new(0.3, 0.25, len), Vector3.new(cx + side * (w / 2 - 0.15), 3.05, mid), Color3.fromHex("#8a6a2a"), { CanCollide = false })
	end
	-- The far wall, with the doorway to the next room.
	local leftW = (exitX - DOOR_W / 2) - (cx - w / 2)
	local rightW = (cx + w / 2) - (exitX + DOOR_W / 2)
	part(m, "FarWallL", Vector3.new(leftW + 1, H, 1), Vector3.new(cx - w / 2 + leftW / 2 - 0.5, H / 2, z1 - 0.5), room.wall)
	part(m, "FarWallR", Vector3.new(rightW + 1, H, 1), Vector3.new(cx + w / 2 - rightW / 2 + 0.5, H / 2, z1 - 0.5), room.wall)
	part(m, "Lintel", Vector3.new(DOOR_W, H - DOOR_H, 1), Vector3.new(exitX, DOOR_H + (H - DOOR_H) / 2, z1 - 0.5), room.wall)
	-- Behind you: shut once the room before is gone (a wall where its doorway was).
	room.back = part(m, "BackWall", Vector3.new(w, H, 1), Vector3.new(cx, H / 2, z0 + 0.5), room.wall,
		{ Transparency = n == 0 and 0 or 1, CanCollide = n == 0 })
	if n > 0 then
		-- The bits of this room's near wall beside the doorway it's entered by.
		local nl = (entranceX - DOOR_W / 2) - (cx - w / 2)
		local nr = (cx + w / 2) - (entranceX + DOOR_W / 2)
		if nl > 0.05 then
			part(m, "NearWallL", Vector3.new(nl, H, 1), Vector3.new(cx - w / 2 + nl / 2, H / 2, z0 + 0.5), room.wall)
		end
		if nr > 0.05 then
			part(m, "NearWallR", Vector3.new(nr, H, 1), Vector3.new(cx + w / 2 - nr / 2, H / 2, z0 + 0.5), room.wall)
		end
	end
	-- The door and its number plate.
	if kind ~= "exit" then
		local door = part(m, "Door", Vector3.new(DOOR_W - 0.1, DOOR_H, 0.35), Vector3.new(exitX, DOOR_H / 2, z1 - 0.5), Color3.fromHex("#4a2c1a"))
		part(door, "DoorKnob", Vector3.new(0.3, 0.3, 0.5), Vector3.new(exitX + DOOR_W / 2 - 0.6, 3.6, z1 - 0.2), Color3.fromHex("#c9a14a"), { Shape = "Ball", Material = "Metal", CanCollide = false })
		room.door = door
		part(m, "Plate", Vector3.new(2.6, 1.1, 0.1), Vector3.new(exitX, DOOR_H + 0.9, z1 + 0.05), Color3.fromHex("#8a6a2a"), { Material = "Metal", CanCollide = false })
		local plate = Instance.new("Text3D")
		plate.Text = Shared.door(n + 1)
		plate.Position = Vector3.new(exitX, DOOR_H + 0.9, z1 + 0.12)
		plate.TextSize = 110
		plate.TextColor = Color3.fromHex("#f2d48a")
		plate.Font = "Black"
		plate.Parent = m
		room.locked = kind ~= "chase" and n >= 4 and rng:NextNumber() < 0.2 and not (rooms[n - 1] and rooms[n - 1].locked)
	end
	-- Lights.
	local lampColor = kind == "chase" and Color3.fromHex("#ff5040") or nil
	local step = kind == "dark" and len or 9
	local z = z0 - step / 2
	while z > z1 do
		if kind ~= "dark" or rng:NextNumber() < 0.6 then
			lamp(room, cx, z, lampColor)
		end
		z -= step
	end
	-- What's in it.
	local function along(t)
		return z0 - len * t
	end
	if kind == "start" then
		local sign = Instance.new("Text3D")
		sign.Text = "$welcome"
		sign.Position = Vector3.new(cx, 6.5, z0 - 0.1)
		sign.Rotation = Vector3.new(0, 180, 0)
		sign.TextSize = 36
		sign.TextColor = Color3.fromHex("#f2d48a")
		sign.Parent = m
		drawers(room, cx + w / 2 - 1.2, along(0.5), -1)
		wardrobe(room, cx - w / 2 + 1.5, along(0.5), 1)
	elseif kind == "exit" then
		-- Daylight through the last doorway.
		local out = part(m, "Outside", Vector3.new(DOOR_W, DOOR_H, 0.4), Vector3.new(exitX, DOOR_H / 2, z1 - 0.3), Color3.fromHex("#fff6d8"), { Material = "Neon", CanCollide = false })
		local sun = Instance.new("PointLight")
		sun.Color = Color3.fromHex("#fff2c8")
		sun.Brightness = 3
		sun.Range = 40
		sun.Offset = Vector3.new(0, 0, 4)
		sun.Parent = out
		local sign = Instance.new("Text3D")
		sign.Text = "$way_out"
		sign.Position = Vector3.new(exitX, DOOR_H + 1, z1 + 0.05)
		sign.TextSize = 44
		sign.TextColor = Color3.fromHex("#9cffb0")
		sign.Font = "Black"
		sign.Parent = m
		room.exit = out
	elseif kind == "bedroom" then
		local side = rng:NextInteger(0, 1) == 0 and -1 or 1
		bed(room, cx + side * (w / 2 - 3.5), along(0.35), -side)
		wardrobe(room, cx - side * (w / 2 - 1.5), along(0.4), side)
		if rng:NextNumber() < 0.6 then
			wardrobe(room, cx + side * (w / 2 - 1.5), along(0.8), -side)
		end
		drawers(room, cx - side * (w / 2 - 1.2), along(0.75), side)
		painting(room, cx + side * (w / 2 - 0.1), 6, along(0.6), -side)
	elseif kind == "storage" then
		for i = 1, rng:NextInteger(2, 4) do
			shelf(room, cx + (i % 2 == 0 and -1 or 1) * (w / 2 - 1.2), along(i / 5), false)
		end
		for i = 1, rng:NextInteger(3, 7) do
			local s = rng:NextNumber(1.2, 2.4)
			part(m, "Box", Vector3.new(s, s, s), Vector3.new(cx + rng:NextNumber(-w / 2 + 2, w / 2 - 2), s / 2, along(rng:NextNumber(0.15, 0.85))),
				Color3.fromHex("#8a6a44"), { Rotation = Vector3.new(0, rng:NextNumber(0, 90), 0) })
		end
		wardrobe(room, cx - w / 2 + 1.5, along(0.9), 1)
		drawers(room, cx + w / 2 - 1.2, along(0.9), -1)
	elseif kind == "hall" or kind == "dark" then
		for i = 1, 3 do
			painting(room, cx + (i % 2 == 0 and -1 or 1) * (w / 2 - 0.1), 5.5, along(i / 4), i % 2 == 0 and 1 or -1)
		end
		-- A wardrobe against one wall, facing the middle; maybe drawers by the other.
		local side = rng:NextInteger(0, 1) == 0 and -1 or 1
		wardrobe(room, cx + side * (w / 2 - 1.5), along(0.55), -side)
		if rng:NextNumber() < 0.5 then
			drawers(room, cx - side * (w / 2 - 1.2), along(0.25), side)
		end
	elseif kind == "chase" then
		-- Fallen shelves to dodge.
		for i = 1, 2 do
			local x = cx + (rng:NextInteger(0, 1) == 0 and -1 or 1) * rng:NextNumber(1.5, 3)
			part(m, "Fallen", Vector3.new(4, 2.2, 1.2), Vector3.new(x, 1.1, along(i / 3)), DARKWOOD, { Rotation = Vector3.new(0, rng:NextNumber(-30, 30), 0) })
		end
	end
	if room.locked then
		key(room, cx + rng:NextNumber(-w / 2 + 3, w / 2 - 3), along(rng:NextNumber(0.3, 0.7)))
		local p = prompt(room.door, "$unlock", "$locked_door", 8)
		room.lockPrompt = p
		p.Triggered:Connect(function(player)
			local tool = player.Character and player.Character:FindFirstChild("Key") or player:FindFirstChildOfClass("Backpack"):FindFirstChild("Key")
			if not tool then
				notice(player, "need_key")
				return
			end
			tool:Destroy()
			room.locked = false
			p:Destroy()
		end)
	end
	if eyesBefore(n) then
		eyes(room)
	end
	rooms[n] = room
	latest = math.max(latest, n)
	return room
end

-- Swings the door aside (into the wall) and builds what's behind it.
local openDoor

local function forget(n)
	local r = rooms[n]
	if not r then
		return
	end
	r.model:Destroy()
	rooms[n] = nil
	if rooms[n + 1] then
		rooms[n + 1].back.Transparency = 0
		rooms[n + 1].back.CanCollide = true
	end
end

-- Old rooms nobody is in any more go away.
local function tidy()
	while oldest < latest - KEEP_BEHIND do
		local r = rooms[oldest]
		local someone = false
		for player in alive do
			local root = rootOf(player)
			if r and root and root.Position.Z <= r.z0 + 1 and root.Position.Z >= r.z1 - 1 then
				someone = true
			end
		end
		if someone then
			return
		end
		forget(oldest)
		oldest += 1
	end
end

-- ------------------------------------------------------------------------------------
-- Monsters
-- ------------------------------------------------------------------------------------

local function kill(player, why)
	if not alive[player] then
		return
	end
	alive[player] = nil
	hidden[player] = nil
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
	end
	Remotes.Died:FireClient(player, why)
end

-- The path through the rooms that are standing: doorway, middle, next doorway...
local function path(from, to)
	local pts = {}
	for n = from, to do
		local r = rooms[n]
		if r then
			table.insert(pts, Vector3.new(r.entranceX, 4, r.z0 + 0.5))
			table.insert(pts, Vector3.new(r.cx, 4, (r.z0 + r.z1) / 2))
			table.insert(pts, Vector3.new(r.exitX, 4, r.z1 - 0.5))
		end
	end
	return pts
end

local function roomAt(z)
	for _, r in rooms do
		if z <= r.z0 + 0.5 and z >= r.z1 - 0.5 then
			return r
		end
	end
	return nil
end

-- The Howl: the lights flicker and something rumbles, then it screams through every room
-- standing, from the oldest to the newest. Whoever isn't in a wardrobe dies.
local function howl()
	busy = true
	lastHowl = latest
	local near = workspace.HowlNear
	near.Playing = true
	for i = 1, 14 do
		for n = oldest, latest do
			local r = rooms[n]
			if r then
				for _, l in r.lights do
					l.Enabled = i % 2 == 0 or rng:NextNumber() < 0.3
				end
			end
		end
		task.wait(0.18)
	end
	for n = oldest, latest do
		if rooms[n] then
			for _, l in rooms[n].lights do
				l.Enabled = true
			end
		end
	end
	task.wait(1.5)
	local pts = path(oldest, latest)
	local h = part(workspace, "Howl", Vector3.new(2, 2, 2), pts[1], Color3.new(0, 0, 0), { Transparency = 1, CanCollide = false, CanTouch = false })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(9, 0, 9, 0)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.MaxDistance = 400
	bb.Parent = h
	local img = Instance.new("ImageLabel")
	img.Image = Assets.Howl.Value
	img.Size = UDim2.new(1, 0, 1, 0)
	img.BackgroundTransparency = 1
	img.Parent = bb
	local red = Instance.new("PointLight")
	red.Color = Color3.fromHex("#ff3020")
	red.Brightness = 3
	red.Range = 22
	red.Parent = h
	sound(h, Assets.HowlScream.Value, 1.5, true).Playing = true
	local speed = 70
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		local t = 0
		while t < len do
			t += speed * 0.05
			h.Position = a:Lerp(b, math.min(t / len, 1))
			-- Everyone in the room it's in, not hiding: gone.
			local r = roomAt(h.Position.Z)
			if r then
				for player in alive do
					local root = rootOf(player)
					local p = root and root.Position
					if p and not hidden[player] and p.Z <= r.z0 + 0.5 and p.Z >= r.z1 - 0.5 and math.abs(p.X - r.cx) <= r.w / 2 + 1 then
						kill(player, "howl")
					end
				end
				-- And it breaks a few lights on the way.
				for _, l in r.lights do
					if rng:NextNumber() < 0.01 then
						l.Enabled = false
					end
				end
			end
			task.wait(0.05)
		end
	end
	h:Destroy()
	near.Playing = false
	busy = false
end

-- The Watcher: comes out of the dark behind you in the first chase hall and runs after
-- you through all of them. Run! The door at the far end slams in its face.
local function chase(first)
	busy = true
	local last = first + CHASE_LEN - 1
	workspace.HotelHum.Playing = false
	workspace.ChaseMusic.Playing = true
	-- The lights of the halls ahead go red, and a moment to start running.
	for n = first, last do
		if rooms[n] then
			for _, l in rooms[n].lights do
				l.Brightness = 2
			end
		end
	end
	task.wait(2.5)
	local pts = path(first - 1, last)
	-- Arc length along the path, to know who's ahead of whom.
	local acc = { 0 }
	for i = 2, #pts do
		acc[i] = acc[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local function at(s)
		for i = 2, #pts do
			if s <= acc[i] then
				local k = (s - acc[i - 1]) / math.max(acc[i] - acc[i - 1], 0.001)
				return pts[i - 1]:Lerp(pts[i], k), (pts[i] - pts[i - 1]).Unit
			end
		end
		return pts[#pts], Vector3.new(0, 0, -1)
	end
	local function progress(p)
		local best, bestD = 0, math.huge
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			local ab = b - a
			local k = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
			local q = a + ab * k
			local d = Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude
			if d < bestD then
				best, bestD = acc[i - 1] + ab.Magnitude * k, d
			end
		end
		return best
	end
	local rig = Instance.new("Rig")
	rig.Name = "Watcher"
	rig.DisplayName = ""
	for _, k in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
		rig[k] = Color3.fromHex("#050407")
	end
	rig.Face = "-_-"
	-- Tall and thin, long arms, a big head.
	rig.HeadScale = Vector3.new(1.3, 1.3, 1.3)
	rig.TorsoScale = Vector3.new(0.9, 1.3, 0.9)
	rig.LeftArmScale = Vector3.new(0.7, 1.7, 0.7)
	rig.RightArmScale = Vector3.new(0.7, 1.7, 0.7)
	rig.LeftLegScale = Vector3.new(0.8, 1.35, 0.8)
	rig.RightLegScale = Vector3.new(0.8, 1.35, 0.8)
	rig.CanCollide = false
	rig.Animation = "run"
	rig.AnimationSpeed = 1.4
	rig.Position = pts[1]
	rig.Parent = workspace
	-- One red eye in the middle of its face, lighting it up from the front.
	local eye = part(workspace, "WatcherEye", Vector3.new(0.6, 0.6, 0.6), pts[1], Color3.fromHex("#ff3b2a"), { Shape = "Ball", Material = "Neon", CanCollide = false, CanTouch = false })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex("#ff2a1a")
	glow.Brightness = 2.5
	glow.Range = 12
	glow.Offset = Vector3.new(0, 0, 0)
	glow.Parent = eye
	local s = 0
	local speed = 11.5
	local goal = acc[#acc]
	while true do
		speed = math.min(speed + 0.05 * 0.08, 13.5)
		s += speed * 0.05
		local pos, dir = at(s)
		rig.Position = Vector3.new(pos.X, 0, pos.Z)
		rig.Rotation = Vector3.new(0, math.deg(math.atan2(-dir.X, -dir.Z)), 0)
		eye.Position = Vector3.new(pos.X, 2.0, pos.Z) + dir * 0.8
		local left = 0
		for player in alive do
			local root = rootOf(player)
			if root then
				local ps = progress(root.Position)
				if ps < goal then
					left += 1
				end
				if ps <= s + 1.2 and (root.Position - Vector3.new(pos.X, root.Position.Y, pos.Z)).Magnitude < 4 then
					kill(player, "watcher")
				end
			end
		end
		if left == 0 or s >= goal then
			break
		end
		task.wait(0.05)
	end
	-- Slam! The last door shuts behind the ones who made it.
	local r = rooms[last]
	if r and r.door then
		TweenService:Create(r.door, TweenInfo.new(0.15), { Position = r.doorShut }):Play()
		sound(r.door, Assets.Door.Value, 1.2):Play()
	end
	rig:Destroy()
	eye:Destroy()
	workspace.ChaseMusic.Playing = false
	workspace.HotelHum.Playing = true
	task.wait(1)
	-- (it opens again for whoever is past it)
	if r and r.door then
		TweenService:Create(r.door, TweenInfo.new(0.5), { Position = r.doorOpen }):Play()
	end
	busy = false
end

-- ------------------------------------------------------------------------------------
-- Doors
-- ------------------------------------------------------------------------------------

function openDoor(room)
	if room.opened or not room.door then
		return
	end
	room.opened = true
	local nextRoom = rooms[room.n + 1] or build(room.n + 1, room.exitX, room.z1 - 1)
	-- A chase: its halls are all built at once, their doors already open.
	if nextRoom.kind == "chase" and not rooms[room.n + 2] then
		local r = nextRoom
		while r.kind == "chase" and r.n < Shared.LAST_DOOR do
			local nr = build(r.n + 1, r.exitX, r.z1 - 1)
			r.doorShut = r.door.Position
			r.doorOpen = r.door.Position + Vector3.new(DOOR_W, 0, 0)
			r.door.Position = r.doorOpen
			r.opened = true
			r = nr
		end
	end
	room.doorShut = room.door.Position
	room.doorOpen = room.door.Position + Vector3.new(DOOR_W, 0, 0)
	TweenService:Create(room.door, TweenInfo.new(0.6, "Quad", "Out"), { Position = room.doorOpen }):Play()
	sound(room.door, Assets.Door.Value, 0.9):Play()
	State.Door.Value = math.max(State.Door.Value, room.n + 1)
	tidy()
	-- What comes through it.
	local d = room.n + 1
	if busy then
		return
	end
	for _, c in chaseAt do
		if d == c then
			task.spawn(chase, c)
			return
		end
	end
	if (testing == "howl" and d == 2) or d >= 6 and d < Shared.LAST_DOOR - 1 and d - lastHowl >= 5 and not isChase(d) and not isChase(d + 1) and rng:NextNumber() < 0.24 then
		task.delay(rng:NextNumber(1, 4), function()
			if not busy then
				howl()
			end
		end)
	end
end

-- ------------------------------------------------------------------------------------
-- Players
-- ------------------------------------------------------------------------------------

local function save(player, escaped)
	local door = State.Door.Value
	local ok, data = pcall(function()
		return Store:GetAsync(Shared.key(player))
	end)
	if not ok then
		return
	end
	data = type(data) == "table" and data or Shared.blank()
	data.coins = (data.coins or 0) + (coins[player] or 0) + (escaped and 30 or 0)
	data.best = math.max(data.best or 0, escaped and Shared.LAST_DOOR or door)
	data.escapes = (data.escapes or 0) + (escaped and 1 or 0)
	pcall(function()
		Store:SetAsync(Shared.key(player), data)
	end)
	coins[player] = 0
end

local function backToLobby(player, data)
	if player.Parent and LOBBY ~= "" then
		TeleportService:Teleport(LOBBY, player, data)
	end
end

Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	local c = Instance.new("IntValue")
	c.Name = "Coins"
	c.Parent = ls
	coins[player] = 0
	player.CharacterAdded:Connect(function(character)
		local hum = character:WaitForChild("Humanoid")
		alive[player] = true
		player.CameraMaxZoom = 10
		hum.Died:Connect(function()
			if alive[player] then
				alive[player] = nil
				hidden[player] = nil
				Remotes.Died:FireClient(player, "fall")
			end
			local reached = State.Door.Value
			save(player, false)
			task.wait(6)
			backToLobby(player, { door = reached, died = true })
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	if alive[player] or (coins[player] or 0) > 0 then
		save(player, false)
	end
	alive[player] = nil
	hidden[player] = nil
end)

-- The way out at door 100.
local function escape(player)
	if not alive[player] then
		return
	end
	alive[player] = nil
	save(player, true)
	Remotes.Escaped:FireClient(player)
	task.wait(5)
	backToLobby(player, { door = Shared.LAST_DOOR, escaped = true })
end

-- The first rooms, then the watch over the doors.
workspace.HotelHum.Playing = true
build(0, 0, 0)

while true do
	task.wait(0.1)
	for n = math.max(oldest, latest - 2), latest do
		local room = rooms[n]
		if room and room.door and not room.opened and not room.locked then
			for player in alive do
				local root = rootOf(player)
				if root and (root.Position - room.door.Position).Magnitude < 8 then
					openDoor(room)
					break
				end
			end
		end
		if room and room.exit then
			for player in alive do
				local root = rootOf(player)
				if root and (root.Position - room.exit.Position).Magnitude < 4 then
					task.spawn(escape, player)
				end
			end
		end
	end
end
