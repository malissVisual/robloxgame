--!strict
-- 9.7 RUNS, the client (server/Runs.luau decides everything; Config.Runs; the rules shared/RunRules.luau): the pad panel
-- while you stand on a portal's pad and the run's results card. Presentation only: the Runs remote asks.
--   * The pad panel (a computer's top centre under the HUD's top row; a touch screen's top right): the house's name, its countdown and how many go ("STARTING IN
--     7 S · 2/4"), who is on the pad in their order (the host first), and the difficulty: the host picks it on a row of
--     five buttons (the ones not open yet 🔒: a tap says how to open them; the one picked lit in its colour; the
--     Runs remote's { kind = "difficulty", id }), everybody else reads it ("NORMAL · Ann picks"). Gone when you step
--     off the pad or the run starts. On a phone at Config.Runs.Panel.TouchScale at least, its buttons a finger's size.
--   * The results card (the middle of the screen, over the game, until OK or ESC): how the run ended, the pieces that
--     went home (each with its rarity's colour stripe and stars, ★ common … ★★★★★ legendary, its value and whose
--     warehouse it went to; the best first, the rest in a list that scrolls), the total value, yours, a difficulty
--     that opened ("🔓 HARD is open"). On a phone it fits the screen (the list scrolls).
--   RunUi.start()     the remote, the screen
--   RunUi.pad()       the pad you stand on now ({ house, mine, … }: the server's view) or nil (client/SandboxGuide.luau)
--   RunUi.run()       the run you are in now ({ house, mine, … }) or nil
--   RunUi.isOpen()    the results card is open (it frees the mouse: Main's windowOpen)
--   RunUi.close()     closes the results card (ESC: Main's Hud.onCloseWindows)
--   RunUi.onOpen      set by Main: called when the card opens (one window at a time)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunRules = require(Shared.RunRules)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local RunUi = {}

local R = Config.Runs
local K = Theme.Contract
local GOLD = Color3.fromRGB(255, 206, 92)
local MONEY = Color3.fromRGB(140, 220, 120)
local ROW = 30 -- px: a piece's row on the card
local BUTTON = 56 -- px: a difficulty button's height (a finger's size at the touch scale)
local OK = 56 -- px: the results card's OK (the same)
local PANEL_TOP = 120 -- px: the pad panel's top on a computer (under the HUD's top row of chips and key hints)

local remote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local card: Frame? = nil
local padView: { [string]: any }? = nil
local runView: { [string]: any }? = nil
local padKey = ""

RunUi.onOpen = nil :: (() -> ())?

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function scaleNow(): number
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, R.Panel.TouchScale)
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

local function send(message: { [string]: any })
	local r = remote
	if r then
		r:FireServer(message)
	end
end

-- ── The pad panel ──────────────────────────────────────────────────────────

local function closePanel()
	if panel then
		panel:Destroy()
		panel = nil
	end
	padKey = ""
end

local function drawPanel(view: { [string]: any })
	local root = screenGui()
	if not root then
		return
	end
	local key = `{view.house}|{view.left}|{view.hostName}|{view.difficulty}|{table.concat(view.party or {}, ",")}|{table.concat(view.open or {}, ",")}|{view.mine}`
	if panel and key == padKey then
		return
	end
	padKey = key
	if panel then
		panel:Destroy()
	end
	local W = math.max(R.Panel.Width, 420)
	local mine = view.mine == true
	local H = 12 + 24 + 20 + 34 + (if mine then BUTTON + 8 else 22) + 10
	-- (a computer: the top centre under the HUD's top row, the guide's line stepping aside while the panel shows; a touch
	-- screen: the top right, clear of the HUD's money and chips at the left and of the touch buttons under it)
	local touch = Ui.touchLayout()
	local frame = Ui.make("Frame", {
		Name = "PadPanel",
		Size = UDim2.fromOffset(W, H),
		Position = if touch then UDim2.new(1, -16, 0, 8) else UDim2.new(0.5, 0, 0, PANEL_TOP),
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, frame)
	Ui.corner(frame, 10)
	Ui.stroke(frame, rgb(R.Portal.Waiting), 2)
	panel = frame
	label(frame, "Title", `🏡 {string.upper(tostring(view.name or ""))}`, UDim2.new(1, -24, 0, 24), { Position = UDim2.fromOffset(12, 10), Font = Theme.HeadingFont, TextSize = 18 })
	local going = tonumber(view.going) or 0
	label(frame, "Countdown", `STARTING IN {tonumber(view.left) or 0} S · {going}/{tonumber(view.max) or R.MaxParty} GOING`, UDim2.new(1, -24, 0, 18),
		{ Position = UDim2.fromOffset(12, 36), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = rgb(R.Portal.Waiting) })
	local names = view.party or {}
	local line = {}
	for n, name in names do
		table.insert(line, if n == 1 then `{name} (host)` elseif n > (tonumber(view.max) or R.MaxParty) then `{name} (waits)` else tostring(name))
	end
	label(frame, "Party", table.concat(line, " · "), UDim2.new(1, -24, 0, 30), { Position = UDim2.fromOffset(12, 56), TextSize = 12, TextColor3 = K.secondary, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local picked = RunRules.def(view.difficulty) or (RunRules.def(R.Default) :: Config.RunDifficulty)
	if not mine then
		label(frame, "Difficulty", `{string.upper(picked.name)} · {view.hostName} picks the difficulty`, UDim2.new(1, -24, 0, 18),
			{ Position = UDim2.fromOffset(12, 90), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = rgb(picked.color) })
		return
	end
	local row = Ui.make("Frame", { Name = "Difficulties", Size = UDim2.new(1, -24, 0, BUTTON), Position = UDim2.fromOffset(12, 90), BackgroundTransparency = 1 }, frame)
	local list = RunRules.list()
	local gap = 4
	local each = (W - 24 - gap * (#list - 1)) / #list
	local open: { [string]: boolean } = {}
	for _, id in view.open or {} do
		open[id] = true
	end
	for n, def in list do
		local isOpen = open[def.id] == true
		local isPicked = def.id == picked.id
		local button = Ui.make("TextButton", {
			Name = `Difficulty_{def.id}`,
			Text = if isOpen then string.upper(def.name) else `🔒 {string.upper(def.name)}`,
			Size = UDim2.fromOffset(each, BUTTON),
			Position = UDim2.fromOffset((n - 1) * (each + gap), 0),
			BackgroundColor3 = if isPicked then rgb(def.color) else K.row,
			BackgroundTransparency = if isOpen then 0 else 0.4,
			AutoButtonColor = isOpen,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextWrapped = not isOpen,
			TextColor3 = if isPicked then K.charcoal elseif isOpen then rgb(def.color) else K.secondary,
		}, row)
		Ui.corner(button, 6)
		button.Activated:Connect(function()
			if isOpen then
				send({ kind = "difficulty", id = def.id })
			else
				local before = list[n - 1]
				local old = frame:FindFirstChild("Locked")
				if old then
					old:Destroy()
				end
				local toast = label(frame, "Locked", `🔒 Finish a run at {if before then string.upper(before.name) else "the one before"} to open {string.upper(def.name)}`,
					UDim2.new(1, -24, 0, 16), { Position = UDim2.new(0, 12, 1, 4), TextSize = 12, TextColor3 = GOLD, TextWrapped = true })
				task.delay(3, function()
					toast:Destroy()
				end)
			end
		end)
	end
end

-- ── The results card ───────────────────────────────────────────────────────

local HEAD: { [string]: string } = { done = "RUN COMPLETE", late = "TIME'S UP", cancelled = "RUN CALLED OFF", failed = "NOTHING CAME HOME" }

function RunUi.close()
	if card then
		card:Destroy()
		card = nil
	end
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
	local fixed = 12 + 22 + 34 + 30 + 20 + 8 + (if opened then 24 else 0) + OK + 8 + 12
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
	if kind == "pad" then
		if message.house == nil then
			padView = nil
			closePanel()
		else
			padView = message
			drawPanel(message)
		end
	elseif kind == "run" then
		runView = if message.house ~= nil then message else nil
		if runView then
			padView = nil
			closePanel()
		end
	elseif kind == "result" then
		runView = nil
		showResult(message)
	end
end

function RunUi.pad(): { [string]: any }?
	return padView
end

function RunUi.run(): { [string]: any }?
	return runView
end

function RunUi.isOpen(): boolean
	return card ~= nil
end

function RunUi.start()
	if not Config.Sandbox.On then
		return
	end
	local r = Net.get("Runs")
	remote = r
	r.OnClientEvent:Connect(onMessage)
	-- (a resize: the panel and the card at the new scale)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local S = scaleNow()
			for _, frame in { panel, card } do
				local scale = if frame then frame:FindFirstChild("Scale") else nil
				if scale and scale:IsA("UIScale") then
					scale.Scale = S
				end
			end
		end)
	end
	r:FireServer({ kind = "state" })
end

return RunUi
