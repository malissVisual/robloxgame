--!strict
-- 9.x LOOT (the owner: "... and stars by rarity, so it has value"; Config.Loot.Stars, .Toast, .Sparkle): what a piece
-- with a rarity is worth, at a glance, on this client. The server decides the rarity and the value (server/Loot.luau,
-- server/Warehouse.luau: the model's Rarity, Stars and Value attributes and the CollectionService tag Config.Loot.Tag);
-- this only shows them. Its colours are the tiers' (Config.Collection.Tiers), its look the HUD's contract style (Theme).
--   * The stars: a small BillboardGui over each of the Stars.Count nearest pieces within Stars.Range studs of the
--     camera (a phone: DeviceBudget's share and reach): ★ × its Stars in the tier's colour on the HUD's charcoal pill
--     (sized like Danny's bubble, client/DannyBubble.luau), and within Stars.Near studs also the tier's name and its value
--     ("★★★ RARE · $450"). It fades out from Stars.Fade to Stars.Range (LootRules.fade) and is never drawn through a wall
--     or over the HUD (AlwaysOnTop false: the world's depth; a BillboardGui is under every ScreenGui). None while a
--     window is open (LootStars.covered, client/Main.client.luau sets it), none over the piece in your own hands. The
--     warehouse's stands' pieces carry the same (server/Warehouse.luau), so their stars show there too.
--   * The toast: your own pick-up or load of a piece of Toast.From's tier or better: "+ RARE Grandma's Clock ★★★ $450"
--     in the tier's colour, under the HUD's toasts (client/Hud.luau's column, its slot "loot"), once a piece, Toast.Gap
--     s apart at least (the next ones wait), Toast.Most at once, Toast.Seconds on screen; an Epic or Legendary one with
--     its sound. Your pick-up is your character's MoveCarry (server/Moving.luau) turning to the piece's MoveSpot; your
--     load is that piece welded into a van a moment after it left your hands (not set down on the floor).
--   * The first sight: an Epic or Legendary piece of a house (its model has a MoveSpot), where the house holds it (not
--     welded in somebody's hands or a van), the first time it is within Sparkle.See studs and in sight (a ray from the
--     camera: not through a wall) sparkles in its colour for Sparkle.Seconds (a ParticleEmitter with its default
--     sparkle texture: no new asset) and plays its sound (Sparkle.Sounds: the sheets' sounds, client/Sounds.luau; no
--     new audio).
--   * Throttled: one look every Stars.Every s (the distances, the bubbles, the pick-up, the toasts); the pieces are the
--     tag's list (its added / removed signals: no GetDescendants), a bubble's words drawn again only when they change.
--   LootStars.start()               listens (once; client/Main.client.luau starts it in the sandbox)
--   LootStars.step()                one look (the loop calls it; the phone-ui scene too)
--   LootStars.toast(rarity, name, value)   a toast now (or as soon as Toast.Gap allows)
--   LootStars.covered               () -> boolean: a window covers the game (no stars then); nil: never
--   LootStars.bubbles()             the BillboardGuis in use now (the checks)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LootRules = require(Shared.LootRules)
local FurnitureLooks = require(Shared.FurnitureLooks)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local DeviceBudget = require(script.Parent.DeviceBudget)

local LootStars = {}

LootStars.covered = nil :: (() -> boolean)?

local S = Config.Loot.Stars
local T = Config.Loot.Toast
local SP = Config.Loot.Sparkle
local K = Theme.Contract
local player = Players.LocalPlayer
local EDGE = 0.55 -- the pill's edge in the tier's colour: its own transparency
local GAP = 5 -- px between the stars and the words beside them
local TOAST_H = 30 -- px: a toast's height (at the column's scale)
local RULE = 3 -- px: a toast's rule in the tier's colour, at its left

type Bubble = { gui: BillboardGui, pill: Frame, edge: UIStroke, stars: TextLabel, info: TextLabel, piece: Piece?, key: string, alpha: number }
type Piece = { model: Model, distance: number, bubble: Bubble?, seen: boolean, toasted: boolean }

local pieces: { Piece } = {}
local byModel: { [Instance]: Piece } = {}
local bubbles: { Bubble } = {}
local started = false
local carrying: number? = nil -- the spot your character carries (its MoveCarry), as last looked at
local dropped: { spot: number, at: number }? = nil -- a piece that just left your hands: loaded or set down?
local queue: { { rarity: string, name: string, value: number } } = {}
local toastAt = -math.huge
local toastOrder = 0
local shown: { Instance } = {} -- the toasts on screen, the oldest first

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function widthOf(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 100))
	end)
	return math.ceil(if ok and bounds then bounds.X else #text * size * 0.55) + 2
end

-- ── A piece's loot (the server's attributes) ───────────────────────────────

local function rarityOf(model: Model): string
	local raw = model:GetAttribute("Rarity")
	return if type(raw) == "string" then raw else "common"
end

local function valueOf(model: Model): number
	local raw = model:GetAttribute("Value")
	return if type(raw) == "number" then raw else 0
end

local function nameOf(model: Model): string
	local id = model:GetAttribute("FurnitureId")
	local def = if type(id) == "string" then (FurnitureLooks.Items :: any)[id] else nil
	return if def and type(def.name) == "string" then def.name else model.Name
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- The piece of `spot` nearest to you (within `reach` studs), nil for none.
local function pieceAt(spot: number, reach: number): Piece?
	local root = myRoot()
	if not root then
		return nil
	end
	local best: Piece? = nil
	local bestD = reach
	for _, piece in pieces do
		local part = piece.model.PrimaryPart
		if part and piece.model:GetAttribute("MoveSpot") == spot then
			local d = (part.Position - root.Position).Magnitude
			if d <= bestD then
				best, bestD = piece, d
			end
		end
	end
	return best
end

-- ── The bubbles ────────────────────────────────────────────────────────────

local function newBubble(): Bubble?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Ui.make("BillboardGui", {
		Name = "LootStars",
		ResetOnSpawn = false,
		Enabled = false,
		AlwaysOnTop = false, -- (never through a wall)
		LightInfluence = 0,
		Size = UDim2.fromOffset(40, S.Tall),
		MaxDistance = DeviceBudget.range(S.Range),
	}, playerGui)
	local pill = Ui.make("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}, gui)
	Ui.corner(pill, math.floor(S.Tall / 2))
	local edge = Ui.make("UIStroke", { Name = "Edge", Color = K.line, Thickness = 1, Transparency = EDGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	local stars = Ui.label(pill, "", UDim2.new(0, 10, 1, 0), {
		Name = "Stars",
		Position = UDim2.fromOffset(S.Pad, 0),
		Font = Theme.HeadingFont,
		TextSize = S.Text,
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local info = Ui.label(pill, "", UDim2.new(0, 10, 1, 0), {
		Name = "Info",
		Position = UDim2.fromOffset(S.Pad, 0),
		Font = Theme.HeadingFont,
		TextSize = S.Detail,
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	})
	local bubble: Bubble = { gui = gui, pill = pill, edge = edge, stars = stars, info = info, piece = nil, key = "", alpha = -1 }
	table.insert(bubbles, bubble)
	return bubble
end

local function freeBubble(bubble: Bubble)
	local piece = bubble.piece
	if piece then
		piece.bubble = nil
		bubble.piece = nil
	end
	bubble.gui.Enabled = false
	(bubble.gui :: any).Adornee = nil
	bubble.key = ""
end

-- Its words (the stars; near: the tier's name and the value too), sized to them, only when they changed.
local function words(bubble: Bubble, model: Model, near: boolean)
	local rarity, value = rarityOf(model), valueOf(model)
	local key = `{rarity}|{value}|{near}`
	if key == bubble.key then
		return
	end
	bubble.key, bubble.alpha = key, -1
	local color = rgb(LootRules.color(rarity))
	local stars = LootRules.stars(rarity)
	local starW = widthOf(stars, S.Text, Theme.HeadingFont)
	bubble.stars.Text = stars
	bubble.stars.TextColor3 = color
	bubble.stars.Size = UDim2.new(0, starW, 1, 0)
	bubble.edge.Color = color
	local width = S.Pad + starW + S.Pad
	bubble.info.Visible = near
	if near then
		local text = LootRules.info(rarity, value)
		local infoW = widthOf(text, S.Detail, Theme.HeadingFont)
		bubble.info.Text = text
		bubble.info.Position = UDim2.fromOffset(S.Pad + starW + GAP, 0)
		bubble.info.Size = UDim2.new(0, infoW, 1, 0)
		width += GAP + infoW
	end
	bubble.gui.Size = UDim2.fromOffset(width, S.Tall)
end

-- Its fade (`alpha`: 0 as drawn … 1 gone).
local function fadeTo(bubble: Bubble, alpha: number)
	if math.abs(alpha - bubble.alpha) < 0.02 then
		return
	end
	bubble.alpha = alpha
	local base = Theme.PanelTransparency
	bubble.pill.BackgroundTransparency = base + (1 - base) * alpha
	bubble.edge.Transparency = EDGE + (1 - EDGE) * alpha
	bubble.stars.TextTransparency = alpha
	bubble.info.TextTransparency = alpha
end

local function show(bubble: Bubble, piece: Piece, root: BasePart)
	if bubble.gui.Adornee ~= root then
		bubble.gui.Adornee = root
	end
	local offset = Vector3.new(0, root.Size.Y / 2 + S.Lift, 0)
	if bubble.gui.StudsOffsetWorldSpace ~= offset then
		bubble.gui.StudsOffsetWorldSpace = offset
	end
	local alpha, near = LootRules.fade(piece.distance, DeviceBudget.range(1)) -- (a phone: its shorter reach)
	words(bubble, piece.model, near)
	fadeTo(bubble, alpha)
	local on = alpha < 0.999
	if bubble.gui.Enabled ~= on then
		bubble.gui.Enabled = on
	end
end

-- ── The toasts ─────────────────────────────────────────────────────────────

-- The HUD's column (client/Hud.luau topSlot "loot": under its toasts, scaled with it), else a ScreenGui of its own.
local slot: Instance? = nil
local function column(): Instance?
	local found = slot
	if found and found.Parent then
		return found
	end
	local ok, hud = pcall(function(): any
		return require(script.Parent.Hud)
	end)
	if ok and type(hud) == "table" and type(hud.topSlot) == "function" then
		local made, frame = pcall(hud.topSlot, "loot")
		if made and frame then
			slot = frame
			return frame
		end
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Ui.make("ScreenGui", { Name = "LootToasts", ResetOnSpawn = false, DisplayOrder = 2 }, playerGui)
	local frame = Ui.make("Frame", { Name = "Column", Size = UDim2.fromOffset(T.Width, 0), Position = UDim2.fromOffset(16, 120), BackgroundTransparency = 1 }, gui)
	slot = frame
	return frame
end

local function strip(parent: Instance, rarity: string, name: string, value: number): Frame
	local color = rgb(LootRules.color(rarity))
	toastOrder += 1
	local frame = Ui.make("Frame", {
		Name = "LootToast",
		Size = UDim2.fromOffset(T.Width, TOAST_H),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		LayoutOrder = toastOrder,
	}, parent)
	frame:SetAttribute("Rarity", rarity)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, RULE, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, frame)
	-- "+ RARE" (the tier's colour) · the name (white, shortened to fit) · ★★★ (the tier's colour) · $450 (money green)
	local head = `+ {LootRules.tierName(rarity)}`
	local stars = LootRules.stars(rarity)
	local money = LootRules.money(value)
	local size = T.Text
	local headW = widthOf(head, size, Theme.HeadingFont)
	local starW = widthOf(stars, size, Theme.HeadingFont)
	local moneyW = widthOf(money, size, Theme.HeadingFont)
	local pad = 10
	local nameW = math.max(24, math.min(widthOf(name, size, Theme.Font), T.Width - RULE - 2 * pad - headW - starW - moneyW - 3 * GAP))
	local width = RULE + pad + headW + GAP + nameW + GAP + starW + GAP + moneyW + pad
	frame.Size = UDim2.fromOffset(math.min(width, T.Width), TOAST_H)
	local x = RULE + pad
	local function part(text: string, w: number, ink: Color3, font: Enum.Font, label: string)
		Ui.label(frame, text, UDim2.new(0, w, 1, 0), {
			Name = label,
			Position = UDim2.fromOffset(x, 0),
			Font = font,
			TextSize = size,
			TextColor3 = ink,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		x += w + GAP
	end
	part(head, headW, color, Theme.HeadingFont, "Head")
	part(name, nameW, K.text, Theme.Font, "PieceName")
	part(stars, starW, color, Theme.HeadingFont, "Stars")
	part(money, moneyW, Theme.Colors.money, Theme.HeadingFont, "Value")
	return frame
end

local function release()
	if #queue == 0 or os.clock() - toastAt < T.Gap then
		return
	end
	local parent = column()
	if not parent then
		return
	end
	local next = table.remove(queue, 1) :: { rarity: string, name: string, value: number }
	toastAt = os.clock()
	while #shown >= T.Most do
		local oldest = table.remove(shown, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local frame = strip(parent, next.rarity, next.name, next.value)
	frame.Position = UDim2.fromOffset(0, #shown * (TOAST_H + 4)) -- (the HUD's column lays them out itself)
	table.insert(shown, frame)
	local sound = if LootRules.sparkles(next.rarity) then LootRules.sound(next.rarity) else nil
	if sound then
		pcall(function()
			(require(script.Parent.Sounds) :: any).play(sound[1], sound[2], sound[3])
		end)
	end
	task.delay(T.Seconds, function()
		local at = table.find(shown, frame)
		if at then
			table.remove(shown, at)
		end
		frame:Destroy()
	end)
end

function LootStars.toast(rarity: string, name: string, value: number)
	table.insert(queue, { rarity = rarity, name = name, value = value })
	while #queue > T.Most + 1 do
		table.remove(queue, 1) -- (a burst: the latest wait, the oldest go)
	end
	release()
end

-- A piece you picked up or loaded: its toast, once (Toast.From's tier or better).
local function told(piece: Piece)
	if piece.toasted then
		return
	end
	piece.toasted = true
	local rarity = rarityOf(piece.model)
	if LootRules.toasted(rarity) then
		LootStars.toast(rarity, nameOf(piece.model), valueOf(piece.model))
	end
end

-- Is the piece welded into a van (its root's weld holds a part that is no character's)?
local function loaded(piece: Piece): boolean
	local root = piece.model.PrimaryPart
	if not root then
		return false
	end
	for _, child in root:GetChildren() do
		if child:IsA("WeldConstraint") then
			local holder = (child :: WeldConstraint).Part0
			local owner = if holder then holder:FindFirstAncestorOfClass("Model") else nil
			if holder and not (owner and owner:FindFirstChildOfClass("Humanoid")) then
				return true
			end
		end
	end
	return false
end

-- Your hands: a piece picked up (its toast), a piece just out of them (loaded: its toast).
local function hands()
	local character = player.Character
	local raw = if character then character:GetAttribute("MoveCarry") else nil
	local now: number? = if type(raw) == "number" then raw else nil
	if now ~= carrying then
		if carrying ~= nil then
			dropped = { spot = carrying, at = os.clock() }
		end
		carrying = now
		if now ~= nil then
			local piece = pieceAt(now, 15)
			if piece then
				told(piece)
			end
		end
	end
	local out = dropped
	if out then
		local piece = pieceAt(out.spot, 30)
		if piece and loaded(piece) then
			told(piece)
			dropped = nil
		elseif os.clock() - out.at > 2 then
			dropped = nil -- (set down, or out of sight: no load)
		end
	end
end

-- ── The first sight ────────────────────────────────────────────────────────

local function inSight(piece: Piece, eye: Vector3, root: BasePart): boolean
	local ok, hit = pcall(function(): any
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: any }
		return workspace:Raycast(eye, root.Position - eye, params)
	end)
	if not ok then
		return false
	end
	return hit == nil or (hit.Instance ~= nil and hit.Instance:IsDescendantOf(piece.model))
end

local function sparkle(piece: Piece, root: BasePart)
	local rarity = rarityOf(piece.model)
	local color = rgb(LootRules.color(rarity))
	pcall(function()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "LootSparkle"
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(1.5, 3.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.35, 0)
		emitter.Rate = 10
		emitter.Parent = root
		emitter:Emit(14)
		task.delay(SP.Seconds, function()
			emitter.Enabled = false
			task.delay(1, function()
				emitter:Destroy()
			end)
		end)
	end)
	local sound = LootRules.sound(rarity)
	if sound then
		pcall(function()
			local Sounds = require(script.Parent.Sounds) :: any
			if type(Sounds.playAt) == "function" then
				Sounds.playAt(sound[1], root.Position, sound[2], sound[3])
			else
				Sounds.play(sound[1], sound[2], sound[3])
			end
		end)
	end
end

-- ── One look ───────────────────────────────────────────────────────────────

function LootStars.step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local covered = LootStars.covered
	local hidden = false
	if covered then
		local ok, value = pcall(covered)
		hidden = ok and value == true
	end
	local range = DeviceBudget.range(S.Range)
	local see = DeviceBudget.range(SP.See)
	local character = player.Character
	local mine = if character then character:GetAttribute("MoveCarry") else nil
	local me = myRoot()
	local near: { Piece } = {}
	for _, piece in pieces do
		local root = piece.model.PrimaryPart
		piece.distance = if root then (root.Position - eye).Magnitude else math.huge
		if root and piece.distance <= range then
			-- (not over the piece in your own hands)
			local held = mine ~= nil and piece.model:GetAttribute("MoveSpot") == mine and me ~= nil and (root.Position - me.Position).Magnitude < 12
			if not held then
				table.insert(near, piece)
			end
			if not piece.seen and piece.distance <= see and piece.model:GetAttribute("MoveSpot") ~= nil and LootRules.sparkles(rarityOf(piece.model)) then
				if root:FindFirstChildOfClass("WeldConstraint") then
					piece.seen = true -- (first seen in somebody's hands or in a van: no longer where the house held it)
				elseif inSight(piece, eye, root) then
					piece.seen = true
					sparkle(piece, root)
				end
			end
		end
	end
	table.sort(near, function(a: Piece, b: Piece): boolean
		return a.distance < b.distance
	end)
	local most = if hidden then 0 else DeviceBudget.count(S.Count)
	local chosen: { [Piece]: boolean } = {}
	for index = 1, math.min(most, #near) do
		chosen[near[index]] = true
	end
	for _, bubble in bubbles do
		local piece = bubble.piece
		if piece and not chosen[piece] then
			freeBubble(bubble)
		end
	end
	for piece in chosen do
		local bubble = piece.bubble
		if not bubble then
			for _, free in bubbles do
				if free.piece == nil then
					bubble = free
					break
				end
			end
			bubble = bubble or newBubble()
			if bubble then
				bubble.piece = piece
				piece.bubble = bubble
			end
		end
		local root = piece.model.PrimaryPart
		if bubble and root then
			show(bubble, piece, root)
		end
	end
	hands()
	release()
end

function LootStars.bubbles(): { BillboardGui }
	local out: { BillboardGui } = {}
	for _, bubble in bubbles do
		if bubble.piece and bubble.gui.Enabled then
			table.insert(out, bubble.gui)
		end
	end
	return out
end

-- ── The pieces ─────────────────────────────────────────────────────────────

local function add(instance: Instance)
	if not instance:IsA("Model") or byModel[instance] then
		return
	end
	local piece: Piece = { model = instance :: Model, distance = math.huge, bubble = nil, seen = false, toasted = false }
	byModel[instance] = piece
	table.insert(pieces, piece)
end

local function drop(instance: Instance)
	local piece = byModel[instance]
	if not piece then
		return
	end
	byModel[instance] = nil
	local at = table.find(pieces, piece)
	if at then
		table.remove(pieces, at)
	end
	local bubble = piece.bubble
	if bubble then
		freeBubble(bubble)
	end
end

function LootStars.start()
	if started then
		return
	end
	started = true
	local tag = Config.Loot.Tag
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(drop)
	task.spawn(function()
		while true do
			local ok, err = pcall(LootStars.step :: any)
			if not ok then
				warn(`[LootStars] {err}`)
			end
			task.wait(S.Every)
		end
	end)
end

return LootStars
