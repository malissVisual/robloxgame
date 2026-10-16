-- 8.9.4: the driving dashboard (client/DrivePedals.luau with shared/PedalRules.luau, Config.DrivePedals) run for real on
-- missions_mock.luau's recorder, in a car panel and a speed row like client/Hud.luau's (a computer's 240 wide, a touch
-- screen's 300; the speed row 30 high): built hidden; a computer's own row over the speed (64 high, the panel's width,
-- LayoutOrder 0), a touch screen's compact one at the speed row's left (LayoutOrder -1, no higher than the speed row and
-- the 8 px gap over it, narrow enough beside the fuel and a three-figure speed); the brake left of the gas, the
-- selector P R N D right of them; parked: P lit, no pedal down; W: D and the gas going down smoothly (Config's Ease, on
-- the check's own clock) to its full travel, green; S rolling forward: the brake down (red), still D; S standing: R and
-- the gas; W backing up: the brake, R; letting go: up again; a bike, someone else's car, on foot or Config.DrivePedals.On
-- false: nothing; a pedal at rest not written again frame after frame.
local mock = require("./missions_mock")
local Config = require("./Config")
local PedalRules = require("./PedalRules")
local DrivePedals = require("./DrivePedals")
local K = mock.MTheme.Contract

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	print("ok    " .. name)
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end
local function same(a, b)
	return near(a.R, b.R, 0.002) and near(a.G, b.G, 0.002) and near(a.B, b.B, 0.002)
end
local function find(root, name)
	return root:FindFirstChild(name, true)
end

-- The check's clock (the prefix gives DrivePedals `os.clock` from it): frames of 1/60 s.
mock.clock = 100
local function frames(n, show, car, throttle, speed)
	for _ = 1, n do
		mock.clock += 1 / 60
		DrivePedals.draw(show, car, throttle, speed)
	end
end

local van = mock.make("Model", { Name = "Van" })
local bike = mock.make("Model", { Name = "Bike" })
bike:SetAttribute("Bike", true)

local function panelFor(width)
	local panel = mock.make("Frame", { Name = "Vehicle", Size = mock.UDim2.fromOffset(width, 0) })
	local speedRow = mock.make("Frame", { Name = "Speed", Size = mock.UDim2.fromOffset(width, 30) }, panel)
	return panel, speedRow
end

-- ── A computer ─────────────────────────────────────────────────────────────

local panel, speedRow = panelFor(240)
local frame = DrivePedals.build(panel, speedRow, false)
check("a computer: its own row in the car panel", frame.Parent == panel and frame.Name == "Pedals")
check("a computer: over the speed (LayoutOrder 0, the speed row's 1)", frame.LayoutOrder == 0)
check("a computer: the panel's width, 64 high", frame.Size.X.Offset == 240 and frame.Size.Y.Offset == 64, `{frame.Size.X.Offset} x {frame.Size.Y.Offset}`)
check("built hidden", frame.Visible == false)
local brake, gas, selector = find(frame, "Brake"), find(frame, "Gas"), find(frame, "Selector")
check("the brake, the gas and the selector", brake ~= nil and gas ~= nil and selector ~= nil)
check("from the left: the brake, the gas, the selector", brake.LayoutOrder < gas.LayoutOrder and gas.LayoutOrder < selector.LayoutOrder)
check("the brake wide and low, the gas tall and narrow", brake.Size.X.Offset > gas.Size.X.Offset and brake:FindFirstChild("Pad").Size.Y.Offset < gas:FindFirstChild("Pad").Size.Y.Offset)
check("the brake has its arm, the gas none", brake:FindFirstChild("Arm") ~= nil and gas:FindFirstChild("Arm") == nil)
for _, gear in PedalRules.Gears do
	check(`the selector's {gear}`, find(selector, `Gear{gear}`) ~= nil and find(selector, `Gear{gear}`).Text == gear)
end
local function pad(p)
	return p:FindFirstChild("Pad")
end
local function restOf(p)
	return p.Size.Y.Offset - pad(p).Size.Y.Offset - math.max(4, math.floor(p.Size.Y.Offset * 0.14 + 0.5))
end
local function lit(gear)
	return find(selector, `Lit{gear}`).BackgroundTransparency < 0.5
end
local function onlyLit(gear)
	for _, g in PedalRules.Gears do
		if lit(g) ~= (g == gear) then
			return false
		end
	end
	return true
end

-- Parked: shown, P, nothing down.
frames(3, true, van, 0, 0)
local view = DrivePedals.view()
check("in your car: shown", frame.Visible and view.shown)
check("parked: P lit, only P", view.gear == "P" and onlyLit("P"))
check("parked: no pedal down", view.gas == 0 and view.brake == 0)
local gasRest, brakeRest = pad(gas).Position.Y.Offset, pad(brake).Position.Y.Offset
check("a pedal at rest sits over its travel", gasRest == restOf(gas) and brakeRest == restOf(brake), `{gasRest}, {brakeRest}`)

-- W: D, the gas down smoothly.
frames(1, true, van, 1, 0)
view = DrivePedals.view()
check("W: D at once", view.gear == "D" and onlyLit("D"))
check("W: the gas starts down, not at once", view.gas > 0 and view.gas < 0.5, view.gas)
frames(30, true, van, 1, 12)
view = DrivePedals.view()
check("W held half a second: the gas all the way down", near(view.gas, 1) and view.brake == 0, view.gas)
local travel = math.max(4, math.floor(64 * 0.14 + 0.5))
check("the gas's pad down by its whole travel", pad(gas).Position.Y.Offset == gasRest + travel, pad(gas).Position.Y.Offset)
check("the gas green when down", same(pad(gas).BackgroundColor3, mock.Color3.fromRGB(44, 47, 52):Lerp(K.good, 0.55)))
check("the brake still up", pad(brake).Position.Y.Offset == brakeRest)
check("the selector's D in the dark on its green", same(find(selector, "GearD").TextColor3, K.charcoal) and same(find(selector, "LitD").BackgroundColor3, K.good))

-- A pedal held still is not written again.
local sentinel = mock.UDim2.fromOffset(-77, -77)
pad(gas).Position = sentinel
frames(5, true, van, 1, 12)
check("a pedal held still: not written frame after frame", pad(gas).Position == sentinel)
pad(gas).Position = mock.UDim2.fromOffset(0, gasRest + travel)

-- S rolling forward: the brake, still D.
frames(40, true, van, -1, 12)
view = DrivePedals.view()
check("S rolling forward: the brake down, still D", view.gear == "D" and near(view.brake, 1) and near(view.gas, 0), `{view.gear} {view.brake} {view.gas}`)
check("the brake red when down", same(pad(brake).BackgroundColor3, mock.Color3.fromRGB(44, 47, 52):Lerp(K.red, 0.55)))
check("the brake's arm follows its pad", brake:FindFirstChild("Arm").Size.Y.Offset >= pad(brake).Position.Y.Offset)
check("the gas up again", pad(gas).Position.Y.Offset == gasRest)

-- S standing: R and the gas (backing up).
frames(40, true, van, -1, 0)
view = DrivePedals.view()
check("S standing: R, the gas down, the brake up", view.gear == "R" and onlyLit("R") and near(view.gas, 1) and near(view.brake, 0))
check("the selector's R amber", same(find(selector, "LitR").BackgroundColor3, K.warn))

-- W backing up: the brake, R.
frames(40, true, van, 1, -8)
view = DrivePedals.view()
check("W backing up: the brake, still R", view.gear == "R" and near(view.brake, 1) and near(view.gas, 0))

-- Letting go: rolling, then standing.
frames(40, true, van, 0, -8)
view = DrivePedals.view()
check("letting go backing up: R, both up", view.gear == "R" and near(view.gas, 0) and near(view.brake, 0))
frames(2, true, van, 0, 0)
check("standing still again: P", DrivePedals.view().gear == "P" and onlyLit("P"))

-- Nothing for a bike, on foot, someone else's car, or with Config's switch off.
frames(1, true, bike, 1, 10)
check("a bike: nothing", frame.Visible == false and not DrivePedals.view().shown)
frames(1, false, van, 1, 10)
check("on foot (or someone else's car): nothing", frame.Visible == false)
frames(1, true, nil, 1, 10)
check("no car: nothing", frame.Visible == false)
local switch = Config.DrivePedals.On
Config.DrivePedals.On = false
frames(1, true, van, 1, 10)
check("Config.DrivePedals.On false: nothing", frame.Visible == false)
Config.DrivePedals.On = switch
frames(1, true, van, 0, 0)
check("back in the car: shown again, the pedals up", frame.Visible and pad(gas).Position.Y.Offset == gasRest and pad(brake).Position.Y.Offset == brakeRest)

-- ── A touch screen ─────────────────────────────────────────────────────────

panel, speedRow = panelFor(300)
frame = DrivePedals.build(panel, speedRow, true)
check("touch: in the speed row, at its left", frame.Parent == speedRow and frame.LayoutOrder == -1)
check("touch: no higher than the speed row and the 8 px gap over it", frame.Size.Y.Offset <= 30 + 8, frame.Size.Y.Offset)
local row = frame:FindFirstChild("Row")
local width, count = 0, 0
for _, child in row:GetChildren() do
	if child:IsA("GuiObject") then
		width += child.Size.X.Offset
		count += 1
	end
end
local padding = row:FindFirstChildOfClass("UIListLayout").Padding.Offset
width += padding * (count - 1)
-- the speed row's 300: the fuel (16 + 6 + 56 + 6 + "31 L") and a three-figure speed with KM/H, 6 px apart, leave 85
check("touch: narrow enough beside the fuel and the speed", width <= 85, width)
frames(30, true, van, 1, 10)
check("touch: the gas down, D", DrivePedals.view().gear == "D" and near(DrivePedals.view().gas, 1) and frame.Visible)
local touchGas = find(frame, "Gas")
check("touch: the gas's pad inside its holder when down", pad(touchGas).Position.Y.Offset + pad(touchGas).Size.Y.Offset <= touchGas.Size.Y.Offset)

print("ALL CHECKS PASSED")
