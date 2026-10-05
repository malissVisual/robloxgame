--!strict
-- The leaderboard window: the best couriers on this server (L, or the TOP button in the HUD's button column). Every
-- player with their place, name, rank name, driver level (and how far into it), mission stars (3.0), deliveries and
-- money earned (and the title they show, 3.1), best first: by level, then mission stars, then money earned (the server sorts, server/Ranking.luau). Your own row is outlined, the ones out
-- on a job are tagged. While it is open it asks the server again every few seconds; closed it costs nothing.
-- While it is open the mouse is free (Main: CameraRig.mouseNeeded checks Leaderboard.isOpen()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local C = Ui.Colors
local P = Theme.Postage
local Leaderboard = {}

-- Set by the HUD: opening the board closes the HUD's windows (one window at a time).
Leaderboard.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer
local REFRESH = 3 -- seconds between two requests while the window is open
local MEDALS = { P.gold, P.silver, P.bronze } -- 3.6: the medal inks (their badges wear Theme.soft faces)

local gui: any = nil
local window: any = nil
local chrome: any = nil
local scale: any = nil
local body: any = nil
local summary: any = nil
local rows: { any } = {}
local polling = 0 -- bumps on every open / close: the old refresh loop stops
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Leaderboard")
	end
	return remote :: RemoteEvent
end

-- Is the game's interface on (after PLAY on the start screen)?
local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return not (hud and hud:IsA("ScreenGui")) or hud.Enabled
end

-- ── Building ───────────────────────────────────────────────────────────────

-- The column header and the cells of a row share these places (x offsets from the right edge).
local COLUMNS = {
	place = { x = 8, w = 44 },
	level = { right = 440, w = 120 },
	stars = { right = 312, w = 84 },
	deliveries = { right = 220, w = 90 },
	earned = { right = 110, w = 102 }, -- in the ticket's stub (EARNED_STUB)
}
local STAR_GOLD = P.gold
local EARNED_STUB = 118 -- 3.6: the EARNED column is the ticket's stub

-- The same rule as the Hud's windows (Ui.scaleFor), so the board matches them on every screen.
local function updateScale()
	if scale then
		scale.Scale = Ui.screenScale()
	end
end

local function build()
	if gui then
		return
	end
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryLeaderboard",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
	}, player:WaitForChild("PlayerGui"))
	-- 3.6: the lavender window (Ui.window), the rows are paper tickets with the money earned in the stub.
	local content
	window, content, chrome = Ui.window(gui, "Top couriers", "This server · by driver level, then mission stars, then money earned", "🏆", UDim2.fromOffset(760, 580))
	window.Visible = false
	chrome.onClose = function()
		Leaderboard.close()
	end
	chrome.context.Text = "L · TOP · refreshes every few seconds"
	scale = Ui.make("UIScale", {}, window)

	-- You: your place and what the next level needs.
	summary = Ui.label(content, "", UDim2.new(1, -48, 0, 32), {
		Position = UDim2.fromOffset(24, 14),
		BackgroundTransparency = 0,
		BackgroundColor3 = P.ticket,
		TextSize = 15,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.HeadingFont,
	})
	Ui.corner(summary, 6)
	Ui.stroke(summary, P.line, 1).Transparency = 0

	-- The column titles.
	local header = Ui.make("Frame", { Size = UDim2.new(1, -56, 0, 20), Position = UDim2.fromOffset(24, 56), BackgroundTransparency = 1 }, content)
	local function title(text: string, position: UDim2, width: number, align: Enum.TextXAlignment)
		Ui.caps(header, text, UDim2.new(0, width, 1, 0), { Position = position, TextXAlignment = align })
	end
	title("#", UDim2.fromOffset(COLUMNS.place.x, 0), COLUMNS.place.w, Enum.TextXAlignment.Center)
	title("COURIER", UDim2.fromOffset(62, 0), 200, Enum.TextXAlignment.Left)
	title("LEVEL", UDim2.new(1, -COLUMNS.level.right, 0, 0), COLUMNS.level.w, Enum.TextXAlignment.Left)
	title("STARS", UDim2.new(1, -COLUMNS.stars.right, 0, 0), COLUMNS.stars.w, Enum.TextXAlignment.Right)
	title("DELIVERIES", UDim2.new(1, -COLUMNS.deliveries.right, 0, 0), COLUMNS.deliveries.w, Enum.TextXAlignment.Right)
	title("EARNED", UDim2.new(1, -COLUMNS.earned.right, 0, 0), COLUMNS.earned.w, Enum.TextXAlignment.Center)

	body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -36, 1, -86),
		Position = UDim2.fromOffset(20, 80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(body, true, 12)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }, body)

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

