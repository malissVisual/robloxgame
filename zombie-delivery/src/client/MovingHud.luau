--!strict
-- 7.0 prototype, MOVES on the client (server/Moving.luau decides everything; shared/MovingRules.luau has the rules):
--   * the contract card (the Moving remote's "contract": the depot's board or the admin panel): the house and its
--     client, the ★ must-haves, the pay big in green, the clock and the horde, the truck lent; START (the server checks
--     it again) or why it can't start;
--   * the move's panel at the top in the middle while a move runs ("state"): the house, the clock (amber with the
--     horde, red in the last minute), the checklist (things out x/y, ★ x/3, broken), the truck's room as a bar and what
--     to do next; a tap on it (or O) opens the list;
--   * the list (O): every thing with its picture, ★, how it is carried (✋ one hand, 🙌 both, 👥 two), fragile, where
--     it is (in the house, carried by …, on the ground, in the truck) and its condition; the owner's GIVE UP (twice);
--   * the result card ("result"): delivered / left / broken, the stars 1 … 5, the pay's lines, your share and XP;
--   * the fade at a door ("fade": client/Fade.luau);
--   * the GPS: the house, or the Wall (the depot's drop-off) while you drive with a load (8.0 SANDBOX: none: the guide's
--     chevron and path, client/SandboxGuide.luau, point the way; one arrow, not two);
--   * the move's prompts only for its crew (the tag MovePrompt: MoveOwner = the move's owner, shown when your player
--     attribute MoveWith is theirs; MoveOnly = for that player alone; MoveSkip = not for that player), hidden by
--     their reach like client/CargoPrompts.luau.
-- 7.0 review: after 0:00 (the state's graceEndsAt) the panel counts down "TIME'S UP · REACH THE WALL · m:ss" in red.
-- Where it all sits is client/MoveLayout.luau's (pure). The panel is a top-centre block (client/
-- TopBlocks.luau: the chips, the banners, the location caption, the helper's strip and the quick chat's lines keep clear
-- of it) and follows the screen's size. The list is drawn again only when what it shows changed (a cheap key; the
-- role's countdown ticks in place); on a computer it sits at the right under the panel and under Roblox's player list,
-- on a touch screen it is a sheet over the whole height (its GIVE UP at the end of what scrolls). The key is O (Tab is
-- Roblox's player list), a key another thing took is left alone. ESC closes the cards and the list
-- (MovingHud.closeAll, Main's Hud.onCloseWindows); the move's end clears only the GPS it set.
--   MovingHud.start(), isOpen(), active(), closeAll(), panel()
-- 7.0 planning (shared/MoveRoles.luau; the lobby is client/MoveLobbyUi.luau): the panel's last line is your role and
-- what only it does (the three roles: the front door is never locked, the house lit from the start); the list (O)
-- starts with YOUR ROLE: its ability (the Driver's CALL TRUCK TO DOOR, the Guard's BARRICADE; the Moving remote's
-- "call" / "barricade") and SWITCH to a free role (the remote's "role", every Config.MoveRoles.Switch s). The prompts:
-- "Enter house" is each move's own, a prompt for one role (MoveQuick: the
-- truck's Load / Unload for the Driver) holds no time for it; a Guard sees the zombies through walls
-- (client/EnemyOutline.luau setXray). The contract card's START opens the planning.
-- (the list's YOUR ROLE comes first; its countdown "SWITCH ROLE IN n S" is kept up to date every second)
-- 8.8 (the owner: "I don't want roles in the game. Everyone is simply the same."; MoveRoles.on: the city's only, never
-- the sandbox): without roles no role anywhere: no role line on the panel (its last line is FINISH's alone), the list
-- starts with THE VAN: CALL VAN TO DOOR for anybody of the crew (the remote's "call", once a move: whoever is first),
-- no SWITCH, no barricade; nobody sees through walls; the truck's prompts hold no time for anybody (the server's: no
-- MoveQuick).
-- 7.x farm move: the contract card lists the board's contracts (card.contracts: a chip each, the open ones ask the
-- server for their card: the Moving remote's ("card", id); a locked one shows why), its CHAPTERS from the same list
-- (MoveStoryUi.chapters' open map: chapter 1 ▶ PLAY once the prologue is done).
-- 7.x van moves (the move goes with your own van, several trips to the Wall): the panel's line is "TRIP n · delivered
-- x/y · ★", the bar the van's room; the owner's FINISH on the panel (and in the list's sheet on a phone), asked twice
-- (the remote's "finish": paid for every trip); the van lost: when CAR brings it back.
-- 8.0 SANDBOX (server/Moving.luau's SB; design/sandbox/KONTRAKT.md), from the server's own fields (none: the city's as
-- before): the state's `drop` ("your warehouse": the drop-off's words in the panel, the list, the GPS, a delivered
-- thing is HOME); the card's `story` false (no intro, no CHAPTERS) and `note` (no pay per piece), a horde at 0:00 none;
-- the result's `home` (what came home: the pieces, their value; no pay lines).
-- 9.7 runs (the state's `run`: server/Moving.luau's SB.runView; client/RunUi.luau has the pad panel and the results
-- card): no trips and no driving: the panel's line is "IN THE TRUCK n/total · ★ · the difficulty", its next step says to
-- load the truck and FINISH at it (or beat the clock); the host's FINISH is always there, the others' is VOTE FINISH
-- (the Runs remote's "vote"), the list's footer LEAVE THE RUN for them (the Runs remote's "leave", asked twice); a
-- run's own results card is RunUi's (the Moving remote's "result" carries none for a run). 10.5 rounds (its `run.round`):
-- the line is "YOURS n · $ · the place · the difficulty" (what you loaded into your own van), the next step says to load
-- it into YOUR van, no FINISH and no vote, the list's footer LEAVE THE ROUND for everybody.
-- 8.3 keys (the sandbox; shared/SandboxPad.luau, client/PadGlyph.luau): the panel's words name the keys of the device
-- used now, a gamepad used last first: what to do next ("Pick up the things (E)", "(X)" with a gamepad, no key on a
-- touch screen: the prompt is tapped) and the list's hint ("LIST [O]", "TAP: LIST" on a touch screen, none with a
-- gamepad: no button opens it). Every refresh, so they follow a gamepad picked up or put down. The city's as before.
-- Presentation only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Map = require(Shared.Map)
local Config = require(Shared.Config)
local MoveRoles = require(Shared.MoveRoles) -- 7.0 planning
local SandboxPad = require(Shared.SandboxPad) -- 8.3 keys
local Ui = require(script.Parent.Ui)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 keys: the device used now
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Fade = require(script.Parent.Fade)
local MapView = require(script.Parent.MapView)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review: where the panel and the list sit
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review: the panel holds the top's middle
local EnemyOutline = require(script.Parent.EnemyOutline) -- 7.0 planning: the Guard's sight
local MoveStoryUi = require(script.Parent.MoveStoryUi) -- MoveStory hook (7.0 story): the intro, the briefing, CHAPTERS, the thanks

local MovingHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color
local TAG = "MovePrompt"
local ORANGE = Color3.fromRGB(240, 132, 44)
local PANEL_W = MoveLayout.PANEL_W
local PANEL_H = MoveLayout.PANEL_H -- (7.0 planning: + the role's line; 8.8 without roles: FINISH's row alone)
local CARD_W = 440
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
local finishAt = 0 -- 7.x van moves: the first tap of FINISH (os.clock)
local cardFrame: any = nil -- the contract card or the result (one at a time)
local gpsAt: Vector3? = nil -- the waypoint set here (cleared here)
local hidden: { [ProximityPrompt]: number } = {} -- the move prompts hidden for you, with their reach
local holds: { [ProximityPrompt]: number } = {} -- 7.0 planning: a MoveQuick prompt's own hold (yours may be none)

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

local function sound(name: string)
	pcall(function()
		(require(script.Parent.Sounds) :: any).play(name, 0.7)
	end)
end

local function clock(seconds: number): string
	return Ui.clock(math.max(0, seconds))
end

local CLASS_TEXT: { [string]: string } = { hand = "✋ one hand", both = "🙌 both hands", pair = "👥 two people" }
local STATE_TEXT: { [string]: string } = { home = "IN THE HOUSE", carried = "CARRIED", ground = "ON THE GROUND", truck = "IN THE VAN", delivered = "AT THE WALL", lost = "LOST" }

-- The move's drop-off in a sentence: the state's `drop` (8.0 SANDBOX: "your warehouse"), else "the Wall".
local function wallOf(s: any): string
	return if type(s) == "table" and type(s.drop) == "string" then s.drop else "the Wall"
end

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

-- 7.0 planning: a prompt for one role (MoveQuick = its id) holds no time for that role (the Driver's Load / Unload).
local function quick(prompt: ProximityPrompt)
	local role = prompt:GetAttribute("MoveQuick")
	if type(role) ~= "string" then
		return
	end
	local base = holds[prompt]
	if not base then
		base = prompt.HoldDuration
		holds[prompt] = base
	end
	local hold = if player:GetAttribute("MoveRole") == role then 0 else base
	if prompt.HoldDuration ~= hold then
		prompt.HoldDuration = hold
	end
end

local function apply(prompt: ProximityPrompt)
	quick(prompt)
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
			holds[instance] = nil
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
	player:GetAttributeChangedSignal("MoveRole"):Connect(applyAll)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, TAG) and not shows(prompt) then
			hidden[prompt] = nil
			apply(prompt)
		end
	end)
end

-- ── The GPS ────────────────────────────────────────────────────────────────

local function setGps(at: Vector3?, name: string?, icon: string?)
	if at == nil then
		local mine = gpsAt
		if mine then
			gpsAt = nil
			-- (7.0 review: a waypoint the player set since is theirs: it stays)
			local now = MapView.waypointAt()
			if now and (now - mine).Magnitude < 1 then
				MapView.setWaypoint(nil)
				pcall(function()
					MapView.onWaypoint(nil)
				end)
			end
		end
		return
	end
	local current = gpsAt
	if current and (current - at).Magnitude < 1 then
		return
	end
	gpsAt = at
	MapView.setWaypoint(at)
	pcall(function()
		MapView.onWaypoint({ id = "move", name = name or "Move", icon = icon or "🏠", x = at.X, z = at.Z, kind = "shop", description = "" } :: any)
	end)
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- The house, or the Wall while you drive with a load (or the horde is on and something is in). 8.0 SANDBOX: never (no
-- waypoint, no GPS ring, beacon or toasts: client/SandboxGuide.luau's chevron and path point at the same spot).
local function updateGps()
	local s = state
	if type(s) ~= "table" or Config.Sandbox.On then
		setGps(nil)
		return
	end
	local counts = s.counts or {}
	local out = tonumber(counts.out) or 0
	if out > 0 and (seated() or s.horde == true or s.graceEndsAt ~= nil) then -- (7.0 review: late: the Wall)
		if type(s.drop) == "string" then -- (8.0 SANDBOX: your warehouse)
			setGps(Vector3.new(s.dropOff.x, Map.RoadTop, s.dropOff.z), "Your warehouse", "🏠")
		else
			setGps(Vector3.new(s.dropOff.x, Map.RoadTop, s.dropOff.z), "The Wall (drop-off)", "🧱")
		end
	else
		setGps(Vector3.new(s.house.x, Map.RoadTop, s.house.z), s.name, s.icon)
	end
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
	refs.role = text(panel, "", UDim2.new(1, -24, 0, 16), { Position = UDim2.fromOffset(12, 96), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary }) -- 7.0 planning
	-- 7.x van moves: the owner's FINISH (asked twice), once something reached the Wall
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
					Net.get("Runs"):FireServer({ kind = "vote" }) -- 9.7 runs: a party member's vote to finish
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

-- 8.3 keys: a prompt's key at the end of the words: the sandbox's for the device used now (shared/SandboxPad.luau
-- withKey: "(E)", "(X)", none on a touch screen), the city's E.
local function keyed(text: string): string
	return if Config.Sandbox.On then SandboxPad.withKey(text, "use", PadGlyph.device()) else `{text} (E)`
end

-- 8.3 keys: the list's hint (the sandbox's: its key, a touch screen's tap, none with a gamepad).
local function listHint(): string
	local device = PadGlyph.device()
	local key = SandboxPad.keyWord("list", device)
	return if key then `LIST [{key}]` elseif device == "touch" then "TAP: LIST" else ""
end

-- What to do now, from the state.
local function nextStep(s: any): string
	local counts = s.counts or {}
	local out, total = tonumber(counts.out) or 0, tonumber(counts.total) or 0
	local carried = tonumber(counts.carried) or 0
	local delivered = tonumber(counts.delivered) or 0
	if type(s.run) == "table" and s.run.round == true then -- 10.5 rounds: your own van, no FINISH
		if s.inside == true then
			return if carried > 0 then "Carry it out to YOUR van: walk out through a door" else `{keyed("Pick up the loot")} · the best first`
		elseif carried > 0 then
			return keyed("Load it into YOUR van (its back)")
		end
		return "Grab more before the clock runs out: the most value wins"
	elseif type(s.run) == "table" then -- 9.7 runs: the truck at the door, no driving
		if s.inside == true then
			return if carried > 0 then "Carry it out: walk out through a door" else `{keyed("Pick up the loot")} · ★ first`
		elseif carried > 0 then
			return if s.backOpen == true then keyed("Load it into the truck") else `{keyed("Open the truck's back")}, then Load`
		elseif out > 0 and out >= total then
			return "Everything is in the truck: FINISH at the truck"
		end
		return if out > 0 then "Load more, or FINISH at the truck before the clock runs out" else `Walk in through {s.name}'s door`
	end
	if s.truck ~= true then -- (7.x van moves: the van lost)
		local wait = math.ceil((tonumber(s.vanAgainAt) or 0) - workspace:GetServerTimeNow())
		return if wait > 0 then `💥 The van is lost · CAR brings it back in {wait} s` else "💥 The van is lost · CAR brings it back now"
	end
	if s.horde == true then
		return if out > 0 then `🧟 THE HORDE! Drive the van to {wallOf(s)} NOW` else "🧟 THE HORDE! Load something and get out"
	end
	if s.inside == true then
		return if carried > 0 then "Carry it out: walk out through a door" else `{keyed("Pick up the things")} · ★ first` -- (8.1 walk-in doors)
	end
	if carried > 0 then
		return if s.backOpen == true then keyed("Load it at the van's back") else `{keyed("Open the van's back")}, then Load`
	end
	if out > 0 and out + delivered >= total and total > 0 then
		return if s.drop then `Everything is in: drive to {wallOf(s)}` else "Everything is in: drive to the Wall at the depot"
	end
	if seated() then
		local gps = if Config.Sandbox.On then "" else " (GPS)" -- (8.0 SANDBOX: no GPS, the guide's arrow)
		return if out > 0 then `Drive to {wallOf(s)}{gps}, or back for more` elseif delivered > 0 then `Back to {s.name} for more, or FINISH` else `Drive to {s.name}{gps}`
	end
	return `Walk in through {s.name}'s door` -- (8.1 walk-in doors: no E)
end

-- 7.0 planning: your role and what only it does (the panel's last line; 8.8 without roles: none, the line is empty).
local function roleLine(s: any): string
	if not MoveRoles.on() then
		return ""
	end
	local team = if type(s.team) == "table" then s.team else {}
	local def = MoveRoles.get(team.role)
	if not def then
		return ""
	end
	local hint = def.hint
	if def.id == "driver" and team.called == true then
		hint = "No wait at the truck's back · the truck was called"
	elseif def.id == "guard" then
		hint = `{hint} · 🪵 {tonumber(team.barricades) or 0} left`
	end
	return `{def.icon} {string.upper(def.name)} · {hint}`
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
	-- 7.0 review: after 0:00 the truck has a grace to reach the Wall (the state's graceEndsAt): its countdown, red
	local grace = tonumber(s.graceEndsAt)
	local late = grace ~= nil and left <= 0
	refs.timer.Text = if late and grace then `⏱ {clock(grace - nowAt)}` else `⏱ {clock(left)}`
	refs.timer.TextColor3 = if left <= 60 then K.red elseif s.horde == true then K.warn else K.text
	local broken = tonumber(counts.broken) or 0
	local delivered = tonumber(counts.delivered) or 0
	-- 7.x van moves: the trip under way and what reached the Wall over every trip (9.7 runs: what is in the truck)
	local run = if type(s.run) == "table" then s.run else nil
	refs.check.Text = if run and run.round == true -- (10.5 rounds: what you loaded into your own van)
		then `YOURS {tonumber(run.count) or 0} · {Ui.money(tonumber(run.value) or 0)} · {string.upper(tostring(s.name or ""))} · {string.upper(tostring(run.name or ""))}`
		elseif run
		then `IN THE TRUCK {counts.out or 0}/{counts.total or 0} · ★ {counts.stars or 0} · {string.upper(tostring(run.name or ""))}{if broken > 0 then ` · 💥 {broken}` else ""}`
		else `TRIP {(tonumber(s.trips) or 0) + 1} · delivered {delivered}/{counts.total or 0} · ★ {counts.starsDelivered or 0}/{counts.stars or 0}{if broken > 0 then ` · 💥 {broken}` else ""}{if s.horde ~= true and hordeIn > 0 then ` · 🧟 {clock(hordeIn)}` else ""}`
	local fill = math.clamp(tonumber(s.fill) or 0, 0, 1)
	refs.truckLabel.Text = `🚐 VAN {math.floor(fill * 100 + 0.5)}%`
	refs.fill.Size = UDim2.fromScale(fill, 1)
	refs.fill.BackgroundColor3 = if fill > 0.9 then K.red elseif fill > 0.7 then K.warn else ORANGE
	refs.next.Text = if late and grace then `⏱ TIME'S UP · REACH {string.upper(wallOf(s))} · {clock(grace - nowAt)}` else nextStep(s)
	refs.next.TextColor3 = if s.horde == true or late then K.red else K.text
	refs.role.Text = roleLine(s) -- 7.0 planning
	if Config.Sandbox.On then
		refs.hint.Text = listHint() -- 8.3 keys
	end
	local finish = refs.finish -- 7.x van moves: the owner's FINISH once something reached the Wall (asked twice)
	if finish then
		local can = (s.mine == true and delivered > 0) or (run ~= nil and run.round ~= true) -- (9.7 runs: the host's FINISH, the others' vote; 10.5 rounds: none)
		local sure = os.clock() - finishAt <= GIVE_UP_SURE
		finish.Visible = can
		finish.Text = if sure then (if run and run.mine ~= true then "TAP TO VOTE" else "TAP TO FINISH") elseif run and run.mine ~= true then "✓ VOTE FINISH" else "✓ FINISH"
		refs.role.Size = UDim2.new(1, if can then -140 else -24, 0, 16)
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

-- 7.0 planning: YOUR ROLE at the list's top: the role, its ability's button (the Driver's call, the Guard's barricade)
-- and SWITCH to a free role (a chip each; a while after a switch: when, counted down in place: refs.switchWait).
-- 8.8 without roles: THE VAN in its place: the call to the door, anybody's (once a move), and no SWITCH.
local function roleCard(parent: Instance, s: any, finger: number)
	local team = if type(s.team) == "table" then s.team else {}
	local roles = MoveRoles.on()
	local def = if roles then MoveRoles.get(team.role) else nil
	if roles and not def then
		return
	end
	local card = Ui.make("Frame", { Name = if def then "Role" else "Van", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = 0 }, parent)
	Ui.corner(card, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, card)
	Ui.list(card, true, 6)
	local color = if def then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) else ORANGE
	text(card, if def then `YOUR ROLE · {def.icon} {string.upper(def.name)}` else "🚐 THE VAN", UDim2.new(1, 0, 0, 18), { LayoutOrder = 1, Font = Theme.HeadingFont, TextSize = 14, TextColor3 = color })
	text(card, if def then def.hint else "Anybody of the crew calls it to the house's door, once a move.", UDim2.new(1, 0, 0, 0), {
		LayoutOrder = 2,
		TextSize = 12,
		TextColor3 = C.faint,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local ability: { text: string, action: string, on: boolean }? = nil
	if not def or def.id == "driver" then -- (8.8 without roles: the call, anybody's)
		local called = team.called == true
		ability = {
			text = if def then (if called then "🚚 TRUCK CALLED (ONCE A MOVE)" else "📍 CALL TRUCK TO DOOR") elseif called then "🚐 VAN CALLED (ONCE A MOVE)" else "📍 CALL VAN TO DOOR",
			action = "call",
			on = not called,
		}
	elseif def.id == "guard" then
		local left = tonumber(team.barricades) or 0
		ability = { text = if left > 0 then `🪵 PUT UP A BARRICADE · {left} LEFT` else "🪵 NO BARRICADES LEFT", action = "barricade", on = left > 0 }
	end
	if ability then
		local holder = Ui.make("Frame", { Name = "Ability", Size = UDim2.new(1, 0, 0, math.max(36, finger)), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
		local act = ability
		CardKit.bigButton(holder, {
			name = "Ability",
			text = act.text,
			kind = if act.on then "warn" else "shut",
			height = math.max(36, finger),
			textSize = 13,
			onClick = function()
				if act.on then
					remote:FireServer(act.action)
				end
			end,
		})
	end
	local wait = math.ceil((tonumber(team.switchAt) or 0) - workspace:GetServerTimeNow())
	local free = if type(team.free) == "table" and roles then team.free else {}
	if wait > 0 and roles then
		refs.switchWait = text(card, `SWITCH ROLE IN {wait} S`, UDim2.new(1, 0, 0, 16), { Name = "SwitchWait", LayoutOrder = 4, Font = Theme.HeadingFont, TextSize = 11, TextColor3 = C.faint })
	elseif #free > 0 then
		text(card, "SWITCH ROLE", UDim2.new(1, 0, 0, 14), { LayoutOrder = 4, Font = Theme.HeadingFont, TextSize = 11, TextColor3 = C.faint })
		local strip = Ui.make("Frame", { Name = "Switch", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5 }, card)
		Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(96, math.max(26, finger)), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
		for index, id in free do
			local other = MoveRoles.get(id)
			if other then
				CardKit.chip(strip, {
					name = `Switch_{id}`,
					text = `{other.icon} {string.upper(other.name)}`,
					order = index,
					stroke = K.rule,
					onClick = function()
						remote:FireServer("role", id)
					end,
				})
			end
		end
	end
end

local function closeList()
	listOpen = false
	listKey = ""
	refs.switchWait = nil
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
	local free = if type(team.free) == "table" then table.concat(team.free, ",") else ""
	local waiting = (tonumber(team.switchAt) or 0) > workspace:GetServerTimeNow()
	local counts = s.counts or {}
	local size = Ui.screenSize()
	return table.concat(parts, ";")
		.. `|{team.role}|{team.called}|{team.barricades}|{free}|{waiting}|{s.mine}|{counts.out}/{counts.total}|{counts.delivered}|{s.name}`
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
	refs.switchWait = nil
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
	text(frame, `★ must-haves first · {counts.delivered or 0} of {counts.total or 0} {if s.drop then "home" else "at the Wall"} · {counts.out or 0} in the van`, UDim2.new(1, -60, 0, 16), { Position = UDim2.fromOffset(12, 32), TextSize = 12, TextColor3 = C.faint })
	Ui.closeButton(frame, function()
		closeList()
	end)
	-- (a computer: GIVE UP under the rows; a touch sheet: at the end of what scrolls; 9.7 runs: LEAVE THE RUN for the
	-- party but the host)
	local leaving = type(s.run) == "table" and s.mine ~= true
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
	roleCard(rows, s, finger) -- 7.0 planning: YOUR ROLE first
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
			if (tonumber(counts.delivered) or 0) > 0 or type(s.run) == "table" then -- 7.x van moves: FINISH a finger's size on a phone (asked twice)
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
	elseif leaving then -- 9.7 runs: out of the run alone (asked twice)
		local foot = if sheet
			then Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, finger), BackgroundTransparency = 1, LayoutOrder = #ordered + 10 }, rows)
			else Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 1, -46), BackgroundTransparency = 1 }, frame)
		CardKit.bigButton(foot, {
			name = "LeaveRun",
			text = if s.run.round == true then "LEAVE THE ROUND" else "LEAVE THE RUN", -- (10.5 rounds)
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

-- Every second while the list is open: the role's countdown in place (a new list only when what it shows changed).
local function tickList()
	local s = state
	if not listOpen or type(s) ~= "table" then
		return
	end
	if keyOf(s) ~= listKey then
		drawList()
		return
	end
	local label = refs.switchWait
	local team = if type(s.team) == "table" then s.team else {}
	if label and label.Parent then
		local wait = math.ceil((tonumber(team.switchAt) or 0) - workspace:GetServerTimeNow())
		label.Text = `SWITCH ROLE IN {math.max(1, wait)} S`
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

-- ── The cards: the contract, the result ────────────────────────────────────

local function closeCard()
	if cardFrame then
		cardFrame:Destroy()
		cardFrame = nil
	end
end

-- A dimmed backdrop and a card in the middle; returns the card's body (a vertical list).
local function cardShell(name: string, accent: Color3): any
	closeCard()
	local root = screen()
	if not root then
		return nil
	end
	local backdrop = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
	}, root)
	cardFrame = backdrop
	local card = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 21,
	}, backdrop)
	scaled(card)
	Ui.corner(card, 12)
	Ui.make("UIStroke", { Color = accent, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16) }, card)
	-- the words in a list; the close button over its top right corner (not one of the list's rows)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 21 }, card)
	Ui.list(body, true, 8)
	local close = Ui.closeButton(card, closeCard)
	close.Position = UDim2.new(1, 10, 0, -8)
	close.ZIndex = 23
	return body
end

local function line(parent: Instance, value: string, order: number, props: { [string]: any }?): any
	local label = Ui.label(parent, value, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = K.secondary,
		TextWrapped = true,
		LayoutOrder = order,
		ZIndex = 22,
	})
	if props then
		for key, prop in props do
			label[key] = prop
		end
	end
	return label
end

local function chipRow(parent: Instance, order: number, chips: { string })
	local strip = Ui.make("Frame", { Name = "Chips", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 22 }, parent)
	local layout = Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(196, 26), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	local _ = layout
	for index, value in chips do
		local chip = CardKit.chip(strip, { name = `Chip{index}`, text = value, order = index, static = true, stroke = K.rule })
		chip.ZIndex = 22
		chip.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function showContract(card: any)
	if type(card) ~= "table" then
		return
	end
	-- MoveStory hook: the first board ever opens on Marge's intro (client/MoveStoryUi.luau), this card after it (8.0
	-- SANDBOX: no story)
	if card.story ~= false and MoveStoryUi.intro(function()
		showContract(card)
	end) then
		return
	end
	local body = cardShell("MoveContract", ORANGE)
	if not body then
		return
	end
	line(body, "DELIVEROS MOVING · CONTRACT", 1, { Font = Theme.HeadingFont, TextSize = 12, TextColor3 = ORANGE })
	-- 7.x farm move: the board's contracts (open ones ask for their card, a locked one says why)
	local list = if type(card.contracts) == "table" then card.contracts else {}
	local open: { [string]: boolean }? = nil
	if #list > 1 then
		open = {}
		local strip = Ui.make("Frame", { Name = "Contracts", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, body)
		Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(196, 30), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
		local why = line(body, "", 1, { Name = "ContractWhy", TextSize = 12, TextColor3 = C.faint, Visible = false })
		for index, entry in list do
			local id = tostring(entry.id)
			local isOpen = entry.open == true
			local mine = id == tostring(card.id);
			(open :: { [string]: boolean })[id] = isOpen
			local chip = CardKit.chip(strip, {
				name = `Contract_{id}`,
				text = `{if isOpen then tostring(entry.icon or "🏠") else "🔒"} {string.upper(tostring(entry.name))}`,
				order = index,
				stroke = if mine then ORANGE else K.rule,
				onClick = function()
					if mine then
						return
					elseif isOpen then
						remote:FireServer("card", id)
					else
						why.Text = tostring(entry.why or "🔒 Not open yet.")
						why.Visible = true
					end
				end,
			})
			chip.ZIndex = 22
		end
	end
	line(body, `{card.icon or "🏠"} {string.upper(tostring(card.name))}`, 2, { Font = Theme.HeadingFont, TextSize = 24, TextColor3 = C.title })
	line(body, `Client: {card.client} · {card.address}`, 3, { TextColor3 = K.text })
	line(body, tostring(card.blurb or ""), 4)
	local minutes = math.floor((tonumber(card.time) or 0) / 60)
	chipRow(body, 5, {
		`⏱ {minutes} MIN`,
		if (tonumber(card.hordeAt) or 0) > 0 then `🧟 HORDE AT {clock(tonumber(card.hordeAt) or 0)} LEFT` else "🧟 NO HORDE",
		`📦 {card.items or 0} THINGS`,
		`🚚 {string.upper(tostring(card.truck))} LENT`,
	})
	local stars = card.stars or {}
	line(body, if #stars > 0 then `★ MUST-HAVES: {table.concat(stars, " · ")}` else "★ MUST-HAVES: none", 6, { TextColor3 = C.gold, Font = Theme.HeadingFont, TextSize = 13 })
	line(body, `UP TO {Ui.money(tonumber(card.estimate) or 0)}`, 7, { Font = Theme.HeadingFont, TextSize = 28, TextColor3 = C.money })
	line(body, if type(card.note) == "string" then card.note else "Paid by what arrives and its condition; ★ things ×1.5, a time bonus, broken things cost you. Your crew (K) helps and shares the pay.", 8, { TextSize = 12, TextColor3 = C.faint })
	local busy = card.busy
	if type(busy) == "string" then
		line(body, busy, 9, { TextColor3 = K.red, Font = Theme.HeadingFont, TextSize = 13 })
	end
	local holder = Ui.make("Frame", { Name = "Start", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = 10, ZIndex = 22 }, body)
	local start = CardKit.bigButton(holder, {
		name = "StartMove",
		text = if type(busy) == "string" then "CAN'T START YET" else "▶ START · PLAN THE MOVE",
		kind = if type(busy) == "string" then "shut" else "primary",
		height = 48,
		z = 23,
		onClick = function()
			if type(busy) ~= "string" then
				closeCard()
				-- MoveStory hook: the chapter's briefing first (once a game), then START; its ✕ brings this card back
				-- (7.0 planning: START opens the planning lobby: client/MoveLobbyUi.luau)
				MoveStoryUi.briefing(card.id, function()
					remote:FireServer("start", card.id)
				end, function()
					showContract(card)
				end)
			end
		end,
	})
	Ui.gamepadFocus(start)
	-- MoveStory hook: the story road (CHAPTERS) under START (7.x farm move: open as the card's contracts say; a tap on
	-- another playable chapter asks for its contract's card)
	if card.story ~= false then
		MoveStoryUi.chapters(body, 11, card.id, open, function(id: string)
			remote:FireServer("card", id)
		end)
	end
	sound("notify")
end

local HEAD: { [string]: string } = { done = "MOVE COMPLETE", late = "TIME'S UP", cancelled = "MOVE CALLED OFF", failed = "MOVE LOST" }

local function showResult(r: any)
	if type(r) ~= "table" or r.run ~= nil then
		return -- (9.7 runs: client/RunUi.luau's results card)
	end
	closeList()
	local good = r.how == "done" or r.how == "late"
	local body = cardShell("MoveResult", if good then K.good else K.red)
	if not body then
		return
	end
	line(body, `{HEAD[r.how] or "MOVE OVER"} · {r.icon or "🏠"} {string.upper(tostring(r.name))}`, 1, { Font = Theme.HeadingFont, TextSize = 13, TextColor3 = if good then K.good else K.red })
	local stars = math.clamp(tonumber(r.stars) or 0, 0, 5)
	line(body, string.rep("★", stars) .. string.rep("☆", 5 - stars), 2, { Font = Theme.HeadingFont, TextSize = 34, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Center })
	line(body, tostring(r.howText or ""), 3, { TextColor3 = K.text, TextXAlignment = Enum.TextXAlignment.Center })
	chipRow(body, 4, {
		`📦 DELIVERED {r.delivered or 0}/{r.total or 0}`,
		`★ {r.starsOut or 0}/{r.starsTotal or 0}`,
		`🏠 LEFT BEHIND {r.left or 0}`,
		`💥 BROKEN {r.broken or 0}`,
	})
	local home = if type(r.home) == "table" then r.home else nil
	if home then -- 8.0 SANDBOX: no pay: what came home to your warehouse (also when called off: it is there)
		local trips = tonumber(r.trips) or 0
		line(body, `{tonumber(home.pieces) or 0} PIECES CAME HOME · WORTH {Ui.money(tonumber(home.value) or 0)}`, 5, { Font = Theme.HeadingFont, TextSize = 22, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Center })
		line(body, `In {trips} trip{if trips == 1 then "" else "s"} home. They wait in your warehouse: put them on show (they earn every minute) or sell them.`, 6, { TextSize = 12, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Center })
	elseif good then
		local parts = { `Things {Ui.money(tonumber(r.base) or 0)}`, `★ bonus {Ui.money(tonumber(r.starBonus) or 0)}`, `time bonus {Ui.money(tonumber(r.timeBonus) or 0)}` }
		local fine = tonumber(r.fine) or 0
		if fine > 0 then
			table.insert(parts, `broken −{Ui.money(fine)}`)
		end
		line(body, table.concat(parts, " · ") .. ` → {Ui.money(tonumber(r.pay) or 0)}`, 5, { TextSize = 13 })
		line(body, `YOUR SHARE {Ui.money(tonumber(r.money) or 0)} · +{r.xp or 0} XP`, 6, { Font = Theme.HeadingFont, TextSize = 24, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Center })
		local trips = tonumber(r.trips) or 0 -- 7.x van moves
		local crewText = if (tonumber(r.crew) or 1) > 1 then `Split with the crew at the van ({r.crew} of you).` else ""
		if trips > 0 or crewText ~= "" then
			line(body, `{if trips > 0 then `In {trips} trip{if trips == 1 then "" else "s"} to the Wall. ` else ""}{crewText}`, 7, { TextSize = 12, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Center })
		end
	end
	MoveStoryUi.thanks(body, 8, r, if type(state) == "table" then state.contract else nil) -- MoveStory hook: the client's thanks
	local holder = Ui.make("Frame", { Name = "Ok", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 9, ZIndex = 22 }, body)
	local ok = CardKit.bigButton(holder, { name = "Ok", text = "OK", kind = if good then "good" else "shut", height = 44, z = 23, onClick = closeCard })
	Ui.gamepadFocus(ok)
	sound(if good then "job_done" else "job_fail")
end

-- ── The state ──────────────────────────────────────────────────────────────

local function setState(view: any)
	state = if type(view) == "table" then view else nil
	-- 7.0 planning: a Guard sees the zombies through walls (8.8 without roles: nobody)
	local team = if state and type(state.team) == "table" and MoveRoles.on() then state.team else nil
	pcall(EnemyOutline.setXray, if team and team.role == "guard" then Config.MoveRoles.Guard.XRay else 0)
	refreshPanel()
	updateGps()
	if listOpen then
		if state == nil then
			closeList()
		elseif keyOf(state) ~= listKey then
			drawList() -- (7.0 review: only when what it shows changed)
		end
	end
end

-- 7.0 review: the screen changed size (a window resized, a phone turned): the panel's scale, the list and a card's.
local function rescale()
	local S = Ui.screenScale()
	local scaler = refs.panelScale
	if scaler and math.abs(scaler.Scale - S) > 0.001 then
		scaler.Scale = S
	end
	local card = cardFrame and cardFrame:FindFirstChild("Card")
	local cardScale = card and card:FindFirstChild("Scale")
	if cardScale then
		cardScale.Scale = S
	end
	if listOpen then
		drawList()
	end
end

function MovingHud.isOpen(): boolean
	return cardFrame ~= nil or listOpen or MoveStoryUi.isOpen() -- (MoveStory hook: a story card frees the mouse too)
end

-- 7.0 review: ESC (Main's Hud.onCloseWindows) closes the contract or result card and the list.
function MovingHud.closeAll()
	closeCard()
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
		elseif kind == "contract" then
			showContract(a)
		elseif kind == "result" then
			showResult(a)
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
	-- 7.0 review: the panel, the list and a card follow the screen's size
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
	-- the clock and the GPS once a second; the panel's words with them; the list's countdown in place
	task.spawn(function()
		while true do
			task.wait(1)
			if state ~= nil then
				pcall(refreshPanel)
				pcall(updateGps)
				pcall(tickList)
			end
		end
	end)
	remote:FireServer("state")
end

return MovingHud
