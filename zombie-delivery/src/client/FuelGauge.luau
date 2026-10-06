--!strict
-- 5.4, the fuel gauge (Config.Fuel; server/Fuel.luau writes the car's Tank and Fuel attributes): a small contract-style
-- group in the lower right, left of the speed on the vehicle line (client/Hud.luau's speed row builds it there with
-- FuelGauge.build, so it moves, scales and hides with the right column on a computer and on a touch screen, and takes no
-- room of its own: the speed row has room to its left).
--
--   ⛽ ▬▬▬▬▬▭▭  24 L        the pump icon (the emoji until art/icons/fuel is uploaded), a thin bar of the tank, the litres
--   ⛽ ▬▭▭▭▭▭▭  LOW · 5 L   under Config.Fuel.Low of the tank: the bar and the words red
--   ⛽ ▭▭▭▭▭▭▭  EMPTY      empty: red (the car crawls, client/Drive.luau; the phone has TOW)
--
-- Only for your own car while you are inside it (the speed row's rule) and only a car with a tank (a bike has none: the
-- gauge hides). It reads the attributes four times a second and redraws only when the words change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FuelMath = require(Shared.FuelMath)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Drive = require(script.Parent.Drive)

local FuelGauge = {}

local BAR_W = 56

-- Builds the gauge into `row` (a horizontal list: it goes first, on the left) and keeps it up to date.
function FuelGauge.build(row: Instance)
	local group = Ui.make("Frame", {
		Name = "FuelGauge",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Visible = false,
	}, row)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, group)
	local icon = Ui.icon(group, "fuel", "⛽", UDim2.fromOffset(16, 16), {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
		LayoutOrder = 1,
	})
	local holder = Ui.make("Frame", { Name = "Tank", Size = UDim2.fromOffset(BAR_W, 22), BackgroundTransparency = 1, LayoutOrder = 2 }, group)
	local back, fill = P.bar(holder, UDim2.fromOffset(BAR_W, 3), P.ink)
	back.Position = UDim2.new(0, 0, 0.5, 0)
	back.AnchorPoint = Vector2.new(0, 0.5)
	-- quarter ticks over the track, like a dial's marks
	for n = 1, 3 do
		Ui.make("Frame", {
			Name = "Tick",
			Size = UDim2.fromOffset(1, 7),
			Position = UDim2.new(n / 4, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = P.line,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}, holder)
	end
	local words = P.caps(group, "", UDim2.fromOffset(0, 22), {
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 12,
		Font = Theme.HeadingFont,
		LayoutOrder = 3,
	})
	local shown = ""
	task.spawn(function()
		while group.Parent do
			local car = Drive.myCar()
			local tank = if car then car:GetAttribute("Tank") else nil
			local fuel = if car then car:GetAttribute("Fuel") else nil
			local key = "none"
			if type(tank) == "number" and type(fuel) == "number" and tank > 0 then
				key = string.format("%.0f|%.0f", fuel * 2, tank)
			end
			if key ~= shown then
				shown = key
				group.Visible = key ~= "none"
				if type(tank) == "number" and type(fuel) == "number" and tank > 0 then
					local share = FuelMath.share(fuel, tank)
					local low = FuelMath.isLow(fuel, tank)
					local empty = FuelMath.isEmpty(fuel)
					local tint = if low then P.danger else P.ink
					fill.Size = UDim2.fromScale(share, 1)
					fill.BackgroundColor3 = tint
					local litres = if fuel < 1 then "<1 L" else string.format("%.0f L", fuel)
					words.Text = if empty then "EMPTY" elseif low then `LOW · {litres}` else litres
					words.TextColor3 = if low then P.danger else P.ink2
					if icon:IsA("ImageLabel") then
						icon.ImageColor3 = tint
					elseif icon:IsA("TextLabel") then
						icon.TextTransparency = if low then 0 else 0.1
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

return FuelGauge
