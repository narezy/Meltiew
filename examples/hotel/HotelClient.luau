-- StarterPlayerScripts.HotelUI: the door you're at, your coins this run, little notes
-- (coins found, a key, a locked door), and what's left when something gets you: a word
-- of advice in blue light, then back down to the lobby.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)
local Remotes = RS.Remotes
local State = RS.State
local Assets = RS.Assets

local me = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "HotelUI"
gui.Parent = me:WaitForChild("PlayerGui")

local function label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor = Color3.fromHex("#f4f1ec")
	l.Font = "Black"
	for k, v in props do
		if k ~= "Parent" then
			l[k] = v
		end
	end
	l.Parent = props.Parent or gui
	return l
end

-- The door number, top middle.
local door = label({ Size = UDim2.new(0, 260, 0, 44), Position = UDim2.new(0.5, -130, 0, 74), TextSize = 30 })
local function showDoor()
	door.Text = Strings.get("door_n", Shared.door(State.Door.Value))
end
State.Door.Changed:Connect(showDoor)
showDoor()

-- Coins this run, under it.
local coins = label({ Size = UDim2.new(0, 260, 0, 26), Position = UDim2.new(0.5, -130, 0, 114), TextSize = 18, TextColor = Color3.fromHex("#ffd36b") })
local function showCoins()
	local ls = me:FindFirstChild("leaderstats")
	coins.Text = ls and Strings.get("coins_run", ls.Coins.Value) or ""
end
task.spawn(function()
	local ls = me:WaitForChild("leaderstats")
	ls:WaitForChild("Coins").Changed:Connect(showCoins)
	showCoins()
end)

-- Little notes that fade.
local note = label({ Size = UDim2.new(0, 520, 0, 34), Position = UDim2.new(0.5, -260, 1, -150), TextSize = 22, TextTransparency = 1 })
Remotes.Notice.OnClientEvent:Connect(function(key, ...)
	note.Text = Strings.get(key, ...)
	note.TextTransparency = 0
	TweenService:Create(note, TweenInfo.new(1.2, "Quad", "In", 0, false, 2), { TextTransparency = 1 }):Play()
end)

-- Got you: the dark, a word of advice, back to the lobby.
local function curtain(color, lines)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 1, 0)
	f.BackgroundColor = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.ZIndex = 20
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
	local y = 0.34
	for i, text in lines do
		local l = label({ Parent = f, Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.new(0.1, 0, y, 0), TextSize = i == 1 and 34 or 22,
			TextColor = color, TextWrapped = true, TextTransparency = 1, ZIndex = 21, Text = text })
		TweenService:Create(l, TweenInfo.new(1, "Quad", "Out", 0, false, 0.8 + i * 1.1), { TextTransparency = 0 }):Play()
		y += i == 1 and 0.1 or 0.08
	end
end

Remotes.Died.OnClientEvent:Connect(function(why)
	local s = Instance.new("Sound")
	s.SoundId = Assets.Sting.Value
	s.Volume = 1.2
	s.Parent = gui
	s:Play()
	local blue = Color3.fromHex("#8fd0ff")
	curtain(blue, {
		Strings.get("died_" .. tostring(why)),
		Strings.get("advice_" .. tostring(why)),
		Strings.get("back_to_lobby"),
	})
end)

Remotes.Escaped.OnClientEvent:Connect(function()
	curtain(Color3.fromHex("#ffe9a8"), { Strings.get("escaped"), Strings.get("escaped_sub"), Strings.get("back_to_lobby") })
end)
