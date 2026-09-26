-- BlockCraft server: puts the spawn on dry land, checks every dig and build,
-- tells everyone about it, and turns the sun around every 10 minutes.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local World = require(RS.World)
local BlockEvent = RS.BlockEvent
local GetEdits = RS.GetEdits

-- Spawn on the nearest dry, flat-ish ground to the middle of the world.
local sx, sz = 0, 0
for r = 0, 60, 2 do
	local found = false
	for _, d in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r } } do
		if World.height(d[1], d[2]) > World.WATER + 1 and not World.isTree(d[1], d[2]) then
			sx, sz = d[1], d[2]
			found = true
			break
		end
	end
	if found then
		break
	end
end
local ground = World.height(sx, sz)
workspace.SpawnLocation.Position = Vector3.new(sx + 0.5, ground + 1.2, sz + 0.5)

GetEdits.OnServerInvoke = function()
	return World.editList()
end

local last = {} -- player -> time of the last action (no autoclicker floods)

local function isCell(x, y, z)
	return type(x) == "number" and type(y) == "number" and type(z) == "number"
		and x == math.floor(x) and y == math.floor(y) and z == math.floor(z)
		and World.inside(x, z) and y >= 1 and y < World.HEIGHT
end

BlockEvent.OnServerEvent:Connect(function(player, action, x, y, z, block)
	if not isCell(x, y, z) then
		return
	end
	local now = time()
	if last[player] and now - last[player] < 0.12 then
		return
	end
	last[player] = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (Vector3.new(x + 0.5, y + 0.5, z + 0.5) - root.Position).Magnitude > 9 then
		return
	end
	if World.editCount >= World.MAX_EDITS and World.edits[World.key(x, y, z)] == nil then
		return
	end
	local current = World.get(x, y, z)
	local result
	if action == "break" then
		if current == "Air" or current == "Water" or current == "Bedrock" then
			return
		end
		-- A hole next to water fills with water.
		result = "Air"
		if y <= World.WATER then
			for _, s in { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } } do
				if World.get(x + s[1], y + s[2], z + s[3]) == "Water" then
					result = "Water"
					break
				end
			end
		end
	elseif action == "place" then
		if not World.PLACEABLE[block] or (current ~= "Air" and current ~= "Water") then
			return
		end
		-- Not inside anyone.
		for _, p in Players:GetPlayers() do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local rp = r.Position
				if x + 1 > rp.X - 0.4 and x < rp.X + 0.4 and z + 1 > rp.Z - 0.4 and z < rp.Z + 0.4 and y + 1 > rp.Y - 0.9 and y < rp.Y + 0.9 then
					return
				end
			end
		end
		result = block
	else
		return
	end
	World.setEdit(x, y, z, result)
	BlockEvent:FireAllClients("set", x, y, z, result)
end)

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

-- Day and night.
local Lighting = game:GetService("Lighting")
while true do
	task.wait(1)
	Lighting.ClockTime = (Lighting.ClockTime + 24 / 600) % 24
end
