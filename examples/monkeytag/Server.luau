-- ServerScriptService.Game: rounds of tag. One monkey is lava; a lava hand (or body) on
-- a monkey turns that monkey into lava too. When everyone is lava, a new round starts with
-- someone else. VR only: players on a screen are sent away (in Studio they may look around).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local RS = game.ReplicatedStorage

local State = RS.State -- "waiting", "starting", "playing", "over"
local Countdown = RS.Countdown
local Tag = RS.Tag -- a lava player's hand touched someone (LocalScript Hands)
local Lava = Teams.Lava
local Monkeys = Teams.Monkeys
local lavaLook = game.ServerStorage.LavaLook

local MIN_PLAYERS = 2
local REACH = 4.5 -- studs between two bodies a hand tag can come from (arms are long)
local BUMP = 2.2 -- bodies this close: tagged without hands too

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- Monkeys have no legs; in VR they move by their arms only (no walking or jumping).
local function monkeyBody(player)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.LeftLegVisible = false
	hum.RightLegVisible = false
	if player.VREnabled then
		hum.WalkSpeed = 0
		hum.CanJump = false
		hum.CanSprint = false
		hum.Traction = 0.1 -- keeps the speed of a throw through the air
	end
end

Players.PlayerAdded:Connect(function(player)
	if not player.VREnabled and not RunService:IsStudio() then
		player:Kick(Strings.forPlayer(player, "vr_only"))
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local tags = Instance.new("IntValue")
	tags.Name = "Tags"
	tags.Parent = stats
	-- Joining mid-round: you're lava (the round finishes soon).
	player.Team = State.Value == "playing" and Lava or Monkeys
	if player.Team == Lava then
		player:ApplyAppearance(lavaLook)
	end
	player.CharacterAdded:Connect(function()
		monkeyBody(player)
	end)
	if player.Character then
		monkeyBody(player)
	end
end)

local function playersOn(team)
	local out = {}
	for _, p in Players:GetPlayers() do
		if p.Team == team then
			table.insert(out, p)
		end
	end
	return out
end

local function makeLava(player, by)
	if player.Team == Lava then
		return
	end
	player.Team = Lava
	player:ApplyAppearance(lavaLook)
	if by and by:FindFirstChild("leaderstats") then
		by.leaderstats.Tags.Value += 1
	end
end

Tag.OnServerEvent:Connect(function(player, target)
	if State.Value ~= "playing" or player.Team ~= Lava then
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Team ~= Monkeys then
		return
	end
	local a, b = rootOf(player), rootOf(target)
	if a and b and (a.Position - b.Position).Magnitude <= REACH then
		makeLava(target, player)
	end
end)

-- Bumping into a monkey with the body tags too.
task.spawn(function()
	while true do
		task.wait(0.2)
		if State.Value == "playing" then
			for _, lava in playersOn(Lava) do
				local a = rootOf(lava)
				for _, monkey in playersOn(Monkeys) do
					local b = rootOf(monkey)
					if a and b and (a.Position - b.Position).Magnitude <= BUMP then
						makeLava(monkey, lava)
					end
				end
			end
		end
	end
end)

-- The rounds.
while true do
	State.Value = "waiting"
	for _, p in Players:GetPlayers() do
		p.Team = Monkeys
		p:ResetAppearance()
	end
	while #Players:GetPlayers() < MIN_PLAYERS do
		Countdown.Value = #Players:GetPlayers()
		task.wait(1)
	end
	State.Value = "starting"
	for i = 5, 1, -1 do
		Countdown.Value = i
		task.wait(1)
	end
	local all = Players:GetPlayers()
	if #all >= MIN_PLAYERS then
		makeLava(all[math.random(#all)])
		State.Value = "playing"
		-- Until everyone is lava (or too few are left to play).
		while #playersOn(Monkeys) > 0 and #Players:GetPlayers() >= MIN_PLAYERS do
			-- The lava monkey left: someone else takes over.
			if #playersOn(Lava) == 0 then
				local left = playersOn(Monkeys)
				makeLava(left[math.random(#left)])
			end
			Countdown.Value = #playersOn(Monkeys)
			task.wait(0.5)
		end
		State.Value = "over"
		task.wait(5)
	end
end
