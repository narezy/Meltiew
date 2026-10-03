-- ServerScriptService.Lobby: the hotel's lobby. Step into the elevator: once someone is in,
-- it counts down and takes everyone inside (up to six) into the hotel together, on a
-- server of their own. Coins, the best door and escapes are saved (DataStore "Hotel",
-- the hotel adds to them) and shown on the board and over your head.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)
local Store = game:GetService("DataStoreService"):GetDataStore("Hotel")

local HOTEL = RS.Config.HotelPlaceId.Value
local zone = workspace.Elevator.Zone
local doorL = workspace.Elevator.DoorL
local doorR = workspace.Elevator.DoorR
local sign = workspace.Elevator.Sign
local Countdown = RS.Countdown

local openL, openR = doorL.Position, doorR.Position
local shutL = openL + Vector3.new(2, 0, 0)
local shutR = openR - Vector3.new(2, 0, 0)

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function stat(parent, name, value)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

Players.PlayerAdded:Connect(function(player)
	local ok, data = pcall(function()
		return Store:GetAsync(Shared.key(player))
	end)
	data = ok and type(data) == "table" and data or Shared.blank()
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	stat(ls, "Coins", data.coins or 0)
	stat(ls, "Best", data.best or 0)
	stat(ls, "Escapes", data.escapes or 0)
	-- Back from the hotel: how it went (the lobby screen says it).
	local j = player:GetJoinData().TeleportData
	if type(j) == "table" then
		task.delay(1.5, function()
			RS.Result:FireClient(player, j.escaped == true, tonumber(j.door) or 0)
		end)
	end
end)

local function inside()
	local list = {}
	local c, s = zone.Position, zone.Size / 2
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local p = root.Position - c
			if math.abs(p.X) <= s.X and math.abs(p.Z) <= s.Z and p.Y > -s.Y - 2 and p.Y < s.Y + 4 then
				table.insert(list, player)
			end
		end
		if #list >= Shared.MAX_PARTY then
			break
		end
	end
	return list
end

local function doors(shut)
	local t = TweenInfo.new(0.8, "Quad", "InOut")
	TweenService:Create(doorL, t, { Position = shut and shutL or openL }):Play()
	TweenService:Create(doorR, t, { Position = shut and shutR or openR }):Play()
end

-- The elevator: waits for riders, counts down, goes.
local left = 0
while true do
	task.wait(1)
	local riders = inside()
	if #riders == 0 then
		left = 0
		Countdown.Value = -1
		sign.Text = ""
	else
		if left <= 0 then
			left = 12
		end
		left -= 1
		Countdown.Value = left
		-- (numbers only: the sign reads the same in every language)
		sign.Text = string.format("%d   ·   %d/%d", left, #riders, Shared.MAX_PARTY)
		if left <= 0 then
			doors(true)
			sign.Text = "▲"
			task.wait(1.2)
			riders = inside()
			if #riders > 0 and HOTEL ~= "" then
				TeleportService:TeleportPartyAsync(HOTEL, riders, { party = #riders })
			end
			task.wait(3)
			doors(false)
			left = 0
		end
	end
end
