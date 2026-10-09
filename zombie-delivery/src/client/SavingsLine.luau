--!strict
-- 6.14: the HUD's savings line, right under the cash ("$1,240 / LV 3 RUNNER"): what you save up for and how far you
-- are ("🚐 OLD VAN  $640 / $1,800" over a thin bar; "✓ BUY IT · $1,800" in green once you have it). The owner asked for
-- no big card all game long (6.12.1): this is one quiet line, and it only shows while there is a goal (shared/Readiness
-- .luau: the next mission's first missing thing that costs money) and never during Marge's first day. A tap opens the
-- phone's READY CHECK (SavingsLine.onOpen, set by Main).
-- It lives in client/Hud.luau's Cash frame (the LeftStack column): while it shows, the Cash frame and the column grow
-- by Config.Readiness.LineHeight and the HUD lays itself out again (Hud listens to the column's Size), so nothing
-- overlaps on a computer (the column grows upward) or on a touch screen (downward). Hud.luau gets no new local.
-- 6.14 review (small screens): the money has a label of its own at the right ("$640 / $1,800", "✓ BUY IT · $1,800",
-- "$1,800 SAVED · LEVEL 4": Readiness.goalMoney) and the name takes what is left (cut with "…"), so the money never
-- goes off the line. On a touch screen too short for the column and the line above the thumbstick, Hud sets the
-- column's SavingsRoom attribute to false and the line stays away (the phone's NEXT MISSION tile still says it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

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
	local TEXT = 11
	local label = P.caps(line, "", UDim2.new(1, 0, 0, 14), {
		Name = "Words",
		Position = UDim2.fromOffset(0, 1),
		TextSize = TEXT,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local money = P.caps(line, "", UDim2.new(0, 0, 0, 14), {
		Name = "Money",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 1),
		TextSize = TEXT,
		TextColor3 = K.secondary,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Right,
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
		on = on and column:GetAttribute("SavingsRoom") ~= false
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
		local amount = string.upper(Readiness.goalMoney(goal))
		local words = `{goal.icon} {goal.name}|{amount}`
		if words ~= shown then
			shown = words
			label.Text = string.upper(`{goal.icon} {goal.name}`)
			money.Text = amount
			-- (the money's own width, the name the rest: TextService measures it before it is drawn)
			local ok, size = pcall(function(): Vector2
				return TextService:GetTextSize(amount, TEXT, Theme.HeadingFont, Vector2.new(1000, 100))
			end)
			local width = math.ceil(if ok and size then size.X else #amount * TEXT * 0.62) + 2
			money.Size = UDim2.fromOffset(width, 14)
			label.Size = UDim2.new(1, -(width + 8), 0, 14)
		end
		local saved = goal.left <= 0 and not goal.afford
		local tone = if goal.afford then K.good elseif saved then K.warn else K.secondary
		label.TextColor3 = tone
		money.TextColor3 = if tone == K.secondary then K.text else tone
		fill.Size = UDim2.fromScale(math.clamp(goal.have / math.max(1, goal.need), 0, 1), 1)
		fill.BackgroundColor3 = if goal.afford then K.good elseif saved then K.warn else K.red
		show(true)
	end
	source.listen(update)
	column:GetAttributeChangedSignal("SavingsRoom"):Connect(update)
	update()
end

return SavingsLine
