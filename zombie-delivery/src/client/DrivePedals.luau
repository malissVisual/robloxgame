--!strict
-- 8.9.4 (the owner: "on the screen as if driving with pedals, an automatic, a UI like that"): the driving dashboard in
-- the HUD's vehicle line while you drive your own car (not a bike: it has no pedals of its own here). An automatic's
-- two pedals and its selector, from the left (as they sit by your feet and your right hand):
--   [ brake ]  wide, low on its arm: pressed (down, red) while S / down slows you or forward slows your backing up
--   [ gas ]    tall and narrow: pressed (down, green) as far as you hold W / up, or S / down backing up in R
--   [P R N D]  the selector: the gear lit (P white, R amber, D green; N is never used: an automatic rolls in D)
-- shared/PedalRules.luau decides the gear and which pedal from Drive.throttle and Drive.speed (client/Drive.luau drives
-- as before: the pedals only show it, a phone's thumbstick too); a pedal follows the foot smoothly
-- (Config.DrivePedals.Ease). Config.DrivePedals.On false: nothing.
-- client/Hud.luau builds it into its car panel (DrivePedals.build: a computer its own row over the speed and the fuel,
-- in the open corner; a touch screen a compact one at the speed row's left, inside the right column's width, so the
-- touch layout's boxes are as they were) and calls DrivePedals.draw from its every-frame vehicle line: it writes only
-- what changed.
--   DrivePedals.build(panel, speedRow, touch)   builds it (hidden); its Frame
--   DrivePedals.draw(show, car, throttle, speed)  every frame: shown while `show` (you drive your own car) and the car is
--                                                 not a bike; the gear and the pedals from the throttle and the speed
--   DrivePedals.view()                          what it shows now { shown, gear, gas, brake } (the tests, the preview)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PedalRules = require(Shared.PedalRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local DrivePedals = {}

local K = Theme.Contract
local RUBBER = Color3.fromRGB(44, 47, 52) -- a pedal's pad at rest
local RIB = Color3.fromRGB(78, 83, 90) -- its ribs
local ARM = Color3.fromRGB(96, 101, 108) -- the brake's arm
local GEAR_LIT: { [string]: Color3 } = { P = K.text, R = K.warn, N = K.secondary, D = K.good }

type Pedal = { holder: Frame, pad: Frame, stroke: UIStroke, arm: Frame?, rest: number, travel: number, lit: Color3 }
type Parts = {
	frame: Frame,
	letters: { [string]: TextLabel },
	marks: { [string]: Frame },
	brake: Pedal,
	gas: Pedal,
}

local parts: Parts? = nil
local shown = { on = false, gear = "", gas = 0, brake = 0, drawnGas = -1, drawnBrake = -1, at = 0 }

local function on(): boolean
	local t = (Config :: any).DrivePedals
	return type(t) ~= "table" or t.On ~= false
end

-- A pedal: its pad (rounded rubber, ribs across it) in a holder `w` × `h`, the pad `padH` high resting `travel` over the
-- holder's bottom (pressed it goes down to it); `arm`: a rod from the holder's top down to the pad (the brake's lever).
local function pedal(parent: Instance, name: string, order: number, w: number, h: number, padH: number, ribs: number, arm: boolean, lit: Color3): Pedal
	local holder: Frame = Ui.make("Frame", { Name = name, Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local travel = math.max(4, math.floor(h * 0.14 + 0.5)) -- (how far it goes down: clearly seen)
	local rest = h - padH - travel
	local rod: Frame? = nil
	if arm then
		rod = Ui.make("Frame", {
			Name = "Arm",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(math.max(3, math.floor(w * 0.12)), rest + 2),
			BackgroundColor3 = ARM,
			BorderSizePixel = 0,
		}, holder)
		Ui.corner(rod :: Frame, 2)
	end
	local pad: Frame = Ui.make("Frame", {
		Name = "Pad",
		Position = UDim2.fromOffset(0, rest),
		Size = UDim2.fromOffset(w, padH),
		BackgroundColor3 = RUBBER,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(pad, math.max(4, math.floor(math.min(w, padH) * 0.22)))
	local stroke: UIStroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.35 }, pad)
	for k = 1, ribs do
		Ui.make("Frame", {
			Name = `Rib{k}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, k / (ribs + 1), 0),
			Size = UDim2.new(1, -math.max(6, math.floor(w * 0.22)), 0, 2),
			BackgroundColor3 = RIB,
			BorderSizePixel = 0,
		}, pad)
	end
	return { holder = holder, pad = pad, stroke = stroke, arm = rod, rest = rest, travel = travel, lit = lit }
end

-- The pedal pressed `share` (0 … 1): down by its travel, its face toward its colour, its edge lit.
local function press(p: Pedal, share: number)
	local y = p.rest + p.travel * share
	p.pad.Position = UDim2.fromOffset(0, math.floor(y + 0.5))
	p.pad.BackgroundColor3 = RUBBER:Lerp(p.lit, 0.55 * share)
	p.stroke.Color = K.line:Lerp(p.lit, math.min(1, share * 1.6))
	p.stroke.Thickness = if share > 0.05 then 2 else 1
	p.stroke.Transparency = 0.35 * (1 - share)
	local arm = p.arm
	if arm then
		arm.Size = UDim2.fromOffset(arm.Size.X.Offset, math.floor(y + 2.5))
	end
end

-- Builds the dashboard (hidden). A computer: its own row in `panel` over the speed row, right-aligned (LayoutOrder 0);
-- a touch screen: compact, at the left of `speedRow` (before the fuel gauge, LayoutOrder -1).
function DrivePedals.build(panel: Instance, speedRow: Instance, touch: boolean): Frame
	-- (a touch screen's 38: the speed row's 30 and the 8 px gap over it, never into the weapon line above)
	local H = if touch then 38 else 64
	local frame: Frame
	if touch then
		frame = Ui.make("Frame", { Name = "Pedals", Size = UDim2.fromOffset(0, H), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = -1, Visible = false }, speedRow)
	else
		local width = if panel:IsA("GuiObject") then panel.Size.X.Offset else 240
		frame = Ui.make("Frame", { Name = "Pedals", Size = UDim2.fromOffset(width, H), BackgroundTransparency = 1, LayoutOrder = 0, Visible = false }, panel)
	end
	local row: Frame = Ui.make("Frame", {
		Name = "Row",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(0, H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, frame)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, if touch then 4 else 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	-- the pedals, the brake on the left of the gas (as your feet find them)
	local brake = pedal(row, "Brake", 1, if touch then 30 else 48, H, if touch then 17 else 28, 3, true, K.red)
	local gas = pedal(row, "Gas", 2, if touch then 17 else 27, H, if touch then 28 else 46, if touch then 4 else 5, false, K.good)
	-- the selector: a dark pill, the letters one under the other, the gear's lit behind its letter
	local pillW = if touch then 18 else 26
	local pill: Frame = Ui.make("Frame", {
		Name = "Selector",
		Size = UDim2.fromOffset(pillW, H),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = K.scrim,
		BorderSizePixel = 0,
		LayoutOrder = 3,
	}, row)
	Ui.corner(pill, math.floor(pillW / 2))
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = K.lineAlpha }, pill)
	local letters: { [string]: TextLabel } = {}
	local marks: { [string]: Frame } = {}
	local step = (H - 4) / #PedalRules.Gears
	for n, gear in PedalRules.Gears do
		local y = 2 + (n - 1) * step
		local mark: Frame = Ui.make("Frame", {
			Name = `Lit{gear}`,
			Position = UDim2.fromOffset(2, math.floor(y + 0.5)),
			Size = UDim2.fromOffset(pillW - 4, math.floor(step + 0.5)),
			BackgroundColor3 = GEAR_LIT[gear] or K.text,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, pill)
		Ui.corner(mark, 4)
		marks[gear] = mark
		letters[gear] = Ui.label(pill, gear, UDim2.fromOffset(pillW, math.floor(step + 0.5)), {
			Name = `Gear{gear}`,
			Position = UDim2.fromOffset(0, math.floor(y + 0.5)),
			Font = Theme.HeadingFont,
			TextSize = if touch then 10 else 14,
			TextColor3 = K.line,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
		})
	end
	parts = { frame = frame, letters = letters, marks = marks, brake = brake, gas = gas }
	shown.on, shown.gear, shown.gas, shown.brake, shown.drawnGas, shown.drawnBrake = false, "", 0, 0, -1, -1
	return frame
end

local function setGear(p: Parts, gear: string)
	for name, label in p.letters do
		local active = name == gear
		label.TextColor3 = if active then K.charcoal else K.line
		p.marks[name].BackgroundTransparency = if active then 0.05 else 1
	end
end

function DrivePedals.draw(show: boolean, car: Model?, throttle: number, speed: number)
	local p = parts
	if not p then
		return
	end
	local visible = show and on() and car ~= nil and (car :: Model):GetAttribute("Bike") ~= true
	if p.frame.Visible ~= visible then
		p.frame.Visible = visible
	end
	local now = os.clock()
	local dt = math.clamp(now - shown.at, 0, 0.1)
	shown.at = now
	shown.on = visible
	if not visible then
		shown.gas, shown.brake = 0, 0
		return
	end
	local state = PedalRules.state(throttle, speed)
	if state.gear ~= shown.gear then
		shown.gear = state.gear
		setGear(p, state.gear)
	end
	shown.gas = PedalRules.ease(shown.gas, state.gas, dt)
	shown.brake = PedalRules.ease(shown.brake, state.brake, dt)
	if math.abs(shown.gas - shown.drawnGas) > 0.01 then
		shown.drawnGas = shown.gas
		press(p.gas, shown.gas)
	end
	if math.abs(shown.brake - shown.drawnBrake) > 0.01 then
		shown.drawnBrake = shown.brake
		press(p.brake, shown.brake)
	end
end

function DrivePedals.view(): { shown: boolean, gear: string, gas: number, brake: number }
	return { shown = shown.on, gear = shown.gear, gas = shown.gas, brake = shown.brake }
end

return DrivePedals
