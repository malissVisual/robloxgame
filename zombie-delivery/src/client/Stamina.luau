--!strict
-- 3.7: the sprint's breath (Config.Movement). A full breath is Stamina seconds of sprint; it drains only while you
-- really sprint and move, and comes back over Recover seconds once you have stopped for RecoverDelay. Run it dry and
-- the sprint stops: you walk, and Shift does nothing until MinToSprint of it is back (no stutter at the empty end).
-- CameraRig asks it every frame (Stamina.update) whether Shift may sprint. While the breath is not full a thin bar
-- shows it at the bottom centre (its own ScreenGui, not in Hud), red when it is nearly empty, gone again HideAfter
-- seconds after it is full.
-- The breath itself is pure (Stamina.new / step / canSprint / barShown / low): tests/stamina_test.luau runs it in the
-- plain Luau CLI, so nothing at the top level of this module may touch Roblox; start() and update() do that.

local Stamina = {}

export type Tuning = {
	Stamina: number,
	Recover: number,
	RecoverDelay: number,
	MinToSprint: number,
	Low: number,
	HideAfter: number,
}

export type State = {
	breath: number, -- 0 (empty) .. 1 (full)
	exhausted: boolean, -- ran dry: no sprint until the breath is back to MinToSprint
	rest: number, -- seconds since the last sprinting step (the breath waits RecoverDelay before it comes back)
	full: number, -- seconds the breath has been full (the bar hides after HideAfter)
	sprinting: boolean, -- the last step's answer: Shift wanted a sprint and the breath allowed it
}

-- A full breath, rested (the bar starts hidden).
function Stamina.new(): State
	return { breath = 1, exhausted = false, rest = math.huge, full = math.huge, sprinting = false }
end

-- May Shift sprint now? Not with an empty breath, nor after running dry until MinToSprint is back.
function Stamina.canSprint(state: State): boolean
	return not state.exhausted and state.breath > 0
end

-- One step of `dt` seconds: `wantSprint` is Shift held where a sprint is allowed (not aiming, not carrying), `moving`
-- whether the character really goes somewhere. Returns the next state (the given one is left as it was).
function Stamina.step(state: State, dt: number, wantSprint: boolean, moving: boolean, tuning: Tuning): State
	dt = math.max(0, dt)
	local breath, exhausted, rest = state.breath, state.exhausted, state.rest
	local sprinting = wantSprint and Stamina.canSprint(state)
	if sprinting and moving then
		breath -= dt / math.max(0.01, tuning.Stamina)
		rest = 0
		if breath <= 0 then
			-- Out of breath: the sprint stops right here.
			breath = 0
			exhausted = true
			sprinting = false
		end
	else
		-- Only the part of this step past RecoverDelay brings breath back.
		local before = rest
		rest += dt
		local back = math.max(0, rest - math.max(before, tuning.RecoverDelay))
		breath = math.min(1, breath + back / math.max(0.01, tuning.Recover))
		if exhausted and breath >= tuning.MinToSprint then
			exhausted = false
		end
	end
	return {
		breath = breath,
		exhausted = exhausted,
		rest = rest,
		full = if breath >= 1 then state.full + dt else 0,
		sprinting = sprinting,
	}
end

-- Should the bar be on screen: the breath is not full, or it filled up less than HideAfter seconds ago.
function Stamina.barShown(state: State, tuning: Tuning): boolean
	return state.breath < 1 or state.full < tuning.HideAfter
end

-- Nearly empty or out of breath: the bar turns red.
function Stamina.low(state: State, tuning: Tuning): boolean
	return state.exhausted or state.breath <= tuning.Low
end

-- ── The local player's breath (Roblox from here on) ────────────────────────────

local current = Stamina.new()
local movement: Tuning? = nil

local function tuningNow(): Tuning
	local found = movement
	if not found then
		local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
		found = Config.Movement
		movement = found
	end
	return found :: Tuning
end

-- CameraRig, every frame on foot: steps the breath and answers whether the character sprints now.
function Stamina.update(dt: number, wantSprint: boolean, moving: boolean): boolean
	current = Stamina.step(current, dt, wantSprint, moving, tuningNow())
	return current.sprinting
end

-- The local player's breath right now (0 .. 1).
function Stamina.breath(): number
	return current.breath
end

