-- StarterPlayerScripts.Status: the line at the top of the screen (in VR, on the panel).
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")
local Teams = game:GetService("Teams")
local RS = game.ReplicatedStorage

local me = Players.LocalPlayer
local label = me:WaitForChild("PlayerGui"):WaitForChild("Status"):WaitForChild("Label")

local function update()
	local state, n = RS.State.Value, RS.Countdown.Value
	if not VRService.VREnabled then
		label.Text = Strings.get("st_screen")
	elseif state == "waiting" then
		label.Text = Strings.get("st_waiting", n, 2)
	elseif state == "starting" then
		label.Text = Strings.get("st_starting", n)
	elseif state == "playing" then
		label.Text = me.Team == Teams.Lava and Strings.get("st_lava", n) or Strings.get("st_run", n)
	else
		label.Text = Strings.get("st_over")
	end
	label.TextColor = me.Team == Teams.Lava and state == "playing" and Color3.fromHex("#ffb070") or Color3.fromHex("#f4f1ec")
end

RS.State.Changed:Connect(update)
RS.Countdown.Changed:Connect(update)
me:GetPropertyChangedSignal("Team"):Connect(update)
update()
