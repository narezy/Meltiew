-- BlockCraft world: the same terrain on the server and on every player's device.
-- Nothing is stored except what players changed: every other block comes from
-- noise, so the server only keeps (and sends) the edits.

local World = {}

World.SIZE = 128 -- the world spans -SIZE .. SIZE-1 on X and Z
World.HEIGHT = 48
World.CHUNK = 16
World.WATER = 13
World.MAX_EDITS = 20000

World.BLOCKS = {
	Grass = { color = Color3.fromHex("#6cbf49"), material = "Grass" },
	Dirt = { color = Color3.fromHex("#8a5a36"), material = "Sand" },
	Stone = { color = Color3.fromHex("#8d8d93"), material = "Concrete" },
	Cobblestone = { color = Color3.fromHex("#6f6f76"), material = "Brick" },
	Sand = { color = Color3.fromHex("#e6d59a"), material = "Sand" },
	Snow = { color = Color3.fromHex("#f4f7fb"), material = "SmoothPlastic" },
	Wood = { color = Color3.fromHex("#6b4a2b"), material = "Wood" },
	Planks = { color = Color3.fromHex("#c08e55"), material = "Wood" },
	Leaves = { color = Color3.fromHex("#3f8f3a"), material = "Grass", see = true },
	Glass = { color = Color3.fromHex("#cfefff"), material = "Glass", transparency = 0.55, see = true },
	Brick = { color = Color3.fromHex("#a4513a"), material = "Brick" },
	Water = { color = Color3.fromHex("#3d7fd6"), material = "Glass", transparency = 0.4, see = true, liquid = true },
	Coal = { color = Color3.fromHex("#3b3b40"), material = "Concrete" },
	Iron = { color = Color3.fromHex("#caa58c"), material = "Metal" },
	Gold = { color = Color3.fromHex("#f2c94c"), material = "Metal" },
	Diamond = { color = Color3.fromHex("#5ce1e6"), material = "Neon" },
	Bedrock = { color = Color3.fromHex("#2c2c30"), material = "Concrete" },
	Pumpkin = { color = Color3.fromHex("#e8871e"), material = "Plastic" },
}

-- What players can build with (the tools in StarterPack have these names).
World.PLACEABLE = {
	Grass = true, Dirt = true, Stone = true, Cobblestone = true, Sand = true, Snow = true, Wood = true,
	Planks = true, Leaves = true, Glass = true, Brick = true, Gold = true, Diamond = true, Pumpkin = true,
}

-- A number key per cell (much faster than strings in big loops).
local function key(x, y, z)
	return ((x + 1024) * 64 + y) * 2048 + (z + 1024)
end
World.key = key

function World.unkey(k)
	local z = k % 2048
	local rest = (k - z) / 2048
	local y = rest % 64
	local x = (rest - y) / 64
	return x - 1024, y, z - 1024
end

-- Deterministic "random" in 0..1 for a cell.
local function hash(x, y, z)
	local h = bit32.bxor(x * 73856093, y * 19349663, z * 83492791)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return (h % 1000003) / 1000003
end
World.hash = hash

function World.inside(x, z)
	return x >= -World.SIZE and x < World.SIZE and z >= -World.SIZE and z < World.SIZE
end

-- Ground height of a column: rolling hills, a few mountains, some lakes.
function World.height(x, z)
	local n = math.noise(x / 110 + 0.5, z / 110 + 0.2, 3.3) * 0.9
		+ math.noise(x / 42 + 0.31, z / 42 + 0.77, 1.3) * 0.55
		+ math.noise(x / 14 + 0.13, z / 14 + 0.41, 7.1) * 0.18
	return math.clamp(math.floor(16 + n * 13), 3, World.HEIGHT - 12)
end

function World.isTree(x, z)
	if not World.inside(x, z) or hash(x, 0, z) > 0.011 then
		return false
	end
	local h = World.height(x, z)
	return h > World.WATER + 1 and h < 28
end

