--!strict
-- 10.6 SNATCHING, the client (server/Runs.luau decides everything; Config.Rounds.Tug; the rules shared/TugRules.luau):
-- your tug of war on the screen. Presentation only: the Tug remote's { kind = "start" | "state" | "end" | "stun", … }.
--   * The tug panel (above the screen's middle; on a phone at TOUCH_SCALE at least): what it is over and with whom, the
--     rope's bar (your side on the left: YOU, theirs on the right), the mark where the server says (your own presses
--     nudge it at once), the seconds left, what to press. Every press (E, Space, a click, a gamepad's A or X, the touch
--     PULL button a finger's size and more) is the Tug remote's { kind = "pull", id }, at most Tug.Rate a second; the
--     prompts are off while it goes on (none fires on your E).
--   * Its end: a big line for END_HOLD s (YOU SNATCHED IT! / YOU HELD ON! / they got it), a sound; stunned: STUNNED
--     until it wears off.
--   TugUi.start()     the remote, the screen
--   TugUi.active()    your tug now ({ id, side, other, name, p, endsAt }) or nil

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local TugUi = {}

local T = Config.Rounds.Tug
local K = Theme.Contract
local GOLD = Color3.fromRGB(255, 206, 92)
local MINE = Color3.fromRGB(126, 196, 120)
local THEIRS = Color3.fromRGB(215, 74, 70)
local W, H = 380, 168 -- px: the panel at scale 1
local PULL_H = 64 -- px: the touch PULL button
local TOUCH_SCALE = 0.85
local END_HOLD = 1.8
local KEYS = { [Enum.KeyCode.E] = true, [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.ButtonX] = true }

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local banner: TextLabel? = nil
local tug: { [string]: any }? = nil
local lastPress = -math.huge
local bannerUntil = 0
local stunUntil = 0
local promptsWere: number? = nil
local started = false

local function play(name: string)
	pcall(function()
		require(script.Parent.Sounds).play(name)
	end)
end

local function scaleNow(): number
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, TOUCH_SCALE)
	end
	return math.min(s, 1)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local made = Ui.make("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for key, value in props do
		(made :: any)[key] = value
	end
	return made
end

-- The prompts off while a tug goes on (your E is a pull, never a prompt), back as they were after it.
local function prompts(off: boolean)
	pcall(function()
		if off and promptsWere == nil then
			promptsWere = ProximityPromptService.MaxPromptsVisible
			ProximityPromptService.MaxPromptsVisible = 0
		elseif not off and promptsWere ~= nil then
			ProximityPromptService.MaxPromptsVisible = promptsWere :: number
			promptsWere = nil
		end
	end)
end

local function build(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local root = Ui.make("ScreenGui", { Name = "TugUi", ResetOnSpawn = false, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = root
	local words = text(root, "Banner", {
		Size = UDim2.new(0.92, 0, 0, 56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		TextSize = 30,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(820, 56) }, words)
	Ui.make("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14 }, words)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, words)
	banner = words
	return root
end

local function sendPull()
	local t = tug
	local r = remote
	local now = os.clock()
	if not t or not r or now - lastPress < 1 / T.Rate then
		return
	end
	lastPress = now
	r:FireServer({ kind = "pull", id = t.id })
	-- (your press at once on the bar: the server's mark follows a moment later)
	local mine = if t.side == "carrier" then -1 else 1
	t.p = math.clamp(t.p + mine * T.Pull * (if t.side == "carrier" then T.Boost else 1), -1, 1)
	play("grip_tick")
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
	end
	prompts(false)
end

local function open(t: { [string]: any })
	local root = build()
	if not root then
		return
	end
	close()
	local touch = Ui.touchLayout()
	local frame = Ui.make("Frame", {
		Name = "TugPanel",
		Size = UDim2.fromOffset(W, H + (if touch then PULL_H + 10 else 0)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if touch then 0.5 else 0.42),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Active = true,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, frame)
	Ui.corner(frame, 12)
	Ui.stroke(frame, GOLD, 2)
	text(frame, "Title", { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 8), TextSize = 18, TextColor3 = GOLD,
		Text = if t.side == "snatcher" then `🤼 SNATCH! · {string.upper(tostring(t.name or ""))}` else `🤼 HOLD ON! · {string.upper(tostring(t.name or ""))}` })
	text(frame, "Me", { Size = UDim2.fromOffset(150, 20), Position = UDim2.fromOffset(14, 38), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MINE, Text = "◀ YOU" })
	text(frame, "Them", { Size = UDim2.fromOffset(150, 20), Position = UDim2.new(1, -164, 0, 38), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEIRS,
		Text = `{string.upper(tostring(t.other or "?"))} ▶` })
	local track = Ui.make("Frame", { Name = "Track", Size = UDim2.new(1, -28, 0, 22), Position = UDim2.fromOffset(14, 64), BackgroundColor3 = K.track, BorderSizePixel = 0 }, frame)
	Ui.corner(track, 11)
	Ui.make("Frame", { Name = "Mine", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = MINE, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, track)
	Ui.make("Frame", { Name = "Middle", Size = UDim2.new(0, 2, 1, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = K.text, BorderSizePixel = 0 }, track)
	local knob = Ui.make("Frame", { Name = "Mark", Size = UDim2.fromOffset(18, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = GOLD, BorderSizePixel = 0 }, track)
	Ui.corner(knob, 6)
	text(frame, "Left", { Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 96), TextSize = 13, TextColor3 = K.secondary, Text = "" })
	text(frame, "Hint", { Size = UDim2.new(1, -28, 0, 26), Position = UDim2.fromOffset(14, 120), TextSize = 17, TextColor3 = K.text,
		Text = if touch then "TAP PULL AS FAST AS YOU CAN!" else "MASH  E  /  SPACE  /  CLICK!" })
	if touch then
		local pull = Ui.make("TextButton", {
			Name = "Pull",
			Text = "💪 PULL!",
			Size = UDim2.new(1, -28, 0, PULL_H),
			Position = UDim2.new(0, 14, 1, -(PULL_H + 12)),
			BackgroundColor3 = GOLD,
			Font = Theme.HeadingFont,
			TextSize = 26,
			TextColor3 = K.charcoal,
			AutoButtonColor = true,
		}, frame)
		Ui.corner(pull, 10)
		pull.Activated:Connect(sendPull)
	end
	panel = frame
	prompts(true)
end

local function show(line: string, color: Color3, seconds: number)
	build()
	local b = banner
	if b then
		b.Text = line
		b.TextColor3 = color
		b.Visible = true
		bannerUntil = os.clock() + seconds
	end
end

-- The panel as things stand (every frame while it is open: the mark, the seconds left).
local function refresh()
	local t = tug
	local frame = panel
	local b = banner
	if b and b.Visible and os.clock() >= bannerUntil then
		if stunUntil > workspace:GetServerTimeNow() then
			b.Text = "😵 STUNNED"
			b.TextColor3 = THEIRS
		else
			b.Visible = false
		end
	end
	if not t or not frame then
		return
	end
	local mine = if t.side == "carrier" then -t.p else t.p -- (+1: yours)
	local track = frame:FindFirstChild("Track")
	local mark = track and track:FindFirstChild("Mark")
	local fill = track and track:FindFirstChild("Mine")
	if mark and mark:IsA("Frame") and fill and fill:IsA("Frame") then
		local x = math.clamp(0.5 - mine * 0.5, 0, 1)
		mark.Position = UDim2.fromScale(x, 0.5)
		fill.Size = UDim2.fromScale(x, 1)
		mark.BackgroundColor3 = if mine > 0 then MINE elseif mine < 0 then THEIRS else GOLD
	end
	local left = frame:FindFirstChild("Left")
	if left and left:IsA("TextLabel") then
		local secs = math.max(0, (tonumber(t.endsAt) or 0) - workspace:GetServerTimeNow())
		left.Text = if mine > 0 then string.format("%.1f s · you're winning!", secs) else string.format("%.1f s · pull harder!", secs)
	end
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "start" and type(message.id) == "number" then
		lastPress = -math.huge -- (a new tug: its first press is heard)
		tug = { id = message.id, side = if message.side == "carrier" then "carrier" else "snatcher", other = message.other, name = message.name,
			icon = message.icon, p = tonumber(message.p) or T.Start, endsAt = tonumber(message.endsAt) or (workspace:GetServerTimeNow() + T.Seconds) }
		open(tug :: { [string]: any })
		play("grip_warning")
		refresh()
	elseif kind == "state" then
		local t = tug
		if t and t.id == message.id and type(message.p) == "number" then
			t.p = message.p
			refresh()
		end
	elseif kind == "end" then
		local t = tug
		if t and t.id == message.id then
			tug = nil
			close()
			if message.void ~= true then
				show(if message.won == true then `✅ {string.upper(tostring(message.text or ""))}` else `❌ {string.upper(tostring(message.text or ""))}`,
					if message.won == true then MINE else THEIRS, END_HOLD)
				play(if message.won == true then "task_done" else "grip_slip")
			end
		end
	elseif kind == "stun" and type(message.untilAt) == "number" then
		stunUntil = message.untilAt
	end
end

function TugUi.active(): { [string]: any }?
	return tug
end

function TugUi.start()
	if started or not Config.Sandbox.On or not Config.Rounds.On or not T.On then
		return
	end
	started = true
	local r = Net.get("Tug")
	remote = r
	r.OnClientEvent:Connect(onMessage)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not tug then
			return
		end
		if KEYS[input.KeyCode] or (input.UserInputType == Enum.UserInputType.MouseButton1 and not processed) then
			sendPull()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if tug or (banner and banner.Visible) then
			refresh()
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local S = scaleNow()
			for _, frame in { panel, banner } :: { GuiObject? } do
				local scale = if frame then frame:FindFirstChild("Scale") else nil
				if scale and scale:IsA("UIScale") then
					scale.Scale = S
				end
			end
		end)
	end
end

return TugUi
