--!strict
-- 5.7: a little juice on the interface (Config.Juice). Presentation only.
--   * countMoney(label, amount): the HUD money (client/Hud.luau setState) runs up to a new, higher amount over
--     CountUpSeconds instead of jumping (a lower one is shown at once; so is the first). Under reduced motion: at once.
--   * confetti: a ★★★ rating (the DeliveryResult remote's rating.stars, the top of the scale) throws a small burst of
--     confetti from the top of the screen, ConfettiPieces for ConfettiSeconds (none under reduced motion).
-- Started by client/Sounds.luau (Sounds.start) so client/Main.client.luau stays as it is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local PhoneMotion = require(script.Parent.PhoneMotion)

local Juice = {}

local J = Config.Juice

-- ── The money counting up ──────────────────────────────────────────────────

type Counter = { shown: number, target: number, token: number }
local counters: { [Instance]: Counter } = {}

function Juice.countMoney(label: TextLabel, amount: number)
	local counter = counters[label]
	if not counter then
		counter = { shown = amount, target = amount, token = 0 }
		counters[label] = counter
		label.Destroying:Once(function()
			counters[label] = nil
		end)
		label.Text = Ui.money(amount)
		return
	end
	assert(counter)
	counter.token += 1
	counter.target = amount
	if amount <= counter.shown or PhoneMotion.reducedMotion() or J.CountUpSeconds <= 0 then
		counter.shown = amount
		label.Text = Ui.money(amount)
		return
	end
	local token = counter.token
	local from = counter.shown
	local started = os.clock()
	task.spawn(function()
		while counters[label] == counter and counter.token == token do
			local k = math.clamp((os.clock() - started) / J.CountUpSeconds, 0, 1)
			local eased = 1 - (1 - k) * (1 - k) * (1 - k)
			counter.shown = math.floor(from + (amount - from) * eased + 0.5)
			label.Text = Ui.money(counter.shown)
			if k >= 1 then
				counter.shown = amount
				label.Text = Ui.money(amount)
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- ── Confetti ───────────────────────────────────────────────────────────────

local PIECE_COLORS = {
	Theme.Colors.money,
	Theme.Colors.yellow,
	Theme.Colors.red,
	Theme.Colors.blue,
	Theme.Colors.text,
	Theme.Postage.gold,
}

local function confetti()
	if PhoneMotion.reducedMotion() then
		return
	end
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Confetti"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 60
	screen.Parent = gui
	type Bit = { frame: Frame, x: number, y: number, vx: number, vy: number, spin: number, turn: number }
	local bits: { Bit } = {}
	local size = screen.AbsoluteSize
	local width = if size.X > 0 then size.X else 1280
	for _ = 1, J.ConfettiPieces do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(math.random(6, 10), math.random(3, 6))
		frame.BackgroundColor3 = PIECE_COLORS[math.random(1, #PIECE_COLORS)]
		frame.Parent = screen
		table.insert(bits, {
			frame = frame,
			x = width * (0.5 + (math.random() - 0.5) * 0.35),
			y = -10,
			vx = (math.random() - 0.5) * 520,
			vy = 120 + math.random() * 260,
			spin = math.random() * 360,
			turn = (math.random() - 0.5) * 900,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local age = os.clock() - started
		if age >= J.ConfettiSeconds or not screen.Parent then
			if connection then
				connection:Disconnect()
			end
			screen:Destroy()
			return
		end
		local fade = math.clamp((age - J.ConfettiSeconds * 0.6) / (J.ConfettiSeconds * 0.4), 0, 1)
		for _, bit in bits do
			bit.vy += 520 * dt -- falling
			bit.vx *= math.exp(-1.6 * dt) -- the air slows the spread
			bit.x += bit.vx * dt
			bit.y += bit.vy * dt
			bit.spin += bit.turn * dt
			bit.frame.Position = UDim2.fromOffset(bit.x, bit.y)
			bit.frame.Rotation = bit.spin
			bit.frame.BackgroundTransparency = fade
		end
	end)
end
Juice.confetti = confetti

function Juice.start()
	Net.get("DeliveryResult").OnClientEvent:Connect(function(r: any)
		if type(r) ~= "table" or not r.success or type(r.rating) ~= "table" then
			return
		end
		if (tonumber(r.rating.stars) or 0) >= 3 then
			task.delay(0.25, confetti)
		end
	end)
end

return Juice
