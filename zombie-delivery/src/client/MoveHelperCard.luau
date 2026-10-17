--!strict
-- 8.3 Danny's card and his list's clicks (the owner: "… you go into the house, click on something, and that assigns it
-- to him, and the rest you carry yourself"). server/MoveHelper.luau decides everything; his words are
-- shared/MoveHelperBrain.luau's. 10.1: no hire any more (free: every move's helper is yours, Danny or the crew's pick:
-- his name the attribute MoveHelperName's), and the card's 👥 CREW opens the CREW window (client/CrewUi.luau: the Crew
-- remote's { kind = "open" }, the server decides):
--   * Opening the card: on a computer a click on his body (the crosshair's middle while the camera holds the mouse, else
--     the mouse's point), on a touch screen a tap on him (UserInputService.TouchTapInWorld; Config.MoveHelper.TapSlop
--     studs beside his body count, ClickReach studs at most), on a gamepad the prompt on him ("Talk to Danny": a
--     ProximityPrompt this client makes on his root, shown only while a gamepad is in use, on shared/SandboxPad.luau's
--     "danny" button: L1); the button of his status line (client/MoveHelperHud.luau, wired by useCard). Never while your
--     hands are full, you wait for him or a grip check shows (a left click is the check's press then:
--     client/CarryGripUi.luau active). His body is found by your player attribute MoveHelperId (his body's
--     MoveHelper): only his move's crew has it.
--   * The card: "🧑‍🔧 DANNY", his status (MoveHelperBrain.status), 👥 CREW (10.1), ✕; "2 pieces to carry", how to give
--     him pieces, and CLEAR QUEUE (("helper", "clear")). A tap on its button sends once and the card closes. A
--     gamepad's selection starts on ✕ (8.3 review: an A pressed by habit never clears his list) and stays inside the
--     card (a SelectionGroup);
--     as it closes it is let go when it sits in the card or in no window (the HUD's groups, the chips, nothing shown:
--     client/PadGlyph.luau's chips need no selection).
--   * His list: a click on a piece of your move (a tap on a touch screen) sends ("helper", "assign", its model):
--     onto his list, or off it again (the server checks and says so in a toast; its marker over the piece is the
--     server's). On a gamepad the prompt "Give to Danny" ("Take back from Danny" for a piece of his list) on the nearest
--     piece of your move within reach, on SandboxPad's "dannygive" button (R1: free in the sandbox, no throw or holster
--     there). 8.5 ORDERS MODE (the owner: "I'll hold a paper in my hand, like a notepad … and I click on what he should
--     carry"): only while your clipboard is out (your character's ClipboardHeld: server/Clipboard.luau; client/
--     DannyOrders.luau takes it out and shows the mode) does a click, a tap or R1 give him a piece: without it a click
--     on a piece does nothing for him (no stray orders) and the gamepad's prompt is off; with it a click never opens his
--     card (nothing else fires), only the pieces. The card's button row is 📋 CLIPBOARD (out; "📋 PUT AWAY" while
--     it is out: the Clipboard remote, the card closes) beside CLEAR QUEUE, its words how (ClipboardRules.cardHint).
--   * Where (MoveHelperCard.layout, pure): beside his head as it was on the screen when it opened (right of him, else
--     left, over, under), clear of the HUD's groups (client/Hud.luau's), the sandbox's chips (client/SandboxHud.luau's
--     money block, client/SandboxTasksUi.luau's TASKS chip), the move's top blocks (its panel, Danny's status line, the
--     guide's line: client/TopBlocks.luau), the quick chat's button, the move's list and on a touch screen the touch
--     controls (client/TouchLayout.luau); none clear, the place that covers the least. On a touch screen its button and
--     its ✕ are at least Ui.MinTouch; 8.3 review: on a small one (667 × 375) it shrinks, SHRINK at a time down to the
--     HUD's scale, until a place within BESIDE px of his head is clear (none: the clear place nearest him; only its
--     button and its ✕ stay Ui.MinTouch tall), and never reaches down over the touch controls at the right (FIRE,
--     SPRINT, the hand button, DRAW, the jump button): such a place goes left of them. Placed again on a resize or
--     when the top blocks move. 8.4: on a small phone where his status line had to move off the middle (clear of the
--     money block and the TASKS chip), the line hides while the card is open (MoveHelperHud.cardOpen): its room is
--     the card's.
--   * One window at a time (client/Main.client.luau registers it: onOpen, ESC); ✕, ESC, the gamepad's B, a click or a
--     tap beside it, walking away from him, a seat, him gone close it. A tap beside it is only that: its own
--     TouchTapInWorld (as the finger lifts) is swallowed SWALLOW s, never a piece given or his card again. Walking away:
--     8.3 review: past Config.MoveHelper.CardReach studs (at least ClickReach: a click on him never opens a card that
--     shuts at once), or CardSlack studs farther than you were when it opened (the status line's LIST opens it from
--     anywhere).
--   * 8.6 the crew's orders (the owner: "… to be able to tell him, for example, put it down on the ground, or get out of
--     the car"): the server's MoveHelperOrders says which apply now (shared/MoveHelperBrain.luau orders: PUT IT DOWN
--     while he carries, GET OUT while he is in the van, getting in or on his way to it); each shows as a button
--     (MoveHelperBrain.orderWords: "⬇ PUT IT DOWN", "🚪 GET OUT") that sends the Moving remote's ("helper",
--     "putdown" | "getout") once and closes the card; the server checks and refuses with a notice. In the card they
--     are a row in place of its list's words and hint while one applies (its status over them keeps the count; the
--     card hardly grows: a small phone still has room beside him). ORDERS MENU: in orders mode (the clipboard out) a
--     click or a tap on Danny himself, or on the piece in his arms (welded to his body), opens the card's short form
--     beside him instead: "📋 DANNY · ORDERS", his status and the row of the orders that apply now ("Nothing to order
--     right now" when none does), the gamepad's selection on its first order (its prompt on him says "Orders for
--     Danny" then: L1); a click that reaches a piece nearer than him is the piece's (onto his list). Both forms are
--     the one window (Main's: ESC, onOpen, the mouse freed), placed by MoveHelperCard.layout (the menu MENU_W wide),
--     its buttons at least Ui.MinTouch tall on a touch screen.
--   * 8.9 the answers' sounds (art/audio/sfx5.ogg, quiet; client/SandboxSounds.luau await: the server decides, the sound
--     follows what it did): a piece given (a click, a tap, R1) ticked onto his list as its DannyQueue comes (a pen's
--     tick), taken back crossed off (shared/SoundPlan.luau giveOutcome); an order (PUT IT DOWN, GET OUT: the card's
--     row, the orders menu; MoveHelperCard.ordered for any other sender) his chirp once it leaves the orders that apply
--     (he did it: SoundPlan.orderOutcome); the card's 📋 CLIPBOARD asking it out as client/DannyOrders.luau's toggle.
--     Refused (the server's notice and nothing changed): the soft nope. Each in place of its notice's ping.
-- Presentation only.
--   MoveHelperCard.start()                         listens (nothing outside the sandbox)
--   MoveHelperCard.open(at?, menu?)                opens it beside the screen point `at` (nil: his head's now); 8.6
--                                                  menu: the orders menu (its short form)
--   MoveHelperCard.isMenu()                        8.6 open as the orders menu
--   MoveHelperCard.target(origin, direction) -> (Model?, boolean)   8.6 what a click in orders mode is on: a piece of
--                                                  your move, or Danny (his body, true)
--   MoveHelperCard.close(), .isOpen(), .card()     closes it / is it open / its frame (the checks)
--   MoveHelperCard.onOpen                          set by client/Main.client.luau (the other windows close)
--   MoveHelperCard.body()                          his body (nil: none on your move, or not streamed in)
--   MoveHelperCard.pieceAt(origin, direction)      the piece of your move a ray from `origin` hits first (its model), nil
--   MoveHelperCard.layout(W, H, S, touch, anchor, blocks, menu?, rows?) -> (box, scale)   where the card goes (px
--                                                  under Roblox's top bar; anchor: { x, y } or nil, the screen's middle;
--                                                  8.6 menu: the orders menu's size, rows: the card with its orders row)
--   MoveHelperCard.promptOf(model)                 8.5 a piece's own Pick up / Lift prompt when it is your move's (nil)
--   MoveHelperCard.giveTarget()                    8.5 the piece the gamepad's "Give to Danny" is on (nil: none)
--   MoveHelperCard.give(piece)                     9.0 E by a piece in orders mode (client/DannyOrders.luau's prompts):
--                                                  the click's request (onto his list or off it), its tick or the nope
--   MoveHelperCard.tapped() -> (Model?, number)    8.5 the piece a click or a tap last gave or took back, and when
--                                                  (os.clock())
--   MoveHelperCard.justClosed()                    8.5 it closed a moment ago (the gamepad's B that closed it is not
--                                                  client/DannyOrders.luau's B too, whichever hears it first)
--   MoveHelperCard.ordered(kind)                   8.9 an order ("putdown" | "getout") was just sent: his chirp when he
--                                                  takes it, the nope when refused (the card's buttons call it; the
--                                                  status line's GET OUT may)

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local SandboxPad = require(Shared.SandboxPad) -- (the gamepad's buttons for him: its actions "danny" and "dannygive")
local ClipboardRules = require(Shared.ClipboardRules) -- 8.5: orders mode's words
local SoundPlan = require(Shared.SoundPlan) -- 8.9: the answers' sounds
local PadGlyph = require(script.Parent.PadGlyph) -- 8.5: the device used now (the card's words)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)
local MoveHelperHud = require(script.Parent.MoveHelperHud)
local CarryGripUi = require(script.Parent.CarryGripUi)

local MoveHelperCard = {}

MoveHelperCard.onOpen = nil :: (() -> ())?

local H = Config.MoveHelper
local K = Theme.Contract
local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
-- the card at scale 1 (px)
local CARD_W, PAD, GAP = 320, 10, 8
local TITLE_H, DOING_H, CLOSE = 18, 16, 28
local LINE_H, HINT_H, BUTTON_H = 20, 30, 56
local MENU_W, ORDER_H = 264, 40 -- 8.6 the orders menu's width; an order's button (PUT IT DOWN, GET OUT)
local ORDER_KINDS = { "putdown", "getout" } -- 8.6 (in the row's order)
local MARGIN = 8 -- from the screen's edges and what it keeps clear of
local SIDE = 36 -- px between his head's point and the card beside it
local SHRINK = 0.05 -- 8.3 review: a small touch screen's card tries this much smaller each time (down to the HUD's scale)
local BESIDE = 3 * SIDE -- px: 8.3 review: a place this near his head counts as beside him (farther: a smaller card first)
local SWALLOW = 0.5 -- s: 8.3 review: a tap that closed the card is not a tap in the world too (its TouchTapInWorld)
local PIECE_REACH = 12 -- studs: the gamepad's "Give to Danny" on the nearest piece this near
local TALK_PAD = SandboxPad.pads("danny")[1] or "ButtonL1" -- (shared/SandboxPad.luau: L1 his)
local GIVE_PAD = SandboxPad.pads("dannygive")[1] or "ButtonR1"
local CREW_W = 74 -- 10.1 the card's 👥 CREW button (the CREW window)
-- (a piece's own prompt: Pick up, Lift; "Lift with <his name>" at his call: 10.1 any helper's name)
local function isPick(text: string): boolean
	return text == "Pick up" or text == "Lift" or string.sub(text, 1, 10) == "Lift with " or string.sub(text, 1, 13) == "Pick up with "
end
-- the HUD's groups (client/CarryGripUi.luau's list) and the sandbox's chips' ScreenGuis
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" } -- (a ScreenGui: its piece, "" every piece)

local remote = Net.get("Moving")
local clipboard = Net.get("Clipboard") -- 8.5: the card's 📋 CLIPBOARD
local started = false
local gui: ScreenGui? = nil
local parts: { [string]: any } = {} -- the card's pieces (built once)
local opened = false
local openToken = 0
local swallowUntil = 0 -- 8.3 review: os.clock() until which a tap in the world is the tap that closed the card
local anchorAt: { x: number, y: number }? = nil -- his head's point when it opened
local found: Model? = nil -- his body (found by MoveHelperId)
local prompt: ProximityPrompt? = nil -- the gamepad's "Talk to Danny" on him
local give: ProximityPrompt? = nil -- the gamepad's "Give to Danny" on the nearest piece
local giveTo: Model? = nil -- …that piece
local tappedPiece: Model? = nil -- 8.5 the piece a click or a tap last gave (client/DannyOrders.luau outlines it a moment)
local tappedAt = 0
local closedAt = -math.huge -- 8.5 os.clock() it last closed (the B that closed it puts no clipboard away)
local menu = false -- 8.6 open as the orders menu (its short form)

-- ── Where it goes (pure maths: the phone-ui check runs it) ──────────────────

-- Its height at a scale, its ✕'s, its button's and 8.6 an order's (a touch screen: at least Ui.MinTouch screen px
-- each), and 8.6 the height of its middle (its list's words and hint, or the orders row in their place: `rows`).
-- `menu`: the orders menu (its head and that row).
local function cardHeight(touch: boolean, scale: number, asMenu: boolean?, rows: boolean?): (number, number, number, number, number)
	local least = if touch then math.ceil(Ui.MinTouch / scale - 1e-6) else 0
	local close, button, order = math.max(CLOSE, least), math.max(BUTTON_H, least), math.max(ORDER_H, least)
	local head = math.max(TITLE_H + DOING_H, close)
	if asMenu then
		return PAD + head + GAP + order + PAD, close, button, order, order
	end
	local middle = if rows then math.max(order, LINE_H + HINT_H) else LINE_H + HINT_H
	return PAD + head + GAP + middle + GAP + button + PAD, close, button, order, middle
end

-- 8.3 review: the scales it tries, the biggest first: on a touch screen its button a finger's height as drawn, then
-- SHRINK smaller down to the HUD's scale S (a small phone); elsewhere S.
local function scalesFor(S: number, touch: boolean): { number }
	local big = if touch then math.max(S, Ui.MinTouch / BUTTON_H) else S
	local list = { big }
	local s = big - SHRINK
	while s > S + 1e-6 do
		table.insert(list, s)
		s -= SHRINK
	end
	if big > S + 1e-6 then
		table.insert(list, S)
	end
	return list
end

local function clearOf(b: TouchLayout.Box, W: number, H: number, blocks: { TouchLayout.Box }): boolean
	if not MoveLayout.inside(b, W, H) then
		return false
	end
	for _, other in blocks do
		if TouchLayout.overlap(b, other) then
			return false
		end
	end
	return true
end

function MoveHelperCard.layout(W: number, H: number, S: number, touch: boolean, anchor: { x: number, y: number }?, blocks: { TouchLayout.Box },
	asMenu: boolean?, rows: boolean?): (TouchLayout.Box, number)
	local wide = if asMenu then MENU_W else CARD_W -- 8.6
	local avoid = table.clone(blocks)
	-- (a touch screen: the right-hand controls' corner, from the column's left edge and the highest one's top)
	local cornerX, cornerY = math.huge, math.huge
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(avoid, b)
		end
		table.insert(avoid, c.thumb)
		table.insert(avoid, c.jump)
		cornerX, cornerY = c.left - MARGIN, c.top - MARGIN
	end
	local ax = if anchor then anchor.x else W / 2
	local ay = if anchor then anchor.y else H * 0.45
	if anchor then
		table.insert(avoid, TouchLayout.box(ax - 26 * S, ay - 30 * S, ax + 26 * S, ay + 90 * S)) -- (never on him: his head, his body)
	end
	-- (a clear place but farther from his head than BESIDE: the nearest of them, if no scale has one beside him)
	local far: TouchLayout.Box? = nil
	local farScale, farGap = S, math.huge
	local fallback: TouchLayout.Box? = nil
	local fallbackScale = S
	local fallbackCost = math.huge
	for _, scale in scalesFor(S, touch) do
		local tall = cardHeight(touch, scale, asMenu, rows)
		local w, h = wide * scale, tall * scale
		-- the preferred place: right of his head, level with it; then left of it, over it, under it; and every place
		-- flush against an edge of what is there
		local px, py = ax + SIDE, ay - h / 2
		local xs = { px, ax - SIDE - w, ax - w / 2 }
		local ys = { py, ay - SIDE - h, ay + SIDE }
		for _, b in avoid do
			table.insert(xs, b.x1 + MARGIN)
			table.insert(xs, b.x0 - MARGIN - w)
			table.insert(ys, b.y1 + MARGIN)
			table.insert(ys, b.y0 - MARGIN - h)
		end
		local best: TouchLayout.Box? = nil
		local bestNear = math.huge
		for _, y in ys do
			local y0 = math.floor(math.clamp(y, MARGIN, math.max(MARGIN, H - MARGIN - h)) + 0.5) -- (whole px: where it is put)
			for _, x in xs do
				local x0 = math.floor(math.clamp(x, MARGIN, math.max(MARGIN, W - MARGIN - w)) + 0.5)
				if y0 + h > cornerY and x0 + w > cornerX then
					x0 = math.floor(math.max(MARGIN, cornerX - w)) -- (down beside the touch controls: left of them)
				end
				local b = TouchLayout.box(x0, y0, x0 + w, y0 + h)
				local near = math.abs(x0 - px) + math.abs(y0 - py)
				if near < bestNear and clearOf(b, W, H, avoid) then
					local gap = if anchor then math.max(x0 - ax, ax - b.x1, y0 - ay, ay - b.y1, 0) else 0
					if gap <= BESIDE then
						best, bestNear = b, near
					elseif gap < farGap then
						far, farScale, farGap = b, scale, gap
					end
				end
				local bad = MoveLayout.clash(b, W, H, avoid) + 1e-3 * near
				if bad < fallbackCost then
					fallback, fallbackScale, fallbackCost = b, scale, bad
				end
			end
		end
		if best then
			return best, scale -- (the biggest scale with a clear place beside him)
		end
	end
	if far then
		return far, farScale
	end
	return (fallback or TouchLayout.box(MARGIN, MARGIN, MARGIN + wide * S, MARGIN + cardHeight(touch, S, asMenu, rows) * S)) :: TouchLayout.Box, fallbackScale
end

-- ── His body, the pieces ───────────────────────────────────────────────────

function MoveHelperCard.body(): Model?
	local id = player:GetAttribute("MoveHelperId")
	if type(id) ~= "number" then
		found = nil
		return nil
	end
	local was = found
	if was and was.Parent and was:GetAttribute("MoveHelper") == id then
		return was
	end
	found = nil
	local folder = workspace:FindFirstChild("Npcs")
	for _, child in (if folder then folder:GetChildren() else {}) :: { Instance } do
		if child:IsA("Model") and child:GetAttribute("MoveHelper") == id then
			found = child
			return child
		end
	end
	return nil
end

local function rootOf(model: Model?): BasePart?
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return if root and root:IsA("BasePart") then root else nil
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function hired(): boolean
	return player:GetAttribute("MoveHelper") == "hired"
end

-- 10.1 his name (the crew's helper's: MoveHelperName), Danny's without one.
local function nameNow(): string
	return Brain.nameOf(player:GetAttribute("MoveHelperName"))
end

-- 8.5 orders mode: your clipboard out (the server's ClipboardHeld on your character).
local function orders(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("ClipboardHeld") == true
end

-- May a click, a tap or a prompt act now (Danny on your move, your hands free, not waiting for him, no grip check, on
-- foot)?
local function mayAct(): boolean
	local character = player.Character
	return type(player:GetAttribute("MoveHelper")) == "string" and character ~= nil and character:GetAttribute("Carrying") == nil
		and character:GetAttribute("Pushing") == nil and player:GetAttribute("MoveHelperCall") == nil and not seated() and not CarryGripUi.active()
end

-- A piece's own prompt (its Pick up / Lift, tagged MovePrompt) when it is your move's: shown to you (MovingHud's rule).
local function piecePrompt(model: Instance): ProximityPrompt?
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and isPick(d.ActionText) then
			local owner = d:GetAttribute("MoveOwner")
			if type(owner) == "number" and (owner == player.UserId or player:GetAttribute("MoveWith") == owner) then
				return d
			end
			return nil
		end
	end
	return nil
end

function MoveHelperCard.promptOf(model: Instance): ProximityPrompt?
	return piecePrompt(model)
end

function MoveHelperCard.giveTarget(): Model?
	return if give ~= nil and give.Enabled then giveTo else nil
end

function MoveHelperCard.tapped(): (Model?, number)
	return tappedPiece, tappedAt
end

function MoveHelperCard.justClosed(): boolean
	return os.clock() - closedAt < 0.1
end

-- The piece of your move a ray hits first (its model: the attribute MoveSpot), nil: none, or another move's.
function MoveHelperCard.pieceAt(origin: Vector3, direction: Vector3): Model?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		table.insert(ignore, npcs) -- (Danny, a crew mate's … never in the way of a piece)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, direction * H.ClickReach, params)
	local node: Instance? = if hit then hit.Instance else nil
	while node and node ~= workspace do
		if node:IsA("Model") and type(node:GetAttribute("MoveSpot")) == "number" then
			return if piecePrompt(node) then node else nil
		end
		node = node.Parent
	end
	return nil
end

-- His head's point on the screen (px under the top bar), nil: behind the camera or off it.
local function headPoint(): { x: number, y: number }?
	local camera = workspace.CurrentCamera
	local root = rootOf(MoveHelperCard.body())
	if not camera or not root then
		return nil
	end
	local ok, point, visible = pcall(function()
		return camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.2, 0))
	end)
	if not ok or not visible then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	return { x = point.X, y = point.Y - inset.Y }
end

-- Does a ray (unit `direction`) from `origin` reach him: his body hit, or passing within TapSlop studs of his middle
-- with nothing nearer in the way?
local function reaches(origin: Vector3, direction: Vector3): boolean
	local model = MoveHelperCard.body()
	local root = rootOf(model)
	if not model or not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character :: Instance } else {}
	local hit = workspace:Raycast(origin, direction * H.ClickReach, params)
	if hit and hit.Instance:IsDescendantOf(model) then
		return true
	end
	local to = root.Position - origin
	local along = to:Dot(direction)
	if along <= 0 or along > H.ClickReach or (to - direction * along).Magnitude > H.TapSlop then
		return false
	end
	return hit == nil or (hit.Position - origin).Magnitude >= along - 1.5
end

-- 8.6 is a piece in his arms (welded to his body: server/Moving.luau's weldTo)?
local function heldBy(piece: Model, model: Model): boolean
	local root = rootOf(piece)
	if not root then
		return false
	end
	for _, child in root:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("Weld") then
			local weld = child :: any
			local other = if weld.Part0 == root then weld.Part1 else weld.Part0
			if other and other:IsDescendantOf(model) then
				return true
			end
		end
	end
	return false
end

function MoveHelperCard.target(origin: Vector3, direction: Vector3): (Model?, boolean)
	local piece = MoveHelperCard.pieceAt(origin, direction)
	local model = MoveHelperCard.body()
	if not model then
		return piece, false
	end
	if piece and heldBy(piece, model) then
		return model, true -- (the piece in his arms: his orders, PUT IT DOWN)
	end
	if reaches(origin, direction) then
		local his, its = rootOf(model), if piece then rootOf(piece) else nil
		if not piece or not its or (his and (his.Position - origin):Dot(direction) <= (its.Position - origin):Dot(direction)) then
			return model, true
		end
	end
	return piece, false
end

-- ── 8.9 the answers' sounds ────────────────────────────────────────────────

-- An answer awaited from the server (client/SandboxSounds.luau await; nothing where it is not there).
local function answer(outcome: () -> string?)
	pcall(function()
		(require(script.Parent.SandboxSounds) :: any).await(outcome)
	end)
end

-- A piece of your move sent onto his list or off it (the server decides): its tick, its cross-off or the nope.
local function given(piece: Model)
	tappedPiece, tappedAt = piece, os.clock()
	remote:FireServer("helper", "assign", piece)
	local was = piece:GetAttribute("DannyQueue") ~= nil
	answer(function(): string?
		return SoundPlan.giveOutcome(was, piece:GetAttribute("DannyQueue") ~= nil)
	end)
end

-- 9.0 E by a piece in orders mode (client/DannyOrders.luau's "Give to Danny" / "Take back" prompts): the same request
-- as a click on it (onto his list or off it; the server checks), only while a click there would give it.
function MoveHelperCard.give(piece: Model)
	if mayAct() and hired() and orders() and not opened then
		given(piece) -- (8.9: its tick or the nope)
	end
end

function MoveHelperCard.ordered(kind: string)
	local before = player:GetAttribute("MoveHelperOrders")
	answer(function(): string?
		return SoundPlan.orderOutcome(kind, before, player:GetAttribute("MoveHelperOrders"))
	end)
end

-- The clipboard asked out (the card's 📋 CLIPBOARD): its rustle is client/DannyOrders.luau's; refused, the nope.
local function askedOut()
	answer(function(): string?
		local character = player.Character
		return if character ~= nil and character:GetAttribute("ClipboardHeld") == true then "" else nil
	end)
end

-- ── The card ───────────────────────────────────────────────────────────────

local function send(kind: string)
	if not opened then
		return -- (a second tap as it closes: one request)
	end
	remote:FireServer("helper", kind)
	if table.find(ORDER_KINDS, kind) then
		MoveHelperCard.ordered(kind) -- 8.9 (his chirp when he takes it)
	end
	MoveHelperCard.close()
end

local function build(): Frame?
	local made = parts.card
	if made and made.Parent then
		return made
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Ui.make("ScreenGui", {
		Name = "MoveHelperCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	}, playerGui)
	gui = screen
	local card = Ui.make("Frame", {
		Name = "DannyCard",
		Size = UDim2.fromOffset(CARD_W, 200),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		SelectionGroup = true, -- (8.3 review: the gamepad's selection stays in the card, never onto a HUD chip)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, screen)
	Ui.corner(card, 10)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 2 }, card)
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, card)
	parts.title = Ui.label(card, `{Brain.iconOf(player:GetAttribute("MoveHelperKind"))} {string.upper(nameNow())}`, UDim2.fromOffset(CARD_W - 2 * PAD - CLOSE - GAP, TITLE_H), {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, PAD),
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	parts.doing = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD - CLOSE - GAP, DOING_H), {
		Name = "Doing",
		Position = UDim2.fromOffset(PAD, PAD + TITLE_H),
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = Ui.make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, PAD),
		Size = UDim2.fromOffset(CLOSE, CLOSE),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		Text = "✕",
	}, card)
	Ui.corner(close, 6)
	close.Activated:Connect(function()
		MoveHelperCard.close()
	end)
	parts.close = close
	-- 10.1 👥 CREW: the CREW window (your crew, who comes into your runs; the server opens it: the Crew remote)
	local crew = Ui.make("TextButton", {
		Name = "Crew",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(PAD + CLOSE + GAP), 0, PAD),
		Size = UDim2.fromOffset(CREW_W, CLOSE),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.text,
		Text = "👥 CREW",
	}, card)
	Ui.corner(crew, 6)
	crew.Activated:Connect(function()
		if not opened then
			return
		end
		Net.get("Crew"):FireServer({ kind = "open" })
		MoveHelperCard.close()
	end)
	parts.crew = crew
	parts.line = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD, LINE_H), {
		Name = "Line",
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	parts.hint = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD, HINT_H), {
		Name = "Hint",
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
	local main = Ui.make("TextButton", {
		Name = "Main",
		Size = UDim2.fromOffset(CARD_W - 2 * PAD, BUTTON_H),
		BackgroundColor3 = ORANGE,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.charcoal,
		Text = "CLEAR QUEUE",
	}, card)
	Ui.corner(main, 8)
	parts.edge = Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1, Transparency = 1 }, main)
	main.Activated:Connect(function()
		send("clear")
	end)
	parts.main = main
	-- 8.5 📋 CLIPBOARD (the clipboard out; 📋 PUT AWAY while it is) beside CLEAR QUEUE, the card closes
	local clip = Ui.make("TextButton", {
		Name = "Clip",
		Size = UDim2.fromOffset((CARD_W - 2 * PAD - GAP) / 2, BUTTON_H),
		BackgroundColor3 = ORANGE,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.charcoal,
		Text = ClipboardRules.cardButton(false),
		Visible = false,
	}, card)
	Ui.corner(clip, 8)
	clip.Activated:Connect(function()
		if not opened then
			return -- (a second tap as it closes: one request)
		end
		local out = not orders()
		clipboard:FireServer(out)
		if out then
			askedOut() -- 8.9
		end
		MoveHelperCard.close()
	end)
	parts.clip = clip
	-- 8.6 the crew's orders that apply now (the server's MoveHelperOrders): a row over the buttons (where the list's
	-- words and hint were), the menu's only row
	parts.order, parts.orderEdge = {}, {}
	for _, kind in ORDER_KINDS do
		local button = Ui.make("TextButton", {
			Name = if kind == "putdown" then "PutDown" else "GetOut",
			Size = UDim2.fromOffset(CARD_W - 2 * PAD, ORDER_H),
			BackgroundColor3 = K.raised,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.HeadingFont,
			TextSize = 15,
			TextColor3 = K.text,
			Text = Brain.orderWords(kind),
			Visible = false,
		}, card)
		Ui.corner(button, 8)
		parts.orderEdge[kind] = Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = ORANGE, Thickness = 1.5 }, button)
		button.Activated:Connect(function()
			send(kind) -- (once; the card closes, the server decides)
		end)
		parts.order[kind] = button
	end
	parts.none = Ui.label(card, "Nothing to order right now", UDim2.fromOffset(MENU_W - 2 * PAD, ORDER_H), {
		Name = "NoOrders",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Visible = false,
	})
	parts.card = card
	return card
end

-- 8.6 the orders that apply now (the server's), in the row's order.
local function ordersNow(): { string }
	if not hired() then
		return {}
	end
	local out: { string } = {}
	local now = Brain.orderList(player:GetAttribute("MoveHelperOrders"))
	for _, kind in ORDER_KINDS do
		if table.find(now, kind) then
			table.insert(out, kind)
		end
	end
	return out
end

-- The card's own words and colours: his status, his list, how to give him pieces with this input (8.5 the clipboard's,
-- 📋 CLIPBOARD, CLEAR QUEUE). (10.1: no "for hire" and no HIRE any more.)
local function paint()
	if not parts.card then
		return
	end
	local count = player:GetAttribute("MoveHelperQueue")
	local doing = player:GetAttribute("MoveHelperDoing")
	local name = nameNow()
	parts.doing.Text = Brain.status(count, if type(doing) == "string" then doing else nil)
	-- 8.6 the orders that apply now: in the card a row in place of its list's words and hint (raised, an orange edge; the
	-- status over it keeps the count), in the orders menu its only row (orange: the menu's actions) or "Nothing to order
	-- right now"
	local now = ordersNow()
	for kind, button in parts.order do
		button.Visible = table.find(now, kind) ~= nil
		button.BackgroundColor3 = if menu then ORANGE else K.raised
		button.TextColor3 = if menu then K.charcoal else K.text
		parts.orderEdge[kind].Transparency = if menu then 1 else 0
	end
	parts.none.Visible = menu and #now == 0
	parts.title.Text = if menu then `📋 {string.upper(name)} · ORDERS` else `{Brain.iconOf(player:GetAttribute("MoveHelperKind"))} {string.upper(name)}`
	parts.crew.Visible = not menu -- 10.1
	parts.line.Visible, parts.hint.Visible, parts.main.Visible = not menu and #now == 0, not menu and #now == 0, not menu
	parts.clip.Visible = not menu -- 8.5
	parts.line.Text = Brain.queueText(count)
	-- 8.5 orders mode: a piece goes to him only with the clipboard out (its key on this device)
	parts.hint.Text = ClipboardRules.cardHint(PadGlyph.device(), name)
	parts.main.Text = "CLEAR QUEUE"
	parts.main.BackgroundColor3 = K.raised
	parts.main.TextColor3 = K.text
	parts.edge.Transparency = 0
	local out = orders()
	parts.clip.Text = ClipboardRules.cardButton(out)
	parts.clip.BackgroundColor3 = if out then K.raised else ORANGE
	parts.clip.TextColor3 = if out then K.text else K.charcoal
end

-- What it keeps clear of, in its ScreenGui's px.
local function blocksNow(origin: Vector2): { TouchLayout.Box }
	local list: { TouchLayout.Box } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(list, TouchLayout.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
		end
	end
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, name in HUD_GROUPS do
			add(hud:FindFirstChild(name))
		end
	end
	for guiName, piece in CHIP_GUIS do
		local holder = playerGui and playerGui:FindFirstChild(guiName)
		if holder and (holder :: any).Enabled ~= false then
			if piece ~= "" then
				add(holder:FindFirstChild(piece, true))
			else
				for _, child in holder:GetChildren() do
					add(child)
				end
			end
		end
	end
	for _, r in TopBlocks.rects(origin) do -- (the move's panel, Danny's status line, the guide's line, the planning)
		table.insert(list, r)
	end
	local chat = playerGui and playerGui:FindFirstChild("QuickChat")
	local moving = playerGui and playerGui:FindFirstChild("MovingHud")
	add(chat and chat:FindFirstChild("QuickChatButton"))
	add(moving and moving:FindFirstChild("MoveList", true))
	return list
end

-- Its place and size for this screen (beside his head's point as it opened).
local function place()
	local card = parts.card
	local screen = gui
	if not opened or not card or not screen then
		return
	end
	local size = screen.AbsoluteSize
	local W, Hh = size.X, size.Y
	if W < 2 or Hh < 2 then
		local s = Ui.screenSize()
		W, Hh = s.X, s.Y
	end
	local touch = Ui.touchLayout()
	local now = ordersNow() -- 8.6 (paint shows the buttons of these)
	local rows = not menu and #now > 0
	local b, scale = MoveHelperCard.layout(W, Hh, Ui.screenScale(), touch, anchorAt, blocksNow(screen.AbsolutePosition), menu, rows)
	local tall, close, button, order, middle = cardHeight(touch, scale, menu, rows)
	local wide = if menu then MENU_W else CARD_W
	card.Size = UDim2.fromOffset(wide, tall)
	-- (8.5: 📋 CLIPBOARD left, CLEAR QUEUE right, half the row each)
	local half = (CARD_W - 2 * PAD - GAP) / 2
	local split = parts.clip.Visible
	parts.main.Size = UDim2.fromOffset(if split then half else CARD_W - 2 * PAD, button)
	parts.clip.Size = UDim2.fromOffset(half, button)
	card.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	parts.scale.Scale = scale
	local head = math.max(TITLE_H + DOING_H, close)
	parts.close.Size = UDim2.fromOffset(close, close)
	local crewW = math.max(CREW_W, close) -- 10.1 (as tall as ✕, at least as wide: a finger's size on a touch screen)
	parts.crew.Size = UDim2.fromOffset(crewW, close)
	parts.crew.Position = UDim2.new(1, -(PAD + close + GAP), 0, PAD)
	local wordsW = wide - 2 * PAD - close - GAP - (if menu then 0 else crewW + GAP)
	parts.title.Size = UDim2.fromOffset(wordsW, TITLE_H)
	parts.doing.Size = UDim2.fromOffset(wordsW, DOING_H)
	local top = PAD + head + GAP
	parts.line.Position = UDim2.fromOffset(PAD, top)
	parts.hint.Position = UDim2.fromOffset(PAD, top + LINE_H)
	-- 8.6 the orders row: the menu's right under its head, the card's in its middle (its list's words and hint step
	-- aside meanwhile: its status keeps the count), over its buttons
	local orderY = if menu then top else top + math.floor((middle - order) / 2)
	local each = (wide - 2 * PAD - (math.max(#now, 1) - 1) * GAP) / math.max(#now, 1)
	for index, kind in now do
		local orderButton = parts.order[kind]
		orderButton.Size = UDim2.fromOffset(each, order)
		orderButton.Position = UDim2.fromOffset(PAD + (index - 1) * (each + GAP), orderY)
	end
	parts.none.Size = UDim2.fromOffset(wide - 2 * PAD, order)
	parts.none.Position = UDim2.fromOffset(PAD, orderY)
	local buttonsY = top + middle + GAP
	parts.main.Position = UDim2.fromOffset(if split then PAD + half + GAP else PAD, buttonsY)
	parts.clip.Position = UDim2.fromOffset(PAD, buttonsY)
end

function MoveHelperCard.isOpen(): boolean
	return opened
end

function MoveHelperCard.isMenu(): boolean
	return opened and menu
end

function MoveHelperCard.card(): Frame?
	return parts.card
end

-- 8.3 review: as it closes, the gamepad's selection is let go when it sits in the card or in no window (the HUD's
-- groups and the sandbox's chips, where it could drift; nothing shown any more): client/PadGlyph.luau's chips need none.
-- One in another window (it opened over this card) is that window's.
local function letGo(card: Frame)
	Ui.gamepadRelease(card)
	local selected = Ui.gamepadSelection()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not selected or not playerGui then
		return
	end
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	for _, name in HUD_GROUPS do
		local group = hud and hud:FindFirstChild(name)
		if group and selected:IsDescendantOf(group) then
			Ui.gamepadRelease(group)
			return
		end
	end
	for guiName in CHIP_GUIS do
		local holder = playerGui:FindFirstChild(guiName)
		if holder and selected:IsDescendantOf(holder) then
			Ui.gamepadRelease(holder)
			return
		end
	end
	local node: Instance? = selected
	while node and node ~= playerGui do
		if (node:IsA("GuiObject") and not (node :: GuiObject).Visible) or (node:IsA("ScreenGui") and not (node :: ScreenGui).Enabled) then
			break -- (hidden)
		end
		node = node.Parent
	end
	if node ~= playerGui then
		Ui.gamepadRelease(playerGui)
	end
end

function MoveHelperCard.close()
	if not opened then
		return
	end
	opened = false
	openToken += 1
	closedAt = os.clock()
	local card = parts.card
	if card then
		letGo(card)
		card.Visible = false
	end
	MoveHelperHud.cardOpen(false) -- 8.4 (his status line back where it gave the card its room)
end

-- How far apart you and he are now (studs; nil: a body not there).
local function apart(): number?
	local mine, his = myRoot(), rootOf(MoveHelperCard.body())
	return if mine and his then (mine.Position - his.Position).Magnitude else nil
end

function MoveHelperCard.open(at: { x: number, y: number }?, asMenu: boolean?)
	if type(player:GetAttribute("MoveHelper")) ~= "string" then
		return
	end
	local card = build()
	if not card then
		return
	end
	anchorAt = at or headPoint()
	menu = asMenu == true -- 8.6 the orders menu (its short form)
	opened = true
	openToken += 1
	local token = openToken
	card.Visible = true
	MoveHelperHud.cardOpen(true) -- 8.4 (a small phone: his status line, moved off the middle, gives it its room)
	paint()
	place()
	local hook = MoveHelperCard.onOpen
	if hook then
		hook() -- (client/Main.client.luau: the other windows close)
	end
	-- (8.3 review: ✕ first: an A by habit never clears his list; 8.6 the orders menu: its first order, asked for)
	local first = ordersNow()[1]
	Ui.gamepadFocus(if menu then (if first then parts.order[first] else parts.close) else parts.close)
	-- walking away from him (8.3 review: past CardReach, or CardSlack studs farther than you were as it opened: the
	-- status line opens it from anywhere), a seat, him gone: it closes (a look every quarter second while it is open)
	local from = apart()
	local out = orders() -- (8.5: the clipboard out or away while it is open: its button says so)
	task.spawn(function()
		while opened and openToken == token do
			task.wait(0.25)
			if not opened or openToken ~= token then
				return
			end
			if orders() ~= out then
				out = orders()
				paint()
			end
			local now = apart()
			if now and not from then
				from = now -- (a body streamed in since it opened)
			end
			local reach = math.max(H.CardReach, (from or 0) + H.CardSlack)
			if type(player:GetAttribute("MoveHelper")) ~= "string" or seated() or (now and now > reach) then
				MoveHelperCard.close()
				return
			end
		end
	end)
end

-- Is a screen point (px under the top bar) on the card?
local function onCard(x: number, y: number): boolean
	local card = parts.card
	if not card or not card.Visible then
		return false
	end
	local at, size = card.AbsolutePosition, card.AbsoluteSize
	return x >= at.X and x <= at.X + size.X and y >= at.Y and y <= at.Y + size.Y
end

-- A click or a tap in the world (a ray): on him, his card. 8.5 orders mode (your clipboard out, a helper with you): on a
-- piece of your move, onto his list or off it (the server decides); 8.6 on him (or the piece in his arms): his orders
-- menu (MoveHelperCard.target); without the clipboard a piece is nothing to him (no stray orders).
local function clicked(origin: Vector3, direction: Vector3)
	if orders() then
		if not hired() then
			return
		end
		local target, him = MoveHelperCard.target(origin, direction)
		if him then
			MoveHelperCard.open(nil, true) -- 8.6
		elseif target then
			given(target) -- (8.9: its tick or the nope)
		end
		return
	end
	if reaches(origin, direction) then
		MoveHelperCard.open(nil)
	end
end

-- ── The gamepad's prompts: on him, on the nearest piece ────────────────────

local function keepPrompt()
	local model = MoveHelperCard.body()
	local root = rootOf(model)
	local made = prompt
	if not root then
		if made then
			made:Destroy()
			prompt = nil
		end
		return
	end
	if not made or made.Parent ~= root then
		if made then
			made:Destroy()
		end
		local fresh = Instance.new("ProximityPrompt")
		fresh.Name = "TalkToDanny"
		fresh.ObjectText = ""
		fresh.GamepadKeyCode = (Enum.KeyCode :: any)[TALK_PAD]
		fresh.HoldDuration = 0
		fresh.MaxActivationDistance = 12
		fresh.RequiresLineOfSight = false
		fresh.Triggered:Connect(function()
			if mayAct() then
				MoveHelperCard.open(nil, hired() and orders()) -- (8.6 orders mode: his orders menu)
			end
		end)
		fresh.Parent = root
		prompt = fresh
		made = fresh
	end
	local p = made :: ProximityPrompt
	local words = if orders() then `Orders for {nameNow()}` else `Talk to {nameNow()}`
	if p.ActionText ~= words then
		p.ActionText = words
	end
	local on = Ui.gamepadActive() and mayAct()
	if p.Enabled ~= on then
		p.Enabled = on
	end
end

-- The nearest piece of your move within PIECE_REACH (its own prompt shown: home or on the ground; or on his list).
local function nearestPiece(): Model?
	local mine = myRoot()
	if not mine then
		return nil
	end
	local best: Model? = nil
	local bestDistance = PIECE_REACH
	for _, tagged in CollectionService:GetTagged("MovePrompt") do
		local root = tagged.Parent
		local model = root and root.Parent
		if not tagged:IsA("ProximityPrompt") or not isPick(tagged.ActionText) or not root or not root:IsA("BasePart") or not model or not model:IsA("Model") then
			continue
		end
		if type(model:GetAttribute("MoveSpot")) ~= "number" or (not tagged.Enabled and model:GetAttribute("DannyQueue") == nil) or piecePrompt(model) == nil then
			continue
		end
		local d = (root.Position - mine.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = model, d
		end
	end
	return best
end

local function keepGive()
	local on = Ui.gamepadActive() and hired() and mayAct() and orders() -- (8.5: only with the clipboard out)
	local piece = if on then nearestPiece() else nil
	local root = if piece then rootOf(piece) else nil
	local made = give
	if not piece or not root then
		if made then
			made.Enabled = false
		end
		giveTo = nil
		return
	end
	if not made or made.Parent ~= root then
		if made then
			made:Destroy()
		end
		local fresh = Instance.new("ProximityPrompt")
		fresh.Name = "GiveToDanny"
		fresh.GamepadKeyCode = (Enum.KeyCode :: any)[GIVE_PAD]
		fresh.HoldDuration = 0
		fresh.MaxActivationDistance = PIECE_REACH
		fresh.RequiresLineOfSight = false
		fresh.UIOffset = Vector2.new(0, 60) -- (under the piece's own prompt)
		fresh.Triggered:Connect(function()
			local to = giveTo
			if to and mayAct() and hired() and orders() then
				given(to) -- (8.9: its tick or the nope)
			end
		end)
		fresh.Parent = root
		give = fresh
		made = fresh
	end
	giveTo = piece
	local p = made :: ProximityPrompt
	local words = if piece:GetAttribute("DannyQueue") ~= nil then `Take back from {nameNow()}` else `Give to {nameNow()}`
	if p.ActionText ~= words then
		p.ActionText = words
	end
	local own = piecePrompt(piece)
	local object = if own then own.ObjectText else ""
	if p.ObjectText ~= object then
		p.ObjectText = object
	end
	if not p.Enabled then
		p.Enabled = true
	end
end

function MoveHelperCard.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	MoveHelperHud.useCard(function()
		if MoveHelperCard.isOpen() then
			MoveHelperCard.close()
		else
			MoveHelperCard.open(nil)
		end
	end)
	for _, name in { "MoveHelper", "MoveHelperDoing", "MoveHelperId", "MoveHelperCall", "MoveHelperName", "MoveHelperQueue", "MoveHelperOrders" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if type(player:GetAttribute("MoveHelper")) ~= "string" then
				MoveHelperCard.close()
			elseif opened then
				paint()
				place() -- (8.5: its button row splits for 📋 CLIPBOARD; 8.6 the orders row comes and goes)
				local selected = Ui.gamepadSelection()
				local card = parts.card
				if selected and card and selected:IsDescendantOf(card) and not selected.Visible then
					local first = ordersNow()[1] -- (8.6: an order gone from under the selection: the next, else ✕)
					Ui.gamepadFocus(if first then parts.order[first] else parts.close)
				end
			end
			pcall(keepPrompt) -- (his body by his id; off while you wait for him)
		end)
	end
	-- a click (a computer) or the input beside the open card (it closes); B while it is open
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local kind = input.UserInputType
		if opened then
			if input.KeyCode == Enum.KeyCode.ButtonB then
				MoveHelperCard.close()
				return
			end
			if not processed and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and not onCard(input.Position.X, input.Position.Y) then
				MoveHelperCard.close() -- (a click or a tap beside it)
				if kind == Enum.UserInputType.Touch then
					swallowUntil = os.clock() + SWALLOW -- (8.3 review: its TouchTapInWorld as the finger lifts is not a tap on a piece)
				end
			end
			return
		end
		if processed or kind ~= Enum.UserInputType.MouseButton1 or not mayAct() then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local ray = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			then camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
			else camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		clicked(ray.Origin, ray.Direction.Unit)
	end)
	-- a tap on him or on a piece (a touch screen)
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed or opened or os.clock() < swallowUntil or not mayAct() then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		clicked(ray.Origin, ray.Direction.Unit)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		pcall(keepPrompt)
		pcall(keepGive)
		if opened then
			paint()
		end
	end)
	-- the screen, the top blocks: placed again
	TopBlocks.onChanged(function()
		place()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			place()
		end)
	end
	-- his body comes and goes (streaming, a respawn): his prompt follows it (a look every second); the gamepad's "Give to
	-- Danny" follows the nearest piece (a look every quarter second, only while a gamepad is in use)
	task.spawn(function()
		local tick = 0
		while true do
			if tick % 4 == 0 then
				pcall(keepPrompt)
			end
			if Ui.gamepadActive() or give ~= nil then
				pcall(keepGive)
			end
			tick += 1
			task.wait(0.25)
		end
	end)
end

return MoveHelperCard
