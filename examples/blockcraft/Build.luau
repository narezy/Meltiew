-- Breaking and placing: hold the Pickaxe to dig, a block to build. Click (or tap)
-- the block you aim at; a white frame shows which one. The server has the last word.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
-- (Apps before 1.4.2 give LocalScripts no `workspace` global, so fetch it.)
local workspace = game:GetService("Workspace")
local World = require(RS:WaitForChild("World"))
local BlockEvent = RS:WaitForChild("BlockEvent")

local REACH = 7
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local frame = Instance.new("Part")
frame.Name = "Selection"
frame.Size = Vector3.new(1.04, 1.04, 1.04)
frame.Color = Color3.new(1, 1, 1)
frame.Material = "SmoothPlastic"
frame.Transparency = 1
frame.CanCollide = false
frame.CanTouch = false
frame.CastShadow = false
frame.Parent = workspace

local function heldTool()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

-- The block under the pointer: the cell to dig and the empty cell in front of it.
local function aim()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not World.folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { World.folder }
	params.FilterType = "Include"
	params.RespectCanCollide = true
	local hit = workspace:Raycast(mouse.Origin, mouse.UnitRay.Direction * 60, params)
	if not hit or (hit.Position - root.Position).Magnitude > REACH then
		return nil
	end
	local inside = hit.Position - hit.Normal * 0.5
	local front = hit.Position + hit.Normal * 0.5
	return Vector3.new(math.floor(inside.X), math.floor(inside.Y), math.floor(inside.Z)),
		Vector3.new(math.floor(front.X), math.floor(front.Y), math.floor(front.Z)),
		root.Position
end

-- Would a block here trap the player inside it?
local function hitsMe(cell, rootPos)
	return cell.X + 1 > rootPos.X - 0.4 and cell.X < rootPos.X + 0.4
		and cell.Z + 1 > rootPos.Z - 0.4 and cell.Z < rootPos.Z + 0.4
		and cell.Y + 1 > rootPos.Y - 0.9 and cell.Y < rootPos.Y + 0.9
end

mouse.Button1Down:Connect(function()
	local tool = heldTool()
	if not tool then
		return
	end
	local dig, place, rootPos = aim()
	if not dig then
		return
	end
	if tool.Name == "Pickaxe" then
		BlockEvent:FireServer("break", dig.X, dig.Y, dig.Z)
	elseif World.PLACEABLE[tool.Name] and not hitsMe(place, rootPos) then
		BlockEvent:FireServer("place", place.X, place.Y, place.Z, tool.Name)
	end
end)

-- Keep the frame on the aimed block.
while true do
	local dig = heldTool() and aim()
	if dig then
		frame.Position = dig + Vector3.new(0.5, 0.5, 0.5)
		frame.Transparency = 0.75
	elseif frame.Transparency ~= 1 then
		frame.Transparency = 1
	end
	task.wait(0.05)
end
