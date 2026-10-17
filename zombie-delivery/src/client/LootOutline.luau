--!strict
-- 9.x LOOT (the owner: "for the loot I'd make outlines with their own colour by how rare it is"; Config.Loot.Outline):
-- every piece with a rarity near you wears an outline in its tier's colour, in a house, in your hands, in the van and on
-- the warehouse's stands. The server decides the rarity (server/Loot.luau, server/Warehouse.luau: the model's Rarity
-- attribute and the CollectionService tag Config.Loot.Tag); this only shows it, on this client.
--   * A Roblox Highlight per outlined piece (Adornee = its model): OutlineColor and FillColor the tier's colour, a soft
--     fill (FillTransparency Outline.Fill), the edge at Outline.Edge, DepthMode Occluded (only what you can see of it:
--     never through a wall). A Common wears none (Outline.Common false: most of a house is Common, and their outlines
--     would spend the budget and drown the colours that mean something; its ★ still shows when near,
--     client/LootStars.luau); with Common true it wears a faint grey-white one (Outline.Faint).
--   * One budget with the enemies' outlines (client/EnemyOutline.luau): Roblox draws at most 31 Highlights on a client,
--     so the pick (shared/OutlinePick.luau loot) takes at most Outline.Count (a phone: DeviceBudget's share) and never
--     past 31 − Config.Outline.Spare − the enemies outlined now (EnemyOutline.drawn); before more enemies are outlined,
--     EnemyOutline asks LootOutline.squeeze to take the least of the loot's off first. The rarest first, then the
--     nearest, within Outline.Range of the camera (a phone: DeviceBudget.range); one outlined keeps it a little farther
--     (HoldRange): nothing blinks at the edge.
--   * Performance: the pieces are a list kept by the tag's added / removed signals (the models that stream in and out
--     too), their root looked up once; picked again every Outline.Every s (no GetDescendants, nothing per frame); a pool
--     of Highlights made as needed, never destroyed, an unused one disabled with no Adornee.
--   LootOutline.start()          listens (once; client/Main.client.luau starts it in the sandbox)
--   LootOutline.drawn()          the pieces wearing an outline now
--   LootOutline.squeeze(enemies) the least of the loot's outlines off until the budget holds `enemies` enemies too
--   LootOutline.setOn(on) / isOn() / toggle()   on or off on this client (off: every loot outline off at once)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local OutlinePick = require(Shared.OutlinePick)
local LootRules = require(Shared.LootRules)
local DeviceBudget = require(script.Parent.DeviceBudget)
local EnemyOutline = require(script.Parent.EnemyOutline)

local LootOutline = {}

local O = Config.Loot.Outline

type Slot = { highlight: Highlight, piece: Piece? }
type Piece = {
	model: Model,
	rarity: string, -- the model's Rarity attribute (read again when it changes)
	entry: OutlinePick.LootEntry, -- what OutlinePick sees of it (kept, filled again every pick)
	slot: Slot?, -- its outline, while it has one
}

local pieces: { Piece } = {}
local byModel: { [Instance]: Piece } = {}
local slots: { Slot } = {}
local entries: { OutlinePick.LootEntry } = {} -- this pick's entries …
local order: { Piece } = {} -- … and their pieces, in the same order
local folder: Folder? = nil
local on = true
local started = false
local nextPick = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The tier's colour (a Common's: the faint grey-white, when Commons wear one).
local function colorOf(rarity: string): Color3
	return if LootRules.rank(rarity) <= 1 then rgb(O.Faint) else rgb(LootRules.color(rarity))
end

-- The pool's local folder (in the workspace: a Highlight renders there; this client's only).
local function holder(): Folder
	local made = folder
	if made and made.Parent == workspace then
		return made
	end
	local fresh = Instance.new("Folder")
	fresh.Name = "LootOutlines"
	fresh.Parent = workspace
	folder = fresh
	return fresh
end

local function release(slot: Slot)
	local piece = slot.piece
	if piece then
		piece.slot = nil
		piece.entry.outlined = false
		slot.piece = nil
	end
	slot.highlight.Enabled = false
	slot.highlight.Adornee = nil
end

