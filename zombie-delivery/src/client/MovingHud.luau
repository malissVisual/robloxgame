--!strict
-- 7.0, MOVES on the client (server/Moving.luau decides everything; shared/MovingRules.luau has the rules). 9.7: every
-- move is a run (the state's `run`: server/Moving.luau's SB.runView; client/RunUi.luau has the pad panel and the run's
-- results card):
--   * the move's panel at the top in the middle while a run goes ("state"): the house, the clock (amber with the horde,
--     red in the last minute), the checklist (IN THE TRUCK n/total · ★ · the difficulty, broken), the truck's room as a
--     bar and what to do next (load the truck and FINISH at it, or beat the clock); a tap on it (or O) opens the list;
--     the host's FINISH, the others' VOTE FINISH (the Runs remote's "vote"), each asked twice;
--   * the list (O): THE VAN first (CALL VAN TO DOOR for anybody of the crew: the Moving remote's "call", once a move:
--     whoever is first), then every thing with its picture, ★, how it is carried (✋ one hand, 🙌 both, 👥 two),
--     fragile, where it is (in the house, carried by …, on the ground, in the truck) and its condition; the host's GIVE
--     UP (twice), the others' LEAVE THE RUN (the Runs remote's "leave", asked twice);
--   * the fade at a door ("fade": client/Fade.luau);
--   * the move's prompts only for its crew (the tag MovePrompt: MoveOwner = the move's owner, shown when your player
--     attribute MoveWith is theirs; MoveOnly = for that player alone; MoveSkip = not for that player), hidden by their
--     reach like client/CargoPrompts.luau.
-- No GPS: the guide's chevron and path (client/SandboxGuide.luau) point the way. 7.0 review: after 0:00 (the state's
-- graceEndsAt) the panel counts down in red. Where it all sits is client/MoveLayout.luau's (pure). The panel is a
-- top-centre block (client/TopBlocks.luau: the helper's strip, the quick chat's lines and the guide's line keep clear
-- of it) and follows the screen's size. The list is drawn again only when what it shows changed (a cheap key); on a
-- computer it sits at the right under the panel and under Roblox's player list, on a touch screen it is a sheet over
-- the whole height (its GIVE UP at the end of what scrolls). The key is O (Tab is Roblox's player list), a key another
-- thing took is left alone. ESC closes the list (MovingHud.closeAll, Main's Hud.onCloseWindows).
--   MovingHud.start(), isOpen(), active(), closeAll(), panel()
-- 8.3 keys (shared/SandboxPad.luau, client/PadGlyph.luau): the panel's words name the keys of the device used now, a
-- gamepad used last first: what to do next ("Pick up the loot (E)", "(X)" with a gamepad, no key on a touch screen: the
-- prompt is tapped) and the list's hint ("LIST [O]", "TAP: LIST" on a touch screen, none with a gamepad: no button opens
-- it). Every refresh, so they follow a gamepad picked up or put down.
-- Presentation only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local SandboxPad = require(Shared.SandboxPad) -- 8.3 keys
local Ui = require(script.Parent.Ui)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 keys: the device used now
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Fade = require(script.Parent.Fade)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review: where the panel and the list sit
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review: the panel holds the top's middle

local MovingHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color
local TAG = "MovePrompt"
local ORANGE = Color3.fromRGB(240, 132, 44)
local PANEL_W = MoveLayout.PANEL_W
local PANEL_H = MoveLayout.PANEL_H -- (its last row: FINISH's)
local LIST_KEY = Enum.KeyCode.O -- 7.0 review: Tab is Roblox's player list (L the leaderboard)
local GIVE_UP_SURE = 3 -- s: a second tap of GIVE UP within this gives the move up (7.x van moves: FINISH's too)

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local state: any = nil -- the server's view of your move (nil: none)
local refs: { [string]: any } = {} -- the panel's labels and bars
local listFrame: any = nil
local listOpen = false
local listKey = "" -- 7.0 review: what the open list shows (drawn again only when this changes)
local giveUpAt = 0 -- 7.0 review: the first tap of GIVE UP (os.clock)
local finishAt = 0 -- the first tap of FINISH (os.clock)
local hidden: { [ProximityPrompt]: number } = {} -- the move prompts hidden for you, with their reach

-- ── Small helpers ──────────────────────────────────────────────────────────

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "MovingHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }): any
	local label = Ui.label(parent, value, size, { Font = Theme.Font, TextSize = 14, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	for key, prop in props do
		label[key] = prop
	end
	return label
end

local function scaled(frame: Instance)
	Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, frame)
end

local function clock(seconds: number): string
	return Ui.clock(math.max(0, seconds))
end

local CLASS_TEXT: { [string]: string } = { hand = "✋ one hand", both = "🙌 both hands", pair = "👥 two people" }
local STATE_TEXT: { [string]: string } = { home = "IN THE HOUSE", carried = "CARRIED", ground = "ON THE GROUND", truck = "IN THE VAN", delivered = "HOME", lost = "LOST" }

-- ── The prompts of your move only ──────────────────────────────────────────

local function shows(prompt: ProximityPrompt): boolean
	-- (7.0 review: "Enter house" is each move's own: its MoveOwner)
	local only = prompt:GetAttribute("MoveOnly")
	if type(only) == "number" then
		return only == player.UserId
	end
	if prompt:GetAttribute("MoveSkip") == player.UserId then
		return false
	end
	local owner = prompt:GetAttribute("MoveOwner")
	return type(owner) ~= "number" or owner == player.UserId or player:GetAttribute("MoveWith") == owner
end

local function apply(prompt: ProximityPrompt)
	if shows(prompt) then
		local reach = hidden[prompt]
		if reach then
			hidden[prompt] = nil
			if prompt.MaxActivationDistance == 0 then
				prompt.MaxActivationDistance = reach
			end
		end
	elseif not hidden[prompt] and prompt.MaxActivationDistance > 0 then
		hidden[prompt] = prompt.MaxActivationDistance
		prompt.MaxActivationDistance = 0
	end
end

local function applyAll()
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("ProximityPrompt") then
			apply(instance)
		end
	end
end

local function watchPrompts()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			apply(instance)
			-- (MoveSkip / MoveOnly change as the thing changes hands)
			instance.AttributeChanged:Connect(function()
				apply(instance)
			end)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			hidden[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("ProximityPrompt") then
			apply(instance)
			instance.AttributeChanged:Connect(function()
				apply(instance)
			end)
		end
	end
	player:GetAttributeChangedSignal("MoveWith"):Connect(applyAll)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, TAG) and not shows(prompt) then
			hidden[prompt] = nil
			apply(prompt)
		end
	end)
end

-- ── The panel ──────────────────────────────────────────────────────────────

local toggleList: () -> ()
local refreshPanel: () -> ()

local function buildPanel(root: ScreenGui)
	local panel = Ui.make("TextButton", {
		Name = "MovePanel",
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, root)
	scaled(panel)
	Ui.corner(panel, 8)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	refs.panel = panel
	refs.panelScale = panel:FindFirstChild("Scale")
	TopBlocks.set("MovePanel", panel) -- 7.0 review: the top's middle is the panel's
	refs.edge = panel:FindFirstChild("Edge")
	refs.title = text(panel, "", UDim2.new(1, -120, 0, 20), { Position = UDim2.fromOffset(12, 8), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = C.title })
	refs.timer = text(panel, "", UDim2.fromOffset(100, 24), { Position = UDim2.new(1, -12, 0, 6), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right })
	refs.check = text(panel, "", UDim2.new(1, -110, 0, 18), { Position = UDim2.fromOffset(12, 32), TextColor3 = K.secondary })
	refs.hint = text(panel, Ui.touchLayout() and "TAP: LIST" or "LIST [O]", UDim2.fromOffset(96, 16), {
		Position = UDim2.new(1, -12, 0, 34),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = C.faint,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	refs.truckLabel = text(panel, "", UDim2.fromOffset(110, 16), { Position = UDim2.fromOffset(12, 54), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary })
	local track = Ui.make("Frame", { Name = "Track", Size = UDim2.new(1, -136, 0, 8), Position = UDim2.fromOffset(124, 58), BackgroundColor3 = K.track, BorderSizePixel = 0 }, panel)
	Ui.corner(track, 4)
	refs.fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, track)
	Ui.corner(refs.fill, 4)
	refs.next = text(panel, "", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(12, 74), TextSize = 13, TextColor3 = K.text })
	-- the host's FINISH, the others' VOTE FINISH (each asked twice)
	local finish = CardKit.bigButton(panel, {
		name = "Finish",
		text = "✓ FINISH",
		kind = "good",
		height = 22,
		textSize = 12,
		onClick = function()
			if os.clock() - finishAt <= GIVE_UP_SURE then
				finishAt = 0
				local run = if type(state) == "table" and type(state.run) == "table" then state.run else nil
				if run and run.mine ~= true then
					Net.get("Runs"):FireServer({ kind = "vote" }) -- a party member's vote to finish
				else
					remote:FireServer("finish")
				end
				return
			end
			finishAt = os.clock()
			refreshPanel()
		end,
	})
	finish.Size = UDim2.fromOffset(112, 22)
	finish.Position = UDim2.new(1, -12, 0, 92)
	finish.AnchorPoint = Vector2.new(1, 0)
	finish.Visible = false
	refs.finish = finish
	panel.Activated:Connect(function()
		toggleList()
	end)
end

-- 8.3 keys: a prompt's key at the end of the words, for the device used now (shared/SandboxPad.luau withKey: "(E)",
-- "(X)", none on a touch screen).
local function keyed(text: string): string
	return SandboxPad.withKey(text, "use", PadGlyph.device())
end

-- 8.3 keys: the list's hint (its key, a touch screen's tap, none with a gamepad).
local function listHint(): string
	local device = PadGlyph.device()
	local key = SandboxPad.keyWord("list", device)
	return if key then `LIST [{key}]` elseif device == "touch" then "TAP: LIST" else ""
end

-- What to do now, from the state: the truck at the door, no driving.
local function nextStep(s: any): string
	local counts = s.counts or {}
	local out, total = tonumber(counts.out) or 0, tonumber(counts.total) or 0
	local carried = tonumber(counts.carried) or 0
	if s.inside == true then
		return if carried > 0 then "Carry it out: walk out through a door" else `{keyed("Pick up the loot")} · ★ first`
	elseif carried > 0 then
		return if s.backOpen == true then keyed("Load it into the truck") else `{keyed("Open the truck's back")}, then Load`
	elseif out > 0 and out >= total then
		return "Everything is in the truck: FINISH at the truck"
	end
	return if out > 0 then "Load more, or FINISH at the truck before the clock runs out" else `Walk in through {s.name}'s door`
end

refreshPanel = function()
	local panel = refs.panel
	if not panel then
		return
	end
	local s = state
	panel.Visible = type(s) == "table"
	if type(s) ~= "table" then
		return
	end
	local nowAt = workspace:GetServerTimeNow()
	local left = (tonumber(s.endsAt) or nowAt) - nowAt
	local hordeIn = (tonumber(s.hordeAt) or nowAt) - nowAt
	local counts = s.counts or {}
	refs.title.Text = `{s.icon or "🏠"} {string.upper(s.name or "MOVE")}{if s.mine == true then "" else ` · {s.owner}'s move`}`
	-- 7.0 review: after 0:00 a grace (the state's graceEndsAt): its countdown, red
	local grace = tonumber(s.graceEndsAt)
	local late = grace ~= nil and left <= 0
	refs.timer.Text = if late and grace then `⏱ {clock(grace - nowAt)}` else `⏱ {clock(left)}`
	refs.timer.TextColor3 = if left <= 60 then K.red elseif s.horde == true then K.warn else K.text
	local broken = tonumber(counts.broken) or 0
	-- what is in the truck, the stars, the difficulty
	local run = if type(s.run) == "table" then s.run else {}
	refs.check.Text = `IN THE TRUCK {counts.out or 0}/{counts.total or 0} · ★ {counts.stars or 0} · {string.upper(tostring(run.name or ""))}{if broken > 0 then ` · 💥 {broken}` else ""}{if s.horde ~= true and hordeIn > 0 then ` · 🧟 {clock(hordeIn)}` else ""}`
	local fill = math.clamp(tonumber(s.fill) or 0, 0, 1)
	refs.truckLabel.Text = `🚐 VAN {math.floor(fill * 100 + 0.5)}%`
	refs.fill.Size = UDim2.fromScale(fill, 1)
	refs.fill.BackgroundColor3 = if fill > 0.9 then K.red elseif fill > 0.7 then K.warn else ORANGE
	refs.next.Text = if late and grace then `⏱ TIME'S UP · {clock(grace - nowAt)}` else nextStep(s)
	refs.next.TextColor3 = if s.horde == true or late then K.red else K.text
	refs.hint.Text = listHint() -- 8.3 keys
	local finish = refs.finish -- the host's FINISH, the others' vote (asked twice)
	if finish then
		local sure = os.clock() - finishAt <= GIVE_UP_SURE
		local voter = run.mine ~= true and s.mine ~= true
		finish.Visible = true
		finish.Text = if sure then (if voter then "TAP TO VOTE" else "TAP TO FINISH") elseif voter then "✓ VOTE FINISH" else "✓ FINISH"
	end
	if refs.edge then
		refs.edge.Color = if s.horde == true then K.red else ORANGE
	end
end

-- ── The list (O) ───────────────────────────────────────────────────────────

-- Roblox's player list on a computer (top right), nil when it is off or on a touch screen.
local function playerListBox(W: number, H: number): TouchLayout.Box?
	if Ui.touchLayout() then
		return nil
	end
	local ok, on = pcall(function(): boolean
		return game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	if ok and on == false then
		return nil
	end
	local count = 1
	pcall(function()
		count = #Players:GetPlayers()
	end)
	return TouchLayout.box(W - 16 - MoveLayout.PLAYER_LIST_W, 0, W, math.min(H * 0.45, 52 + 40 * count))
end

-- Where the list goes (px in this gui) and its scale; `sheet`: a touch screen's sheet over the whole height.
local function listBox(): (TouchLayout.Box, number, boolean)
	local size = Ui.screenSize()
	local S = Ui.screenScale()
	local root = gui
	local under = TopBlocks.bottom(if root then root.AbsolutePosition else nil) or MoveLayout.panel(size.X, S).y1
	return MoveLayout.list(size.X, size.Y, S, Ui.touchLayout(), under, playerListBox(size.X, size.Y))
end

local function itemRow(parent: Instance, item: any, order: number)
	local row = Ui.make("Frame", { Name = `Item{item.spot}`, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = order }, parent)
	Ui.corner(row, 6)
	local accent = if item.broken == true then K.red elseif item.state == "truck" or item.state == "delivered" then K.good elseif item.star == true then C.gold else K.rule
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(4, 6), BackgroundColor3 = accent, BorderSizePixel = 0 }, row)
	text(row, tostring(item.icon or "📦"), UDim2.fromOffset(36, 36), { Position = UDim2.fromOffset(12, 8), TextSize = 26, Font = Theme.Font, TextXAlignment = Enum.TextXAlignment.Center })
	text(row, `{item.name}{if item.star == true then " ★" else ""}`, UDim2.new(1, -150, 0, 18), {
		Position = UDim2.fromOffset(54, 7),
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if item.star == true then C.gold else K.text,
	})
	local facts = CLASS_TEXT[item.class] or ""
	if item.fragile == true then
		facts ..= " · fragile"
	end
	text(row, facts, UDim2.new(1, -150, 0, 16), { Position = UDim2.fromOffset(54, 28), TextSize = 12, TextColor3 = C.faint })
	local where = if item.state == "delivered" and type(state) == "table" and state.drop then "HOME" else STATE_TEXT[item.state] or ""
	if item.state == "carried" and type(item.by) == "string" then
		where = if item.mine == true then "IN YOUR HANDS" else `CARRIED · {string.upper(item.by)}`
	end
	text(row, where, UDim2.fromOffset(92, 16), {
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = if item.state == "truck" or item.state == "delivered" then K.good elseif item.state == "carried" then ORANGE else K.secondary,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local condition = math.floor((tonumber(item.condition) or 1) * 100 + 0.5)
	text(row, if item.broken == true then "BROKEN" else `{condition}%`, UDim2.fromOffset(92, 18), {
		Position = UDim2.new(1, -8, 0, 26),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if item.broken == true then K.red elseif condition < 60 then K.warn else K.text,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

-- THE VAN at the list's top: the call to the door, anybody's of the crew (once a move: the state's team.called).
local function vanCard(parent: Instance, s: any, finger: number)
	local team = if type(s.team) == "table" then s.team else {}
	local card = Ui.make("Frame", { Name = "Van", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = 0 }, parent)
	Ui.corner(card, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, card)
	Ui.list(card, true, 6)
	text(card, "🚐 THE VAN", UDim2.new(1, 0, 0, 18), { LayoutOrder = 1, Font = Theme.HeadingFont, TextSize = 14, TextColor3 = ORANGE })
	text(card, "Anybody of the crew calls it to the house's door, once a move.", UDim2.new(1, 0, 0, 0), {
		LayoutOrder = 2,
		TextSize = 12,
		TextColor3 = C.faint,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local called = team.called == true
	local holder = Ui.make("Frame", { Name = "Ability", Size = UDim2.new(1, 0, 0, math.max(36, finger)), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
	CardKit.bigButton(holder, {
		name = "Ability",
		text = if called then "🚐 VAN CALLED (ONCE A MOVE)" else "📍 CALL VAN TO DOOR",
		kind = if called then "shut" else "warn",
		height = math.max(36, finger),
		textSize = 13,
		onClick = function()
			if not called then
				remote:FireServer("call")
			end
		end,
	})
end

local function closeList()
	listOpen = false
	listKey = ""
	if listFrame then
		listFrame:Destroy()
		listFrame = nil
	end
end

-- 7.0 review: what the list shows, as one cheap string (the state comes up to 4 times a second: an unchanged list is
-- not drawn again, so a tap on its buttons is never lost under a rebuild).
local function keyOf(s: any): string
	local parts: { string } = {}
	for _, item in s.items or {} do
		table.insert(parts, `{item.spot}:{item.state}:{item.condition}:{item.broken}:{item.by}:{item.mine}`)
	end
	local team = if type(s.team) == "table" then s.team else {}
	local counts = s.counts or {}
	local size = Ui.screenSize()
	return table.concat(parts, ";")
		.. `|{team.called}|{s.mine}|{counts.out}/{counts.total}|{counts.delivered}|{s.name}`
		.. `|{size.X}x{size.Y}|{Ui.screenScale()}|{Ui.touchLayout()}`
end

-- GIVE UP: the first tap asks (the button says so for GIVE_UP_SURE s), a second one within that gives the move up.
local function giveUpButton(holder: Instance, height: number)
	local sure = os.clock() - giveUpAt <= GIVE_UP_SURE
	local button = CardKit.bigButton(holder, {
		name = "GiveUp",
		text = if sure then "TAP AGAIN TO GIVE UP" else "GIVE UP THE MOVE",
		kind = if sure then "primary" else "shut",
		height = height,
		textSize = 14,
		onClick = function()
			if os.clock() - giveUpAt <= GIVE_UP_SURE then
				giveUpAt = 0
				remote:FireServer("giveup")
				return
			end
			giveUpAt = os.clock()
			local mine = giveUpAt
			local made: any = holder:FindFirstChild("GiveUp")
			if made then
				made.Text = "TAP AGAIN TO GIVE UP"
				CardKit.paint(made, "primary")
			end
			task.delay(GIVE_UP_SURE, function()
				local still: any = holder:FindFirstChild("GiveUp")
				if giveUpAt == mine and still then
					still.Text = "GIVE UP THE MOVE"
					CardKit.paint(still, "shut")
				end
			end)
		end,
	})
	return button
end

local function drawList()
	local root = screen()
	local s = state
	if not root or type(s) ~= "table" then
		closeList()
		return
	end
	local scroll = listFrame and listFrame:FindFirstChild("Rows", true)
	local keep = if scroll then scroll.CanvasPosition else Vector2.zero
	if listFrame then
		listFrame:Destroy()
	end
	listKey = keyOf(s)
	local area, scale, sheet = listBox()
	local width, height = (area.x1 - area.x0) / scale, (area.y1 - area.y0) / scale
	local holder: any = root
	if sheet then
		-- a touch screen: a sheet in front of everything (the touch buttons too); a tap beside it closes it
		local shade = Ui.make("TextButton", {
			Name = "MoveListShade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Selectable = false,
			ZIndex = 10,
		}, root)
		shade.Activated:Connect(function()
			closeList()
		end)
		holder = shade
	end
	local frame = Ui.make("Frame", {
		Name = "MoveList",
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromOffset(area.x0, area.y0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = if sheet then 11 else 1,
	}, holder)
	Ui.make("UIScale", { Name = "Scale", Scale = scale }, frame)
	Ui.corner(frame, 8)
	Ui.make("UIStroke", { Color = K.rule, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	listFrame = if sheet then holder else frame
	text(frame, `{s.icon or "🏠"} {string.upper(s.name or "")} · THINGS`, UDim2.new(1, -60, 0, 22), { Position = UDim2.fromOffset(12, 10), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = C.title })
	local counts = s.counts or {}
	text(frame, `★ must-haves first · {counts.out or 0} of {counts.total or 0} in the van`, UDim2.new(1, -60, 0, 16), { Position = UDim2.fromOffset(12, 32), TextSize = 12, TextColor3 = C.faint })
	Ui.closeButton(frame, function()
		closeList()
	end)
	-- (a computer: GIVE UP under the rows; a touch sheet: at the end of what scrolls; LEAVE THE RUN for the party but
	-- the host)
	local leaving = s.mine ~= true
	local footer = if (s.mine == true or leaving) and not sheet then 52 else 0
	local rows = Ui.make("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -16, 1, -(58 + footer)),
		Position = UDim2.fromOffset(8, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, frame)
	Ui.list(rows, true, 6)
	-- (7.0 review: a touch sheet's buttons a finger's height after its scale: Ui.MinTouch screen px)
	local finger = if sheet then math.ceil(MoveLayout.MIN_TOUCH / scale) else 0
	vanCard(rows, s, finger) -- THE VAN first
	local list = s.items or {}
	-- ★ first, then what is still in the house, then the rest
	local ordered = table.clone(list)
	local rank: { [string]: number } = { carried = 0, ground = 1, home = 2, truck = 3, delivered = 4, lost = 5 }
	table.sort(ordered, function(a: any, b: any): boolean
		if (a.star == true) ~= (b.star == true) then
			return a.star == true
		end
		local ra, rb = rank[a.state] or 4, rank[b.state] or 4
		if ra ~= rb then
			return ra < rb
		end
		return (tonumber(a.spot) or 0) < (tonumber(b.spot) or 0)
	end)
	for index, item in ordered do
		itemRow(rows, item, index)
	end
	rows.CanvasPosition = keep
	if s.mine == true then
		if sheet then
			do -- FINISH a finger's size on a phone (asked twice)
				local row = Ui.make("Frame", { Name = "FinishRow", Size = UDim2.new(1, 0, 0, finger), BackgroundTransparency = 1, LayoutOrder = #ordered + 9 }, rows)
				CardKit.bigButton(row, {
					name = "FinishMove",
					text = "✓ FINISH THE MOVE",
					kind = "good",
					height = finger,
					textSize = 14,
					onClick = function()
						if os.clock() - finishAt <= GIVE_UP_SURE then
							finishAt = 0
							remote:FireServer("finish")
							return
						end
						finishAt = os.clock()
						local made: any = row:FindFirstChild("FinishMove")
						if made then
							made.Text = "TAP AGAIN TO FINISH"
						end
					end,
				})
			end
			local foot = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, finger), BackgroundTransparency = 1, LayoutOrder = #ordered + 10 }, rows)
			giveUpButton(foot, finger)
		else
			local foot = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 1, -46), BackgroundTransparency = 1 }, frame)
			giveUpButton(foot, 40)
		end
	elseif leaving then -- out of the run alone (asked twice)
		local foot = if sheet
			then Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, finger), BackgroundTransparency = 1, LayoutOrder = #ordered + 10 }, rows)
			else Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 1, -46), BackgroundTransparency = 1 }, frame)
		CardKit.bigButton(foot, {
			name = "LeaveRun",
			text = "LEAVE THE RUN",
			kind = "shut",
			height = if sheet then finger else 40,
			textSize = 14,
			onClick = function()
				if os.clock() - giveUpAt <= GIVE_UP_SURE then
					giveUpAt = 0
					Net.get("Runs"):FireServer({ kind = "leave" })
					return
				end
				giveUpAt = os.clock()
				local made: any = foot:FindFirstChild("LeaveRun")
				if made then
					made.Text = "TAP AGAIN TO LEAVE"
					CardKit.paint(made, "primary")
				end
			end,
		})
	end
end

-- Every second while the list is open: a new list only when what it shows changed.
local function tickList()
	local s = state
	if listOpen and type(s) == "table" and keyOf(s) ~= listKey then
		drawList()
	end
end

toggleList = function()
	if listOpen then
		closeList()
	elseif type(state) == "table" then
		listOpen = true
		drawList()
	end
end

-- ── The state ──────────────────────────────────────────────────────────────

local function setState(view: any)
	state = if type(view) == "table" then view else nil
	refreshPanel()
	if listOpen then
		if state == nil then
			closeList()
		elseif keyOf(state) ~= listKey then
			drawList() -- (7.0 review: only when what it shows changed)
		end
	end
end

-- 7.0 review: the screen changed size (a window resized, a phone turned): the panel's scale and the list.
local function rescale()
	local S = Ui.screenScale()
	local scaler = refs.panelScale
	if scaler and math.abs(scaler.Scale - S) > 0.001 then
		scaler.Scale = S
	end
	if listOpen then
		drawList()
	end
end

function MovingHud.isOpen(): boolean
	return listOpen
end

-- 7.0 review: ESC (Main's Hud.onCloseWindows) closes the list.
function MovingHud.closeAll()
	closeList()
end

-- 7.0 review: the move's panel (a top-centre block, client/TopBlocks.luau "MovePanel").
function MovingHud.panel(): GuiObject?
	return refs.panel
end

function MovingHud.active(): boolean
	return state ~= nil
end

function MovingHud.start()
	local root = screen()
	if root then
		buildPanel(root)
	end
	watchPrompts()
	remote.OnClientEvent:Connect(function(kind: any, a: any, b: any, c: any)
		if kind == "state" then
			setState(a)
		elseif kind == "fade" then
			local seconds = if type(b) == "number" then math.clamp(b, 0, 2) else nil
			if a == "out" then
				Fade.out(seconds)
			else
				Fade.into(seconds, Fade.arrival(c)) -- (8.3 a door's trip: dark until you are there, client/Fade.luau)
			end
		end
	end)
	-- O: the list (7.0 review: not Tab, Roblox's player list; a key something else took is left alone)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == LIST_KEY and state ~= nil then
			toggleList()
		end
	end)
	-- 7.0 review: the panel and the list follow the screen's size
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				pcall(rescale)
			end)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		pcall(rescale)
	end)
	-- the clock once a second; the panel's words with it; the list drawn again when what it shows changed
	task.spawn(function()
		while true do
			task.wait(1)
			if state ~= nil then
				pcall(refreshPanel)
				pcall(tickList)
			end
		end
	end)
	remote:FireServer("state")
end

return MovingHud
