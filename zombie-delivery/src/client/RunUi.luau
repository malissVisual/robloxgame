--!strict
-- 9.7 RUNS, the client (server/Runs.luau decides everything; Config.Runs; the rules shared/RunRules.luau): the run's
-- results card; 10.4 the PLAY panel at the lobby's PLAY circle and the party lobby's bar (client/PlayUi.luau, started
-- here: the six portals' pad panel is gone). Presentation only: the Runs and Party remotes ask.
--   * The results card (the middle of the screen, over the game, until OK or ESC): how the run ended, the pieces that
--     went home (each with its rarity's colour stripe and stars, ★ common … ★★★★★ legendary, its value and whose
--     warehouse it went to; the best first, the rest in a list that scrolls), the total value, yours, a difficulty
--     that opened ("🔓 HARD is open"). On a phone it fits the screen (the list scrolls). 10.x danger: a line for the
--     run's danger when it had any (the result's `danger`, server/RunDanger.luau: "🗝 VAULT OPENED ✓ · 🧟 ZOMBIES
--     STOPPED: 7").
--   RunUi.start()     the remote, the screen; 10.4 PlayUi.start
--   RunUi.play()      10.4: the PLAY view now (client/PlayUi.luau's: { circle, lobby?, lobbies, houses, … }) or nil
--   RunUi.lobby()     10.4: your party lobby now ({ house, mine, members, endsAt, … }) or nil (client/SandboxGuide.luau)
--   RunUi.run()       the run you are in now ({ house, mine, … }) or nil
--   RunUi.isOpen()    the results card or the PLAY panel is open (a window: it frees the mouse, Main's windowOpen)
--   RunUi.close()     closes the results card and the PLAY panel (ESC: Main's Hud.onCloseWindows)
--   RunUi.onOpen      set by Main: called when the card or the PLAY panel opens (one window at a time)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunRules = require(Shared.RunRules)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local PlayUi = require(script.Parent.PlayUi) -- 10.4: the PLAY panel and the lobby bar

local RunUi = {}

local R = Config.Runs
local K = Theme.Contract
local GOLD = Color3.fromRGB(255, 206, 92)
local MONEY = Color3.fromRGB(140, 220, 120)
local ROW = 30 -- px: a piece's row on the card
local OK = 56 -- px: the results card's OK (a finger's size at the touch scale)

local gui: ScreenGui? = nil
local card: Frame? = nil
local runView: { [string]: any }? = nil

RunUi.onOpen = nil :: (() -> ())?

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function scaleNow(): number
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, R.Result.TouchScale)
	end
	return math.min(s, 1)
end

local function screenGui(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", { Name = "RunUi", ResetOnSpawn = false, DisplayOrder = 22, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = made
	return made
end

local function label(parent: Instance, name: string, text: string, size: UDim2, props: { [string]: any }?): TextLabel
	local made = Ui.make("TextLabel", {
		Name = name,
		Text = text,
		Size = size,
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	if props then
		for key, value in props do
			(made :: any)[key] = value
		end
	end
	return made
end

-- ── The results card ───────────────────────────────────────────────────────

local HEAD: { [string]: string } = { done = "RUN COMPLETE", late = "TIME'S UP", cancelled = "RUN CALLED OFF", failed = "NOTHING CAME HOME" }

function RunUi.close()
	if card then
		card:Destroy()
		card = nil
	end
	PlayUi.close() -- (10.4: the PLAY panel too; its bar stays)
end

-- 10.x danger: the results card's danger line (the result's `danger`: vault true / false / nil, stopped), nil none.
local function dangerText(danger: any): string?
	if type(danger) ~= "table" then
		return nil
	end
	local parts: { string } = {}
	if danger.vault == true then
		table.insert(parts, "🗝 VAULT OPENED ✓")
	elseif danger.vault == false then
		table.insert(parts, "🗝 VAULT OPENED ✗")
	end
	local stopped = tonumber(danger.stopped) or 0
	if stopped > 0 or danger.zombies == true then
		table.insert(parts, `🧟 ZOMBIES STOPPED: {stopped}`)
	end
	return if #parts > 0 then table.concat(parts, " · ") else nil
end

local function tierOf(rarity: any): (Config.CollectionTier, number)
	local tier = Config.Collection.Tiers[if type(rarity) == "string" then rarity else "common"] or Config.Collection.Tiers.common
	return tier, tier.rank
end

local function showResult(r: { [string]: any })
	local root = screenGui()
	if not root then
		return
	end
	RunUi.close()
	local hook = RunUi.onOpen
	if hook then
		pcall(hook)
	end
	local S = scaleNow()
	local camera = workspace.CurrentCamera
	local screenH = if camera then camera.ViewportSize.Y - 36 else 600
	local W = R.Result.Width
	local pieces = if type(r.pieces) == "table" then r.pieces else {}
	local def = RunRules.def(r.difficulty)
	local opened = type(r.openedName) == "string"
	local danger = dangerText(r.danger) -- 10.x danger
	local fixed = 12 + 22 + 34 + 30 + 20 + 8 + (if opened then 24 else 0) + (if danger then 22 else 0) + OK + 8 + 12
	local room = math.max(ROW * 2, math.floor((screenH - 16) / S) - fixed)
	local listH = math.min(#pieces, R.Result.Rows) * ROW
	listH = math.max(if #pieces > 0 then ROW else 0, math.min(listH, room))
	local H = fixed + listH
	local frame = Ui.make("Frame", {
		Name = "RunResult",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Active = true,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = S }, frame)
	Ui.corner(frame, 12)
	local good = r.phase == "done" or r.phase == "late"
	Ui.stroke(frame, if good then K.good else K.red, 2)
	card = frame
	local y = 12
	label(frame, "Head", `{HEAD[r.phase] or "RUN OVER"} · {string.upper(tostring(r.name or ""))} · {if def then string.upper(def.name) else ""}`, UDim2.new(1, -24, 0, 20),
		{ Position = UDim2.fromOffset(12, y), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = if good then K.good else K.red, TextTruncate = Enum.TextTruncate.AtEnd })
	y += 22
	label(frame, "Why", tostring(r.why or ""), UDim2.new(1, -24, 0, 32), { Position = UDim2.fromOffset(12, y), TextSize = 12, TextColor3 = K.secondary, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	y += 34
	local count, value = tonumber(r.count) or 0, tonumber(r.value) or 0
	label(frame, "Total", `{count} PIECE{if count == 1 then "" else "S"} HOME · {Ui.money(value)}`, UDim2.new(1, -24, 0, 28),
		{ Position = UDim2.fromOffset(12, y), Font = Theme.HeadingFont, TextSize = 22, TextColor3 = MONEY, TextXAlignment = Enum.TextXAlignment.Center })
	y += 30
	local mine, mineValue = tonumber(r.mine) or 0, tonumber(r.mineValue) or 0
	label(frame, "Yours", `YOURS: {mine} · {Ui.money(mineValue)} → your warehouse`, UDim2.new(1, -24, 0, 18),
		{ Position = UDim2.fromOffset(12, y), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = K.text, TextXAlignment = Enum.TextXAlignment.Center })
	y += 20 + 8
	if danger then
		label(frame, "Danger", danger, UDim2.new(1, -24, 0, 18),
			{ Position = UDim2.fromOffset(12, y - 4), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center })
		y += 22
	end
	local list = Ui.make("ScrollingFrame", {
		Name = "Pieces",
		Size = UDim2.new(1, -16, 0, listH),
		Position = UDim2.fromOffset(8, y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.fromOffset(0, #pieces * ROW),
	}, frame)
	local me = tonumber(r.me)
	for n, piece in pieces do
		local tier, rank = tierOf(piece.rarity)
		local c = rgb(tier.color)
		local rowFrame = Ui.make("Frame", {
			Name = `Piece{n}`,
			Size = UDim2.new(1, -6, 0, ROW - 4),
			Position = UDim2.fromOffset(0, (n - 1) * ROW),
			BackgroundColor3 = K.row,
			BorderSizePixel = 0,
		}, list)
		Ui.corner(rowFrame, 5)
		Ui.make("Frame", { Name = "Rarity", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = c, BorderSizePixel = 0 }, rowFrame)
		label(rowFrame, "Stars", string.rep("★", rank), UDim2.fromOffset(68, ROW - 4), { Position = UDim2.fromOffset(8, 0), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = c })
		label(rowFrame, "Name", `{piece.icon or "📦"} {piece.name or ""}`, UDim2.new(1, -222, 0, ROW - 4),
			{ Position = UDim2.fromOffset(78, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = if piece.to == me then K.text else K.secondary })
		label(rowFrame, "Who", tostring(piece.by or ""), UDim2.fromOffset(70, ROW - 4),
			{ Position = UDim2.new(1, -142, 0, 0), TextSize = 11, TextColor3 = K.secondary, TextTruncate = Enum.TextTruncate.AtEnd })
		label(rowFrame, "Value", Ui.money(tonumber(piece.value) or 0), UDim2.fromOffset(64, ROW - 4),
			{ Position = UDim2.new(1, -70, 0, 0), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = MONEY, TextXAlignment = Enum.TextXAlignment.Right })
	end
	y += listH
	if opened then
		y += 4
		label(frame, "Unlocked", `🔓 {string.upper(tostring(r.openedName))} IS OPEN NOW`, UDim2.new(1, -24, 0, 20),
			{ Position = UDim2.fromOffset(12, y), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center })
		y += 20
	end
	local ok = Ui.make("TextButton", {
		Name = "Ok",
		Text = "OK",
		Size = UDim2.new(1, -24, 0, OK),
		Position = UDim2.new(0, 12, 1, -(OK + 12)),
		BackgroundColor3 = if good then K.good else K.track,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.charcoal,
	}, frame)
	Ui.corner(ok, 8)
	ok.Activated:Connect(RunUi.close)
	pcall(Ui.gamepadFocus, ok)
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "run" then
		runView = if message.house ~= nil then message else nil
	elseif kind == "result" then
		runView = nil
		showResult(message)
	end
end

function RunUi.play(): { [string]: any }?
	return PlayUi.view()
end

function RunUi.lobby(): { [string]: any }?
	local view = PlayUi.view()
	return if view then view.lobby else nil
end

function RunUi.run(): { [string]: any }?
	return runView
end

function RunUi.isOpen(): boolean
	return card ~= nil or PlayUi.isOpen()
end

function RunUi.start()
	if not Config.Sandbox.On then
		return
	end
	local r = Net.get("Runs")
	r.OnClientEvent:Connect(onMessage)
	-- (a resize: the card at the new scale; the PLAY panel follows its own)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local open = card
			local scale = if open then open:FindFirstChild("Scale") else nil
			if scale and scale:IsA("UIScale") then
				scale.Scale = scaleNow()
			end
		end)
	end
	r:FireServer({ kind = "state" })
	-- 10.4 the PLAY panel (its window is this one: opening it closes the others)
	PlayUi.onOpen = function()
		local hook = RunUi.onOpen
		if hook then
			pcall(hook)
		end
	end
	PlayUi.start()
end

return RunUi