-- Trunks and leaves of every tree touching the area, as cell key -> block.
function World.trees(x0, z0, x1, z1)
	local out = {}
	for x = x0 - 2, x1 + 2 do
		for z = z0 - 2, z1 + 2 do
			if World.isTree(x, z) then
				local h = World.height(x, z)
				local top = h + 5 + math.floor(hash(x, 1, z) * 3)
				-- Two wide layers, then a small cap: tidy shapes merge into few parts.
				for dy = -2, 1 do
					local r = dy < 0 and 2 or 1
					for dx = -r, r do
						for dz = -r, r do
							local corner = math.abs(dx) == r and math.abs(dz) == r
							if not (corner and dy == 1) then
								local k = key(x + dx, top + dy, z + dz)
								if out[k] == nil then
									out[k] = "Leaves"
								end
							end
						end
					end
				end
				-- The trunk holds the crown up from below.
				for y = h + 1, top - 3 do
					out[key(x, y, z)] = "Wood"
				end
			end
		end
	end
	return out
end

-- Blocks players placed or broke: cell key -> block ("Air" when broken).
World.edits = {}
World.editCount = 0
-- The lowest edited cell in each chunk column, so chunks know how deep to look.
World.editFloor = {}

local function chunkKey(cx, cz)
	return cx * 4096 + cz
end
World.chunkKey = chunkKey

function World.setEdit(x, y, z, block)
	local k = key(x, y, z)
	if World.edits[k] == nil then
		World.editCount += 1
	end
	World.edits[k] = block
	local ck = chunkKey(x // World.CHUNK, z // World.CHUNK)
	World.editFloor[ck] = math.min(World.editFloor[ck] or y, y)
end

-- All edits as a flat list x, y, z, block, x, y, z, block... (for players who join).
function World.editList()
	local out = {}
	for k, block in World.edits do
		local x, y, z = World.unkey(k)
		table.insert(out, x)
		table.insert(out, y)
		table.insert(out, z)
		table.insert(out, block)
	end
	return out
end

function World.applyEditList(list)
	for i = 1, #list - 3, 4 do
		World.setEdit(list[i], list[i + 1], list[i + 2], list[i + 3])
	end
end

-- What the world has at a cell before anyone touched it.
local function natural(x, y, z, h, trees)
	if y < 0 then
		return "Bedrock"
	end
	if y >= World.HEIGHT or not World.inside(x, z) then
		return "Air"
	end
	if y == 0 then
		return "Bedrock"
	end
	if y > h then
		local t = trees and trees[key(x, y, z)]
		if t then
			return t
		end
		return y <= World.WATER and "Water" or "Air"
	end
	local beach = h <= World.WATER + 1
	if y == h then
		if beach then
			return "Sand"
		end
		return h >= 28 and "Snow" or "Grass"
	end
	if y > h - 3 then
		return beach and "Sand" or "Dirt"
	end
	local r = hash(x, y, z)
	if r < 0.02 then
		return "Coal"
	elseif r < 0.03 and y < 14 then
		return "Iron"
	elseif r < 0.034 and y < 9 then
		return "Gold"
	elseif r < 0.036 and y < 6 then
		return "Diamond"
	end
	return "Stone"
end

-- A fast block lookup for one area: column heights and trees are worked out once.
function World.reader(x0, z0, x1, z1)
	local heights = {}
	local trees = World.trees(x0, z0, x1, z1)
	local edits = World.edits
	return function(x, y, z)
		local e = edits[key(x, y, z)]
		if e ~= nil then
			return e
		end
		local hk = (x + 1024) * 2048 + (z + 1024)
		local h = heights[hk]
		if h == nil then
			h = World.height(x, z)
			heights[hk] = h
		end
		return natural(x, y, z, h, trees)
	end, heights
end

-- One cell, anywhere (the server checks edits with this).
function World.get(x, y, z)
	local read = World.reader(x, z, x, z)
	return read(x, y, z)
end

-- Is a block visible: does any side face air or something see-through (not itself)?
local SIDES = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
function World.exposed(read, x, y, z, block)
	for _, s in SIDES do
		local n = read(x + s[1], y + s[2], z + s[3])
		if n == "Air" then
			return true
		end
		local info = World.BLOCKS[n]
		if info and info.see and n ~= block then
			return true
		end
	end
	return false
end

return World
