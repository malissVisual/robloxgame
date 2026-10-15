--!strict
-- 7.0 planning (the owner's rework, design/rework/NAVRH.md §2: "the planning: a lobby like GTA's heists"): the move's
-- planning lobby on the client, in the 6.18 UI kit's look (client/CardKit.luau, design/ui-kit/README.md). The server
-- (server/MoveLobby.luau) decides everything and sends the lobby (the MoveLobby remote's "lobby", nil: closed); this
-- draws it and asks:
--   * the header: ZDC MOVING · PLANNING, the house big, chips (the clock, the horde, the crew n/max), ✕ folds it away
--     (a pill at the top brings it back: nothing is left);
--   * the contract (the kit's hero): the house's picture mark, the client and address, UP TO $ big in green, one facts
--     line (★ must-haves, things), DOOR OPEN in its corner (the client greets the crew there); the van under it (7.x van
--     moves: the owner's own van, its bay, SELECTED; bigger ones later);
--   * the crew (the kit's rows): each member with their role's icon, LEADER / YOU, the role, READY (green) / NOT READY
--     (red); the owner's + INVITE opens the crew panel (MoveLobbyUi.onInvite: client/CrewPanel.luau) and the lobby comes
--     back when it closes;
--   * PICK YOUR ROLE: the three role cards (shared/MoveRoles.luau: icon, name, what it does, its loadout line) side by
--     side, or one under the other where three would not fit (ROLE_MIN); yours lit in its colour, a crew mate's greyed
--     with their name (no doubles while there are no more players than roles);
--   * the footer: the one primary button: the owner's ▶ LAUNCH (green once everybody is READY; solo at once), a
--     member's ✔ I'M READY / NOT READY; and CANCEL (the owner) or LEAVE CREW (a member: the crew's own "leave").
--   * 8.8 (the owner: "I don't want roles in the game. Everyone is simply the same."; MoveRoles.on: the city's only,
--     never the sandbox): without roles no PICK YOUR ROLE and no role anywhere: a member's row has a plain 👤, says who
--     leads the move, and READY / NOT READY as ever.
-- Wide (Config.UiKit.SplitMin and more): the contract and the truck on the left, the crew and the roles on the right;
-- narrow (a phone held upright): one column that scrolls, the footer stays; a touch screen draws it at least
-- Config.MoveRoles.Lobby.TouchScale big (the body scrolls under the header). Presentation only.
--   MoveLobbyUi.start()       the remote
--   MoveLobbyUi.isOpen()      drawn (not folded away): the mouse is free (Main)
--   MoveLobbyUi.minimize()    fold it away (another window opens: Main's Hud.onCloseWindows)
--   MoveLobbyUi.onInvite      set by Main: open the crew panel
--   MoveLobbyUi.crewOpen      set by Main: is the crew panel open (the lobby comes back when it closes)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRoles = require(Shared.MoveRoles)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review: the folded planning's pill holds the top's middle

local MoveLobbyUi = {}

MoveLobbyUi.onInvite = nil :: (() -> ())?
MoveLobbyUi.crewOpen = nil :: (() -> boolean)?

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color
local KIT = Config.UiKit
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (the Moving Truck's)
local CARD_W = 860
local CARD_H = 640
local HEAD_H = 64
local FOOT_H = 72
local ROLE_H = 170 -- a role card side by side (its words wrap in a third of the column, its kit a short list)
local ROLE_ROW = 100 -- a role card one under the other (a narrow column: the words wrap less)
local ROLE_MIN = 134 -- a role card's least width side by side

local remote = Net.get("MoveLobby")
local crewRemote = Net.get("CrewAnswer")
local gui: ScreenGui? = nil
local view: any = nil -- the server's lobby (nil: none)
local backdrop: any = nil
local pill: any = nil
local folded = false
local backAfterCrew = false -- INVITE folded it: back when the crew panel closes
local lastOwner: number? = nil

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "MoveLobby",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 6, -- (under the move's own cards: client/MovingHud.luau 7)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function sound(name: string)
	pcall(function()
		(require(script.Parent.Sounds) :: any).play(name, 0.7)
	end)
end

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

local function label(parent: Instance, value: string, size: UDim2, props: { [string]: any }): any
	local made = Ui.label(parent, value, size, { Font = Theme.Font, TextSize = 14, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	for key, prop in props do
		made[key] = prop
	end
	return made
end

local function clock(seconds: number): string
	return Ui.clock(math.max(0, seconds))
end

-- ── The parts ──────────────────────────────────────────────────────────────

local function section(parent: Instance, text: string, order: number, chip: CardKit.Chip?)
	CardKit.sectionHeader(parent, { name = `Head{order}`, text = text, order = order, chip = chip })
end

local function memberRow(parent: Instance, member: any, order: number)
	local roles = MoveRoles.on() -- (8.8: no roles: nobody's shown)
	local def = if roles then MoveRoles.get(member.role) else nil
	local state: string, color: Color3
	if member.owner == true then
		state, color = "LEADER", C.gold
	elseif member.ready == true then
		state, color = "READY", K.good
	else
		state, color = "NOT READY", K.red
	end
	local tag = if member.you == true then " · YOU" else ""
	CardKit.row(parent, {
		name = `Member{order}`,
		order = order,
		accent = color,
		picture = { emoji = if def then def.icon else "👤" },
		thumb = KIT.Icon,
		emojiSize = 26,
		title = `{string.upper(tostring(member.name))}{tag}`,
		titleColor = if member.you == true then C.title else K.secondary,
		facts = if def then `{def.name} · {def.blurb}` elseif roles then "Picking a role" elseif member.owner == true then "Leads the move" else "On the crew",
		value = state,
		valueColor = color,
		silent = true,
		onOpen = function() end,
	})
end

-- A role card: its icon, name, what it does and its loadout; yours lit, a crew mate's greyed with their name. `tall`:
-- side by side, a third of the column (the state under the name's line, the words wrapped); else a row across it.
local function roleCard(parent: Instance, id: string, order: number, holder: string?, mine: boolean, tall: boolean)
	local def = MoveRoles.get(id)
	if not def then
		return
	end
	local color = rgb(def.color)
	local taken = holder ~= nil and not mine
	local card = Ui.make("TextButton", {
		Name = `Role_{id}`,
		Size = UDim2.fromOffset(100, if tall then ROLE_H else ROLE_ROW),
		BackgroundColor3 = if mine then K.raised else K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		ClipsDescendants = true,
	}, parent)
	Ui.corner(card, KIT.RowCorner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if mine then color else K.line, Thickness = if mine then 2 else 1, Transparency = if mine then 0 else 0.75 }, card)
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = if taken then K.track else color, BorderSizePixel = 0 }, card)
	label(card, def.icon, UDim2.fromOffset(36, 36), { Name = "Icon", Position = UDim2.fromOffset(12, 10), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = if taken then 0.5 else 0 })
	label(card, string.upper(def.name), UDim2.new(1, -60, 0, 18), {
		Name = "Name",
		Position = UDim2.fromOffset(54, 10),
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = if taken then C.dim else color,
	})
	label(card, if mine then "✔ YOURS" elseif taken then `TAKEN · {string.upper(holder :: string)}` else "FREE · TAP TO PICK", UDim2.new(1, if tall then -24 else -60, 0, 14), {
		Name = "State",
		Position = if tall then UDim2.fromOffset(14, 50) else UDim2.fromOffset(54, 30),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = if mine then color elseif taken then C.dim else C.faint,
	})
	label(card, def.blurb, UDim2.new(1, -24, 0, if tall then 30 else 16), {
		Name = "Blurb",
		Position = UDim2.fromOffset(14, if tall then 68 else 52),
		TextSize = 12,
		TextColor3 = if taken then C.dim else K.secondary,
		TextWrapped = tall,
		TextTruncate = if tall then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	-- the loadout: a line (a row across the column) or, side by side, a short list (one piece of the kit a line)
	local loadout = MoveRoles.loadout(id)
	if tall then
		loadout = (string.gsub(loadout, " · ", "\n"))
	end
	label(card, loadout, UDim2.new(1, -24, 0, if tall then 66 else 26), {
		Name = "Loadout",
		Position = UDim2.fromOffset(14, if tall then 100 else 70),
		TextSize = 11,
		TextColor3 = if taken then C.dim else C.faint,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	card.Activated:Connect(function()
		if not mine and not taken then
			CardKit.click()
			remote:FireServer("role", id)
		end
	end)
end

local function roleGrid(parent: Instance, v: any, width: number, order: number)
	local holders: { [string]: string } = {}
	local mine = v.role
	for _, member in v.members or {} do
		if type(member.role) == "string" and member.you ~= true and v.doubles ~= true then
			holders[member.role] = tostring(member.name)
		end
	end
	-- the three side by side when each gets ROLE_MIN, else one under the other (a narrow phone held upright)
	local count = #MoveRoles.Order
	local gap = KIT.Gap
	local tall = width >= count * ROLE_MIN + gap * (count - 1)
	local columns = if tall then count else 1
	local cell = math.floor((width - gap * (columns - 1)) / columns)
	local grid = Ui.make("Frame", { Name = "Roles", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(cell, if tall then ROLE_H else ROLE_ROW), CellPadding = UDim2.fromOffset(gap, gap), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for index, id in MoveRoles.Order do
		roleCard(grid, id, index, holders[id], mine == id, tall)
	end
end

local function truckRows(parent: Instance, v: any, order: number)
	local card = v.card or {}
	local van = Config.Moving.Beds[Config.Moving.Van] -- (7.x van moves: the owner's van's bay)
	local bed = if type(card.bed) == "table" then card.bed else { van.Width, van.Length }
	section(parent, "YOUR VAN", order) -- (7.x van moves: the move goes with the owner's own van, trip after trip)
	CardKit.row(parent, {
		name = "Truck",
		order = order + 1,
		accent = ORANGE,
		picture = { emoji = "🚐" },
		thumb = KIT.Icon,
		emojiSize = 26,
		title = string.upper(tostring(card.truck or "ZDC Van")),
		titleColor = C.title,
		facts = `Bay {bed[1]} × {bed[2]} studs · as many trips as it takes`,
		word = "✔ SELECTED",
		wordInk = K.good,
		silent = true,
		onOpen = function() end,
	})
	CardKit.row(parent, {
		name = "MoreTrucks",
		order = order + 2,
		accent = K.track,
		picture = { emoji = "🚛" },
		thumb = KIT.Icon,
		emojiSize = 26,
		shut = true,
		title = "BIGGER VEHICLES",
		facts = "Box van, trailer: as ZDC Moving grows",
		lock = "🔒 SOON",
		silent = true,
		onOpen = function() end,
	})
end

-- ── The lobby ──────────────────────────────────────────────────────────────

local function close()
	if backdrop then
		Ui.gamepadRelease(backdrop)
		backdrop:Destroy()
		backdrop = nil
	end
end

local function drawPill()
	local root = screen()
	local v = view
	if not root then
		return
	end
	if not v or not folded then
		if pill then
			pill.Visible = false
		end
		return
	end
	if not pill then
		pill = Ui.make("TextButton", {
			Name = "PlanningPill",
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0.5, 0, 0, 8),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = K.charcoal,
			BackgroundTransparency = Theme.PanelTransparency,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = K.text,
			Text = "",
		}, root)
		Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, pill)
		Ui.corner(pill, 17)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, pill)
		Ui.make("UIStroke", { Color = ORANGE, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
		pill.Activated:Connect(function()
			CardKit.click()
			MoveLobbyUi.unfold()
		end)
		TopBlocks.set("PlanningPill", pill)
	end
	local members = v.members or {}
	local ready = 0
	for _, member in members do
		if member.ready == true then
			ready += 1
		end
	end
	local card = v.card or {}
	pill.Text = `📋 PLANNING · {string.upper(tostring(card.name or "MOVE"))} · {ready}/{#members} READY · OPEN ›`
	pill.Visible = true
end

local function draw()
	local root = screen()
	local v = view
	if not root or not v or folded then
		close()
		drawPill()
		return
	end
	drawPill()
	local keep = Vector2.zero
	local oldBody = backdrop and backdrop:FindFirstChild("Body", true)
	if oldBody and oldBody:IsA("ScrollingFrame") then
		keep = oldBody.CanvasPosition
	end
	close()
	local card = v.card or {}
	local scale = if Ui.touchLayout() then math.max(Ui.screenScale(), Config.MoveRoles.Lobby.TouchScale) else Ui.screenScale() -- (a phone: bigger, it scrolls)
	local area = Ui.screenSize() / scale
	-- 7.0 review: a touch screen's footer buttons a finger's height after the card's scale (Ui.MinTouch screen px)
	local button = if Ui.touchLayout() then math.max(48, math.ceil(Ui.MinTouch / scale)) else 48
	local footH = FOOT_H + (button - 48)
	local W = math.floor(math.min(CARD_W, area.X - 24))
	local H = math.floor(math.min(CARD_H, area.Y - 16))
	local wide = W >= KIT.SplitMin + 40
	local shade = Ui.make("TextButton", {
		Name = "MoveLobby",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
	}, root)
	backdrop = shade
	local frame = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		Active = true,
	}, shade)
	Ui.make("UIScale", { Name = "Scale", Scale = scale }, frame)
	Ui.corner(frame, KIT.Corner)
	Ui.make("UIStroke", { Color = ORANGE, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)

	-- the header: what this is, the house, the chips; ✕ folds it away
	label(frame, "ZDC MOVING · PLANNING", UDim2.new(1, -60, 0, 16), { Name = "Kicker", Position = UDim2.fromOffset(18, 12), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = ORANGE })
	label(frame, `{card.icon or "🏠"} {string.upper(tostring(card.name or "MOVE"))}`, UDim2.new(if wide then 0.5 else 1, -70, 0, 28), {
		Name = "Title",
		Position = UDim2.fromOffset(18, 28),
		Font = Theme.HeadingFont,
		TextSize = 24,
		TextColor3 = C.title,
	})
	local members = v.members or {}
	local chips = Ui.make("Frame", {
		Name = "Chips",
		Size = UDim2.new(if wide then 0.5 else 1, if wide then -64 else -36, 0, KIT.Chip),
		Position = if wide then UDim2.new(0.5, 0, 0, 34) else UDim2.fromOffset(18, HEAD_H - 4),
		BackgroundTransparency = 1,
	}, frame)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if wide then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, KIT.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chips)
	local time = tonumber(card.time) or Config.Moving.Time
	CardKit.chip(chips, { name = "Clock", text = `⏱ {math.floor(time / 60)} MIN`, order = 1, static = true })
	local hordeAt = tonumber(card.hordeAt) or Config.Moving.HordeAt -- (8.0 SANDBOX: 0, no horde)
	CardKit.chip(chips, { name = "Horde", text = if hordeAt > 0 then `🧟 AT {clock(hordeAt)} LEFT` else "🧟 NO HORDE", order = 2, static = true, face = C.rushFace, ink = C.rushInk })
	CardKit.chip(chips, { name = "Crew", text = `👥 {#members}/{tonumber(v.maxCrew) or 4}`, order = 3, static = true })
	local fold = Ui.closeButton(frame, function()
		MoveLobbyUi.minimize()
	end)
	fold.Position = UDim2.new(1, -8, 0, 8)

	-- the body: scrolls between the header and the footer
	local top = if wide then HEAD_H + 8 else HEAD_H + KIT.Chip + 6
	local body = Ui.make("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, -24, 1, -(top + footH)),
		Position = UDim2.fromOffset(12, top),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, frame)
	local inner = W - 24 - 8
	local left: any, right: any
	local leftW, rightW = inner, inner
	if wide then
		leftW = math.floor((inner - 12) * KIT.HeroShare)
		rightW = inner - 12 - leftW
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		left = Ui.make("Frame", { Name = "Left", Size = UDim2.fromOffset(leftW, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, body)
		right = Ui.make("Frame", { Name = "Right", Size = UDim2.fromOffset(rightW, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, body)
		Ui.list(left, true, KIT.Gap)
		Ui.list(right, true, KIT.Gap)
	else
		Ui.list(body, true, KIT.Gap)
		local column = Ui.make("Frame", { Name = "Column", Size = UDim2.fromOffset(inner, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, body)
		Ui.list(column, true, KIT.Gap)
		left, right = column, column
	end

	-- the contract (the hero) and the truck
	local stars = if type(card.stars) == "table" then #card.stars else 0
	local facts = `★ {stars} MUST-HAVES · 📦 {tonumber(card.items) or 0} THINGS`
	CardKit.hero(left, {
		name = "Contract",
		order = 1,
		height = if wide then 230 else KIT.HeroMin,
		picture = { emoji = tostring(card.icon or "🏠") },
		stroke = ORANGE,
		title = `{string.upper(tostring(card.client or ""))} · {string.upper(tostring(card.address or ""))}`,
		value = `UP TO {Ui.money(tonumber(card.estimate) or 0)}`,
		facts = facts,
		ribbon = { text = "📋 CONTRACT", face = ORANGE, ink = C.goldInk },
		corner = { text = "DOOR OPEN", ink = K.good, width = 96 }, -- (the client greets the crew at it: server/MoveGreeters.luau)
		silent = true,
	})
	if wide then
		truckRows(left, v, 10)
	end

	-- the crew, the roles (8.8: the crew only without roles)
	local owner = v.mine == true
	section(right, `CREW {#members}/{tonumber(v.maxCrew) or 4}`, 20, if owner then {
		name = "Invite",
		text = "+ INVITE",
		face = K.red,
		ink = C.white,
		onClick = function()
			local invite = MoveLobbyUi.onInvite
			if invite then
				backAfterCrew = true
				MoveLobbyUi.minimize()
				invite()
			end
		end,
	} else nil)
	for index, member in members do
		memberRow(right, member, 20 + index)
	end
	if MoveRoles.on() then -- (8.8: no roles, nothing to pick)
		section(right, if v.doubles == true then "PICK YOUR ROLE · MORE OF YOU THAN ROLES: DOUBLES OK" else "PICK YOUR ROLE · ONE EACH", 40)
		roleGrid(right, v, rightW, 41)
	end
	if not wide then
		truckRows(right, v, 50)
	end
	body.CanvasPosition = keep

	-- the footer: CANCEL / LEAVE CREW, and the one primary button
	local foot = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, -36, 0, button), Position = UDim2.new(0, 18, 1, -(button + 12)), BackgroundTransparency = 1 }, frame)
	local quietW = if W >= 420 then 150 else 110
	local quiet = Ui.make("Frame", { Name = "Quiet", Size = UDim2.new(0, quietW, 1, 0), BackgroundTransparency = 1 }, foot)
	local quietButton = CardKit.bigButton(quiet, {
		name = if owner then "Cancel" else "Leave",
		text = if owner then "CANCEL" else "LEAVE CREW",
		kind = "shut",
		height = button,
		textSize = 14,
		onClick = function()
			if owner then
				remote:FireServer("cancel")
			else
				crewRemote:FireServer("leave") -- (server/Crew.luau: out of the crew, so out of its planning)
			end
		end,
	})
	quietButton.TextColor3 = K.red
	local main = Ui.make("Frame", { Name = "Main", Size = UDim2.new(1, -(quietW + 12), 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, foot)
	local primary: any
	if owner then
		local waiting = tonumber(v.waiting) or 0
		local go = v.canLaunch == true
		primary = CardKit.bigButton(main, {
			name = "Launch",
			text = if go then (if #members <= 1 then "▶ LAUNCH · SOLO" else "▶ LAUNCH THE MOVE") else `WAITING FOR {waiting} · READY`,
			kind = if go then "good" else "shut",
			height = button,
			onClick = function()
				remote:FireServer("launch")
			end,
		})
	else
		local ready = v.ready == true
		primary = CardKit.bigButton(main, {
			name = "Ready",
			text = if ready then "READY ✔ · TAP: NOT READY" else "✔ I'M READY",
			kind = if ready then "shut" else "good",
			height = button,
			onClick = function()
				remote:FireServer("ready", not ready)
			end,
		})
	end
	Ui.gamepadFocus(primary)
end

function MoveLobbyUi.isOpen(): boolean
	return backdrop ~= nil
end

function MoveLobbyUi.minimize()
	if view and not folded then
		folded = true
		close()
		drawPill()
	end
end

function MoveLobbyUi.unfold()
	backAfterCrew = false
	if view then
		folded = false
		draw()
	end
end

local function setView(next: any)
	local was = view
	view = if type(next) == "table" then next else nil
	if not view then
		folded = false
		backAfterCrew = false
		lastOwner = nil
		close()
		drawPill()
		return
	end
	if not was or lastOwner ~= view.owner then
		folded = false -- (a new planning opens in front)
		lastOwner = view.owner
		sound("notify")
	end
	draw()
end

function MoveLobbyUi.start()
	screen()
	remote.OnClientEvent:Connect(function(kind: any, a: any)
		if kind == "lobby" then
			setView(a)
		end
	end)
	-- INVITE folded it for the crew panel: back when that closes
	task.spawn(function()
		while true do
			task.wait(0.3)
			local crewOpen = MoveLobbyUi.crewOpen
			if backAfterCrew and view and folded and crewOpen and not crewOpen() then
				MoveLobbyUi.unfold()
			end
		end
	end)
	remote:FireServer("state")
end

return MoveLobbyUi
