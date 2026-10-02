-- StarterPlayerScripts.Hands: moving by your arms, like the gorilla games. No walking:
-- a hand that touches anything holds on to it, and moving that hand moves you instead.
-- Push down on the ground and you go up, drag it back and you go forward, pull on a wall
-- and you climb. Pull the hand back off the surface to let go: you fly on with the speed
-- of your last push.
--
-- Everything here is the place's own script, made of three things any place can use:
--   VRService:GetUserPosition("LeftHand" / "RightHand"): where the hands are (world)
--   workspace:Raycast: whether a hand went into something since the last frame
--   HumanoidRootPart.AssemblyLinearVelocity: moves the player
-- Change the numbers below to make it feel your way.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local Teams = game:GetService("Teams")
local Tag = game.ReplicatedStorage.Tag

local me = Players.LocalPlayer

local HAND = 0.1 -- a hand's radius (studs)
local LET_GO = 0.06 -- how far a hand comes back off a surface to let go of it
local FOLLOW = 0.04 -- seconds the body takes to catch up with a held hand (smaller is stiffer)
local MAX_THROW = 16 -- the fastest you fly off when you let go
local TAG_REACH = 1.5 -- a lava hand this near someone's middle tags them

if not VRService.VREnabled then
	return -- on a screen (looking around in Studio): walking as usual
end

local held = {} -- side -> { at = where the hand holds on, n = the surface's normal }
local prev = {} -- side -> where the hand was last frame
local pushes = {} -- the last few speeds while holding on (averaged for the throw)
local tagged = {} -- player -> time we last sent a tag for them

-- What hands can't hold on to: players (our own body too).
local function params()
	local skip = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = skip
	rp.RespectCanCollide = true
	return rp
end

-- Lava: a hand on another monkey tags them (the server checks they really were close).
local function tagWith(hand)
	if me.Team ~= Teams.Lava then
		return
	end
	for _, p in Players:GetPlayers() do
		local root = p ~= me and p.Team == Teams.Monkeys and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (hand - root.Position).Magnitude < TAG_REACH and time() - (tagged[p] or 0) > 0.5 then
			tagged[p] = time()
			Tag:FireServer(p)
		end
	end
end

RunService.Heartbeat:Connect(function()
	local character = me.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local rp = params()
	local move, count = Vector3.new(0, 0, 0), 0
	for _, side in { "LeftHand", "RightHand" } do
		local hand = VRService:GetUserPosition(side)
		if not hand then
			held[side], prev[side] = nil, nil
			continue
		end
		tagWith(hand)
		local h = held[side]
		-- Pulled back off the surface: let go.
		if h and (hand - h.at):Dot(h.n) > LET_GO then
			held[side], h = nil, nil
		end
		if not h then
			-- Did the hand go into something since last frame? (From the chest the first time.)
			local from = prev[side] or root.Position + Vector3.new(0, 0.5, 0)
			local way = hand - from
			if way.Magnitude > 0.001 then
				local hit = workspace:Raycast(from, way + way.Unit * HAND, rp)
				if hit then
					h = { at = hit.Position + hit.Normal * HAND, n = hit.Normal }
					held[side] = h
				end
			end
		end
		prev[side] = hand
		if h then
			move += h.at - hand
			count += 1
		end
	end
	if count > 0 then
		-- Holding on: the body goes wherever keeps the hands where they hold.
		local v = move / count / FOLLOW
		root.AssemblyLinearVelocity = v
		table.insert(pushes, v)
		if #pushes > 5 then
			table.remove(pushes, 1)
		end
	elseif #pushes > 0 then
		-- Just let go: fly off with the last pushes' speed.
		local sum = Vector3.new(0, 0, 0)
		for _, v in pushes do
			sum += v
		end
		local throw = sum / #pushes
		if throw.Magnitude > MAX_THROW then
			throw = throw.Unit * MAX_THROW
		end
		root.AssemblyLinearVelocity = throw
		table.clear(pushes)
	end
end)