-- A free Highlight: an unused one, or a new one while the pool is under the shared budget.
local function freeSlot(): Slot?
	for index = #slots, 1, -1 do
		local slot = slots[index]
		if not slot.highlight.Parent then
			release(slot)
			table.remove(slots, index)
		elseif not slot.piece then
			return slot
		end
	end
	if #slots >= OutlinePick.BUDGET then
		return nil
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "LootOutline"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- never through walls
	highlight.FillTransparency = O.Fill
	highlight.OutlineTransparency = O.Edge
	highlight.Enabled = false
	highlight.Parent = holder()
	local slot: Slot = { highlight = highlight, piece = nil }
	table.insert(slots, slot)
	return slot
end

local function paint(slot: Slot, piece: Piece)
	local color = colorOf(piece.rarity)
	local highlight = slot.highlight
	if highlight.OutlineColor ~= color then
		highlight.OutlineColor = color
		highlight.FillColor = color
	end
end

local function assign(piece: Piece)
	local slot = freeSlot()
	if not slot then
		return
	end
	slot.piece = piece
	piece.slot = slot
	piece.entry.outlined = true
	paint(slot, piece)
	slot.highlight.Adornee = piece.model
	slot.highlight.Enabled = true
end

local function rarityOf(model: Model): string
	local raw = model:GetAttribute("Rarity")
	return if type(raw) == "string" then raw else "common"
end

-- Every Outline.Every s: the rarest, then the nearest pieces within range wear the outlines (what the enemies leave).
local function pick()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	table.clear(entries)
	table.clear(order)
	for _, piece in pieces do
		local root = piece.model.PrimaryPart
		local entry = piece.entry
		entry.distance = if root then (root.Position - eye).Magnitude else math.huge
		entry.rank = LootRules.rank(piece.rarity)
		table.insert(entries, entry)
		table.insert(order, piece)
	end
	local chosen = OutlinePick.loot(entries, DeviceBudget.count(O.Count), DeviceBudget.range(O.Range), EnemyOutline.drawn())
	for index, piece in order do
		local slot = piece.slot
		if slot and not chosen[index] then
			release(slot)
		end
	end
	for index in chosen do
		local piece = order[index]
		local slot = piece.slot
		if slot then
			paint(slot, piece) -- (its rarity may have changed: the colour follows)
		else
			assign(piece)
		end
	end
end

-- ── The pieces ─────────────────────────────────────────────────────────────

local function add(instance: Instance)
	if not instance:IsA("Model") or byModel[instance] then
		return
	end
	local model = instance :: Model
	local piece: Piece = { model = model, rarity = rarityOf(model), entry = { distance = math.huge, rank = 1, outlined = false }, slot = nil }
	byModel[model] = piece
	table.insert(pieces, piece)
	model:GetAttributeChangedSignal("Rarity"):Connect(function()
		piece.rarity = rarityOf(model)
	end)
	nextPick = 0 -- (a piece streamed in or made: outlined at the next frame)
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
	local slot = piece.slot
	if slot then
		release(slot)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

function LootOutline.drawn(): number
	local count = 0
	for _, slot in slots do
		if slot.piece then
			count += 1
		end
	end
	return count
end

-- Before `enemies` enemies are outlined (client/EnemyOutline.luau onSqueeze): the least of the loot's outlines come
-- off until the shared budget holds both (the plainest first, then the farthest).
function LootOutline.squeeze(enemies: number)
	local room = OutlinePick.room(enemies, DeviceBudget.count(O.Count))
	local worn: { Slot } = {}
	for _, slot in slots do
		if slot.piece then
			table.insert(worn, slot)
		end
	end
	if #worn <= room then
		return
	end
	table.sort(worn, function(a: Slot, b: Slot): boolean
		local pa, pb = a.piece :: Piece, b.piece :: Piece
		if pa.entry.rank ~= pb.entry.rank then
			return pa.entry.rank < pb.entry.rank
		end
		return pa.entry.distance > pb.entry.distance
	end)
	for index = 1, #worn - room do
		release(worn[index])
	end
end

function LootOutline.isOn(): boolean
	return on
end

function LootOutline.setOn(value: boolean)
	on = value
	if not on then
		for _, slot in slots do
			release(slot)
		end
	end
	nextPick = 0
end

function LootOutline.toggle(): boolean
	LootOutline.setOn(not on)
	return on
end

function LootOutline.start()
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
	EnemyOutline.onSqueeze = LootOutline.squeeze
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if not on or now < nextPick then
			return
		end
		nextPick = now + O.Every
		local ok, err = pcall(pick :: any)
		if not ok then
			warn(`[LootOutline] {err}`)
		end
	end)
end

return LootOutline