-- ── Rendering ──────────────────────────────────────────────────────────────

local function row(entry: any, place: number)
	local mine = entry.userId == player.UserId
	-- 3.6: a paper ticket (your own one outlined in the crew violet), the money earned in its stub.
	local frame = Ui.ticket(body, UDim2.new(1, -16, 0, 56), UDim2.new(), nil, EARNED_STUB, 0, P.lavender)
	frame.Parent.LayoutOrder = place
	if mine then
		Ui.stroke(frame, P.violet, 1.5)
	end
	-- The place: the first three on medal badges.
	local medal = MEDALS[place]
	local badge = Ui.label(frame, tostring(place), UDim2.fromOffset(40, 40), {
		Position = UDim2.fromOffset(COLUMNS.place.x + 2, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = if medal then 20 else 17,
		Font = if medal then Theme.DisplayFont else Theme.MonoFont,
		TextColor3 = if medal then C.text else C.dim,
		BackgroundTransparency = if medal then 0 else 1,
		BackgroundColor3 = if medal then Theme.soft(medal).face else P.paper,
	})
	Ui.corner(badge, 20)
	if medal then
		Ui.stroke(badge, medal, 1.5)
	end
	-- Name and rank name (and the job tag).
	local name = `{entry.name}{if mine then "  (you)" else ""}`
	Ui.label(frame, name, UDim2.new(1, -(62 + COLUMNS.level.right + 10), 0, 24), {
		Position = UDim2.fromOffset(62, 6),
		TextSize = 18,
		Font = Theme.DisplayFont,
		TextColor3 = if mine then P.violet else C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = Ui.make("Frame", {
		Size = UDim2.new(1, -(62 + COLUMNS.level.right + 10), 0, 18),
		Position = UDim2.fromOffset(62, 31),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, frame)
	Ui.list(line, false, 6)
	Ui.label(line, tostring(entry.rank or Levels.rank(entry.level)), UDim2.new(0, 0, 1, 0), {
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.dim,
		LayoutOrder = 1,
	})
	-- 3.1: the title they show (server/Challenges.luau), in gold after the rank name.
	if type(entry.title) == "string" and entry.title ~= "" then
		Ui.label(line, `« {entry.title} »`, UDim2.new(0, 0, 1, 0), {
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = STAR_GOLD,
			LayoutOrder = 2,
		})
	end
	if entry.onJob then
		local chip = Ui.chip(line, "ON A JOB", C.green)
		chip.TextSize = 12
		chip.LayoutOrder = 3
	end
	-- The level and how far into it.
	local level = tonumber(entry.level) or 1
	local levelCell = Ui.make("Frame", {
		Size = UDim2.fromOffset(COLUMNS.level.w, 44),
		Position = UDim2.new(1, -COLUMNS.level.right, 0, 6),
		BackgroundTransparency = 1,
	}, frame)
	Ui.label(levelCell, `LV {level}`, UDim2.new(1, 0, 0, 24), {
		TextSize = 20,
		Font = Theme.DisplayFont,
		TextColor3 = if level >= Config.Levels.MaxLevel then MEDALS[1] else C.text,
	})
	local back, fill = Ui.bar(levelCell, UDim2.new(1, -16, 0, 6), P.violet)
	back.Position = UDim2.fromOffset(0, 30)
	fill.Size = UDim2.fromScale(math.clamp(tonumber(entry.progress) or 0, 0, 1), 1)
	-- The mission stars (the gold of a full 300 when every mission has 3).
	local stars = tonumber(entry.stars) or 0
	local starsMax = tonumber(entry.starsMax) or 0
	Ui.label(frame, `★ {stars}`, UDim2.fromOffset(COLUMNS.stars.w, 44), {
		Position = UDim2.new(1, -COLUMNS.stars.right, 0, 6),
		TextSize = 18,
		Font = Theme.DisplayFont,
		TextColor3 = if starsMax > 0 and stars >= starsMax then STAR_GOLD elseif stars > 0 then C.yellow else C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	Ui.label(frame, tostring(entry.deliveries or 0), UDim2.fromOffset(COLUMNS.deliveries.w, 44), {
		Position = UDim2.new(1, -COLUMNS.deliveries.right, 0, 6),
		TextSize = 18,
		Font = Theme.MonoFont,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- The money earned: the stub, like a ticket's payout.
	local earned = Ui.label(frame, Ui.money(tonumber(entry.earned) or 0), UDim2.fromOffset(EARNED_STUB - 16, 40), {
		Position = UDim2.new(1, -EARNED_STUB + 8, 0, 8),
		TextSize = 18,
		Font = Theme.MonoFont,
		TextColor3 = C.money,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12 }, earned)
end

local function render()
	if not body then
		return
	end
	Ui.clear(body)
	if #rows == 0 then
		Ui.label(body, "Asking the dispatcher...", UDim2.new(1, -10, 0, 60), { TextColor3 = C.dim, Font = Theme.Font, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center })
		summary.Text = ""
		return
	end
	local myPlace: number? = nil
	local myStars = 0
	for place, entry in rows do
		row(entry, place)
		if entry.userId == player.UserId then
			myPlace = place
			myStars = tonumber(entry.stars) or 0
		end
	end
	-- Your place, and the XP the next level needs.
	local xp = tonumber(player:GetAttribute("Xp")) or 0
	local level = Levels.levelFor(xp)
	local next = if level < Config.Levels.MaxLevel then ` · {Levels.xpFor(level + 1) - xp} XP to level {level + 1}` else " · top level"
	summary.Text = if myPlace then `You: #{myPlace} of {#rows} · LV {level} {Levels.rank(level)} · ★ {myStars}{next}` else `{#rows} couriers on this server`
end

local function onRows(list: any)
	if type(list) ~= "table" then
		return
	end
	rows = list
	if window and window.Visible then
		render()
	end
end

-- ── Open / close ───────────────────────────────────────────────────────────

function Leaderboard.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function Leaderboard.close()
	if window then
		window.Visible = false
	end
	polling += 1
end

function Leaderboard.open()
	build()
	if not hudOn() then
		return
	end
	local onOpen = Leaderboard.onOpen
	if onOpen then
		onOpen()
	end
	window.Visible = true
	render()
	polling += 1
	local mine = polling
	task.spawn(function()
		while polling == mine and window.Visible do
			getRemote():FireServer()
			task.wait(REFRESH)
		end
	end)
end

function Leaderboard.toggle()
	if Leaderboard.isOpen() then
		Leaderboard.close()
	else
		Leaderboard.open()
	end
end

function Leaderboard.start()
	build()
	getRemote().OnClientEvent:Connect(onRows)
	-- L opens and closes it (not while typing, e.g. in the chat).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or input.KeyCode ~= Enum.KeyCode.L then
			return
		end
		if hudOn() then
			Leaderboard.toggle()
		end
	end)
	-- The interface went off (back to the start screen): the board goes too.
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not hud.Enabled then
				Leaderboard.close()
			end
		end)
	end
end

return Leaderboard
