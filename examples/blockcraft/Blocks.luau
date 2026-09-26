-- Draws the world around the player: 16x16 chunks load as you walk and far ones
-- unload. Only blocks you could actually see become parts (buried ones are skipped),
-- and same blocks lying side by side merge into one big part per layer.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
-- (Apps before 1.4.2 give LocalScripts no `workspace` global, so fetch it.)
local workspace = game:GetService("Workspace")
local World = require(RS:WaitForChild("World"))
local BlockEvent = RS:WaitForChild("BlockEvent")
local GetEdits = RS:WaitForChild("GetEdits")

-- Chunks around the player: 5x5 on computers, 3x3 on phones (with closer fog).
local RADIUS = game:GetService("UserInputService").TouchEnabled and 1 or 2
local CHUNK = World.CHUNK

local player = Players.LocalPlayer
if RADIUS < 2 then
	game:GetService("Lighting").FogEnd = 40
end

local folder = Instance.new("Folder")
folder.Name = "Blocks"
folder.Parent = workspace
World.folder = folder

local loaded = {} -- chunk key -> Folder
local coords = {} -- chunk key -> { cx, cz }
local queued = {} -- chunk key -> true (needs a rebuild)

local function makePart(parent, block, x, y, z, w, d, h)
	local info = World.BLOCKS[block]
	local p = Instance.new("Part")
	p.Name = block
	p.Size = Vector3.new(w, h, d)
	p.Position = Vector3.new(x + w / 2, y + h / 2, z + d / 2)
	p.Color = info.color
	p.Material = info.material
	p.Transparency = info.transparency or 0
	p.CanCollide = not info.liquid
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
end

local function buildChunk(cx, cz)
	local x0, z0 = cx * CHUNK, cz * CHUNK
	local read, heights = World.reader(x0 - 1, z0 - 1, x0 + CHUNK, z0 + CHUNK)
	-- How deep to look: the lowest ground (or water bed) around, and anything players dug.
	local low = World.HEIGHT
	for x = x0 - 1, x0 + CHUNK do
		for z = z0 - 1, z0 + CHUNK do
			local h = World.height(x, z)
			heights[(x + 1024) * 2048 + (z + 1024)] = h
			low = math.min(low, h)
		end
	end
	low = math.min(low, World.WATER) - 1
	local floor = World.editFloor[World.chunkKey(cx, cz)]
	for _, n in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local f = World.editFloor[World.chunkKey(cx + n[1], cz + n[2])]
		if f then
			floor = math.min(floor or f, f)
		end
	end
	if floor then
		low = math.min(low, floor - 1)
	end

	local model = Instance.new("Folder")
	model.Name = cx .. "," .. cz
	local N = CHUNK * CHUNK
	local grid = table.create(N) -- block in each cell of the layer (false = air)
	local seen = table.create(N) -- can you see it?
	local used = table.create(N)
	-- Boxes still growing upwards: an identical rectangle on the next layer makes them taller.
	local open = {}
	for y = math.max(low, 0), World.HEIGHT do
		local any = false
		if y < World.HEIGHT then
			for lz = 0, CHUNK - 1 do
				for lx = 0, CHUNK - 1 do
					local i = lx + lz * CHUNK + 1
					local b = read(x0 + lx, y, z0 + lz)
					if b ~= "Air" then
						grid[i] = b
						local vis = World.exposed(read, x0 + lx, y, z0 + lz, b)
						seen[i] = vis
						any = any or vis
					else
						grid[i] = false
						seen[i] = false
					end
					used[i] = false
				end
			end
		end
		local nextOpen = {}
		if any then
			-- Greedy: start at a visible block and grow the widest rectangle of the same
			-- kind. Hidden blocks of that kind may be swallowed too (nobody sees the inside).
			for lz = 0, CHUNK - 1 do
				for lx = 0, CHUNK - 1 do
					local i = lx + lz * CHUNK + 1
					local b = grid[i]
					if b and seen[i] and not used[i] then
						local w = 1
						while lx + w < CHUNK and grid[i + w] == b and not used[i + w] do
							w += 1
						end
						local d = 1
						while lz + d < CHUNK do
							local ok = true
							for k = 0, w - 1 do
								local j = lx + k + (lz + d) * CHUNK + 1
								if grid[j] ~= b or used[j] then
									ok = false
									break
								end
							end
							if not ok then
								break
							end
							d += 1
						end
						for dz = 0, d - 1 do
							for k = 0, w - 1 do
								used[lx + k + (lz + dz) * CHUNK + 1] = true
							end
						end
						local key = string.format("%s|%d|%d|%d|%d", b, lx, lz, w, d)
						local box = open[key]
						if box then
							box.h += 1
							open[key] = nil
						else
							box = { b = b, x = x0 + lx, y = y, z = z0 + lz, w = w, d = d, h = 1 }
						end
						nextOpen[key] = box
					end
				end
			end
		end
		-- Boxes that didn't continue on this layer are finished.
		for _, box in open do
			makePart(model, box.b, box.x, box.y, box.z, box.w, box.d, box.h)
		end
		open = nextOpen
	end
	return model
end

local function load(cx, cz)
	local ck = World.chunkKey(cx, cz)
	local fresh = buildChunk(cx, cz)
	fresh.Parent = folder
	local old = loaded[ck]
	loaded[ck] = fresh
	coords[ck] = { cx, cz }
	queued[ck] = nil
	if old then
		old:Destroy()
	end
end

-- Rebuilds the chunk of a changed cell (and the neighbour it borders).
local function changed(x, z)
	local cx, cz = x // CHUNK, z // CHUNK
	for _, c in { { cx, cz }, { (x - 1) // CHUNK, cz }, { (x + 1) // CHUNK, cz }, { cx, (z - 1) // CHUNK }, { cx, (z + 1) // CHUNK } } do
		local ck = World.chunkKey(c[1], c[2])
		if loaded[ck] and not queued[ck] then
			queued[ck] = c
		end
	end
end

BlockEvent.OnClientEvent:Connect(function(what, x, y, z, block)
	if what == "set" then
		World.setEdit(x, y, z, block)
		changed(x, z)
	end
end)

-- What others already built before we came.
World.applyEditList(GetEdits:InvokeServer())

local function rootPosition()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- Keep the chunks around the player: nearest missing one first, one per frame.
while true do
	local todo = {}
	for _, c in queued do
		table.insert(todo, c)
	end
	for _, c in todo do
		load(c[1], c[2])
	end
	local pos = rootPosition()
	if pos then
		local pcx, pcz = math.floor(pos.X / CHUNK), math.floor(pos.Z / CHUNK)
		local best, bestD = nil, math.huge
		for dx = -RADIUS, RADIUS do
			for dz = -RADIUS, RADIUS do
				local cx, cz = pcx + dx, pcz + dz
				local inWorld = cx * CHUNK < World.SIZE and (cx + 1) * CHUNK > -World.SIZE and cz * CHUNK < World.SIZE and (cz + 1) * CHUNK > -World.SIZE
				local d = dx * dx + dz * dz
				if inWorld and not loaded[World.chunkKey(cx, cz)] and d < bestD then
					best, bestD = { cx, cz }, d
				end
			end
		end
		if best then
			load(best[1], best[2])
		end
		-- Chunks we walked away from go away.
		for ck, f in loaded do
			local c = coords[ck]
			if math.max(math.abs(c[1] - pcx), math.abs(c[2] - pcz)) > RADIUS + 1 then
				f:Destroy()
				loaded[ck] = nil
				coords[ck] = nil
			end
		end
	end
	task.wait()
end
