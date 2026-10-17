--!strict
-- 5.7: a little juice on the interface (Config.Juice). Presentation only.
--   * countMoney(label, amount): the HUD's money (client/SandboxHud.luau) runs up to a new, higher amount over
--     CountUpSeconds instead of jumping (a lower one is shown at once; so is the first). Under reduced motion: at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
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

return Juice
