-- StarterPlayerScripts.LobbyUI: your coins, best door and escapes; how the last trip went.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)

local me = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.Parent = me:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Size = UDim2.new(0, 230, 0, 96)
card.Position = UDim2.new(1, -246, 0, 70)
card.BackgroundColor = Color3.fromHex("#16141d")
card.BackgroundTransparency = 0.3
card.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = 14
corner.Parent = card

local function line(y, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -24, 0, 26)
	l.Position = UDim2.new(0, 12, 0, y)
	l.BackgroundTransparency = 1
	l.TextColor = color
	l.TextSize = 18
	l.Font = "Bold"
	l.TextXAlignment = "Left"
	l.Parent = card
	return l
end
local coins = line(8, Color3.fromHex("#ffd36b"))
local best = line(36, Color3.fromHex("#f4f1ec"))
local escapes = line(62, Color3.fromHex("#9cffb0"))

task.spawn(function()
	local ls = me:WaitForChild("leaderstats")
	local function show()
		coins.Text = Strings.get("lobby_coins", ls.Coins.Value)
		best.Text = Strings.get("lobby_best", Shared.door(ls.Best.Value))
		escapes.Text = Strings.get("lobby_escapes", ls.Escapes.Value)
	end
	for _, k in { "Coins", "Best", "Escapes" } do
		ls:WaitForChild(k).Changed:Connect(show)
	end
	show()
end)

-- How the last trip went, for a few seconds.
RS.Result.OnClientEvent:Connect(function(escaped, door)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0, 640, 0, 50)
	l.Position = UDim2.new(0.5, -320, 0, 110)
	l.BackgroundTransparency = 1
	l.TextColor = escaped and Color3.fromHex("#9cffb0") or Color3.fromHex("#8fd0ff")
	l.TextSize = 28
	l.Font = "Black"
	l.TextWrapped = true
	l.Text = escaped and Strings.get("result_escaped") or Strings.get("result_died", Shared.door(door))
	l.Parent = gui
	task.wait(6)
	TweenService:Create(l, TweenInfo.new(1), { TextTransparency = 1 }):Play()
	task.wait(1)
	l:Destroy()
end)