-- ── The breath bar ─────────────────────────────────────────────────────────────
-- The contract style: a thin white line on a faint charcoal track, about 120×4 px, at the bottom centre over the
-- item tags and the contextual hint (the centre of the screen stays clear). Red (#D74A46) when nearly empty; out of
-- breath it says so in small words too (never by colour alone). It fades, it never flashes.

local TRACK_ALPHA = 0.45 -- how much of the charcoal track shows (a faint scrim)
local FADE = 4 -- per second: in or out in a quarter of a second
local TINT = 5 -- per second: white to red (and back) in a fifth of a second

function Stamina.start()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Ui = require(script.Parent.Ui)
	local Theme = require(script.Parent.Theme)
	local player = Players.LocalPlayer
	-- The contract colours (Color3 is Roblox's: here, not at the top level).
	local TEXT = Color3.fromRGB(242, 242, 240) -- #F2F2F0
	local SECONDARY = Color3.fromRGB(196, 199, 203) -- #C4C7CB
	local CHARCOAL = Color3.fromRGB(20, 23, 28) -- #14171C
	local RED = Color3.fromRGB(215, 74, 70) -- #D74A46

	-- A new character starts rested.
	player.CharacterAdded:Connect(function()
		current = Stamina.new()
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Breath"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- under Roblox's top bar
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- clear of a phone's notch and rounded corners
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4 -- under the crosshair (5)
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.Name = "Bar"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.BackgroundColor3 = CHARCOAL
	track.BorderSizePixel = 0
	track.Parent = holder

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = TEXT
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = track

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.BackgroundTransparency = 1
	caption.Font = Theme.Font
	caption.Text = "OUT OF BREATH"
	caption.TextColor3 = SECONDARY
	caption.TextStrokeColor3 = CHARCOAL
	caption.Parent = holder

	-- Sizes and the place follow the screen's scale (Ui.screenScale, like the HUD): the bar sits over the item tags
	-- and the room the HUD keeps for the contextual hint above them.
	local laidFor = Vector2.zero
	local function layout()
		local size = Ui.screenSize()
		if size == laidFor then
			return
		end
		laidFor = size
		local s = Ui.screenScale()
		local width = math.floor(120 * math.clamp(s, 0.8, 1.1) + 0.5)
		local thick = math.max(3, math.floor(4 * s + 0.5))
		local textSize = math.max(11, math.floor(12 * s + 0.5))
		holder.Size = UDim2.fromOffset(width, thick + textSize + 6)
		holder.Position = UDim2.new(0.5, 0, 1, -math.floor(16 + 170 * s + 0.5))
		track.Size = UDim2.fromOffset(width, thick)
		caption.TextSize = textSize
		caption.Size = UDim2.fromOffset(width * 2, textSize)
		caption.Position = UDim2.new(0.5, 0, 1, -(thick + 5))
	end

	local alpha = 0 -- 0 = hidden, 1 = shown
	local red = 0 -- 0 = white, 1 = the red accent
	local outOfBreath = 0 -- the caption's own fade
	local sinceLayout = math.huge
	RunService.RenderStepped:Connect(function(dt: number)
		local tuning = tuningNow()
		local state = current
		local shown = Stamina.barShown(state, tuning)
		if not shown and alpha <= 0 then
			if holder.Visible then
				holder.Visible = false
			end
			return
		end
		-- The screen's size is checked a few times a second, not every frame.
		sinceLayout += dt
		if sinceLayout >= 0.5 then
			sinceLayout = 0
			layout()
		end
		-- Even fades (no easing that never quite arrives): in or out in 1 / FADE seconds.
		alpha = math.clamp(alpha + (if shown then dt else -dt) * FADE, 0, 1)
		red = math.clamp(red + (if Stamina.low(state, tuning) then dt else -dt) * TINT, 0, 1)
		outOfBreath = math.clamp(outOfBreath + (if state.exhausted then dt else -dt) * FADE, 0, 1)
		holder.Visible = alpha > 0
		fill.Size = UDim2.fromScale(math.clamp(state.breath, 0, 1), 1)
		fill.BackgroundColor3 = TEXT:Lerp(RED, red)
		fill.BackgroundTransparency = 1 - alpha
		track.BackgroundTransparency = 1 - alpha * TRACK_ALPHA
		local captionAlpha = alpha * outOfBreath
		caption.TextTransparency = 1 - captionAlpha
		caption.TextStrokeTransparency = 1 - captionAlpha * 0.5
	end)
end

return Stamina
