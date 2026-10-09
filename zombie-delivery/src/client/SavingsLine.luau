--!strict
-- 6.14: the HUD's savings line, right under the cash ("$1,240 / LV 3 RUNNER"): what you save up for and how far you
-- are ("🚐 OLD VAN  $640 / $1,800" over a thin bar; "✓ BUY IT · $1,800" in green once you have it). The owner asked for
-- no big card all game long (6.12.1): this is one quiet line, and it only shows while there is a goal (shared/Readiness
-- .luau: the next mission's first missing thing that costs money) and never during Marge's first day. A tap opens the
-- phone's READY CHECK (SavingsLine.onOpen, set by Main).
-- It lives in client/Hud.luau's Cash frame (the LeftStack column): while it shows, the Cash frame and the column grow
-- by Config.Readiness.LineHeight and the HUD lays itself out again (Hud listens to the column's Size), so nothing
-- overlaps on a computer (the column grows upward) or on a touch screen (downward). Hud.luau gets no new local.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Readiness = require(Shared.Readiness)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local K = Theme.Contract
local SavingsLine = {}

-- Set by Main: a tap on the line (the phone's READY CHECK).
SavingsLine.onOpen = nil :: (() -> ())?

type Source = {
	current: () -> Readiness.Result,
	listen: (fn: () -> ()) -> (),
}

local player = Players.LocalPlayer

-- Mounts the line in the HUD's Cash frame and keeps it up to date with `source` (client/ReadyCheck.luau). No HUD: none.
function SavingsLine.start(source: Source)
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	local stack = hud and hud:FindFirstChild("LeftStack")
	local cash = stack and stack:FindFirstChild("Cash")
	if not (stack and cash and stack:IsA("GuiObject") and cash:IsA("GuiObject")) then
		return
	end
	local column: GuiObject, holder: GuiObject = stack, cash
	local height = Config.Readiness.LineHeight
	local baseCash, baseColumn = holder.Size.Y.Offset, column.Size.Y.Offset
	local line = Ui.make("TextButton", {
		Name = "Savings",
		Size = UDim2.new(1, 0, 0, height),
		Position = UDim2.fromOffset(0, baseCash),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, holder)
	local label = P.caps(line, "", UDim2.new(1, 0, 0, 14), {
		Name = "Words",
		Position = UDim2.fromOffset(0, 1),
		TextSize = 11,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local back, fill = P.bar(line, UDim2.new(1, 0, 0, 2), K.red)
	back.Position = UDim2.fromOffset(0, height - 4)
	line.Activated:Connect(function()
		local open = SavingsLine.onOpen
		if open then
			open()
		end
	end)
	local function show(on: boolean)
		if line.Visible == on then
			return
		end
		line.Visible = on
		local extra = if on then height else 0
		holder.Size = UDim2.new(holder.Size.X.Scale, holder.Size.X.Offset, 0, baseCash + extra)
		column.Size = UDim2.new(column.Size.X.Scale, column.Size.X.Offset, 0, baseColumn + extra)
	end
	local shown = ""
	local function update()
		local result = source.current()
		local goal = result.goal
		if result.quiet or not goal then
			show(false)
			return
		end
		local words = Readiness.hudLine(goal)
		if words ~= shown then
			shown = words
			label.Text = string.upper(words)
		end
		label.TextColor3 = if goal.afford then K.good else K.secondary
		fill.Size = UDim2.fromScale(math.clamp(goal.have / math.max(1, goal.need), 0, 1), 1)
		fill.BackgroundColor3 = if goal.afford then K.good else K.red
		show(true)
	end
	source.listen(update)
	update()
end

return SavingsLine
