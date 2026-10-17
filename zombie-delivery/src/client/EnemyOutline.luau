--!strict
-- 6.15, the owner: "I'd outline the zombies: a red outline, but just subtle." A thin outline on the nearest living
-- zombies of a run on this client: red (orange for a kind Config.Outline.HumanKinds names a person; Config.Outline).
-- Cosmetic only, the server knows nothing of it.
--   * A Roblox Highlight per outlined zombie (Adornee = its model): no fill (FillTransparency 1), the outline at
--     Config.Outline.Transparency, DepthMode Occluded (only the part you can see is outlined, never through walls).
--   * Roblox draws at most 31 Highlights on a client, so this keeps a pool of at most Config.Outline.Count (made as
--     needed, never destroyed, an unused one disabled with no Adornee) in a local folder (workspace.EnemyOutlines) and
--     hands them out every Config.Outline.Every seconds to the nearest living zombies within Range of the camera
--     (shared/OutlinePick.luau: one already outlined keeps it a little farther, nothing blinks at the edge). A phone
--     gets fewer and nearer ones (client/DeviceBudget.luau, Config.Performance.Lite).
--   * The zombies are a list kept by the Zombies folder's ChildAdded / ChildRemoved (the models that stream in and out
--     too), their humanoid and root looked up once: no GetDescendants, no GetChildren per pick. Only that folder:
--     never a player, Danny, a helper or a visitor.
--   * Dead is dead at once: the outlined one's Humanoid Health reaching 0 takes the outline off before the next pick,
--     so the falling corpses never wear one.
--   * 9.x loot: one budget with the loot's outlines (client/LootOutline.luau, shared/OutlinePick.luau BUDGET): the
--     zombies come first. EnemyOutline.drawn() says how many zombies wear one now (the loot takes what is left), and
--     before a pick outlines more of them EnemyOutline.onSqueeze(count) (LootOutline.squeeze) takes loot outlines off
--     first, so the two together never pass Roblox's 31 less Config.Outline.Spare.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OutlinePick = require(Shared:WaitForChild("OutlinePick"))
local DeviceBudget = require(script.Parent.DeviceBudget)

local EnemyOutline = {}

local Tuning = Config.Outline
local RETRY = 0.5 -- seconds between new lookups of a body still missing its humanoid or root

type Slot = { highlight: Highlight, enemy: Enemy?, death: RBXScriptConnection? }
type Enemy = {
	model: Model,
	entry: OutlinePick.Entry, -- what OutlinePick sees of it (kept, filled again every pick)
	humanoid: Humanoid?,
	root: BasePart?,
	retry: number, -- a missing humanoid or root is looked up again from then on
	slot: Slot?, -- its outline, while it has one
}

local enemies: { Enemy } = {}
local byModel: { [Model]: Enemy } = {}
local slots: { Slot } = {}
local entries: { OutlinePick.Entry } = {} -- this pick's entries …
local order: { Enemy } = {} -- … and their enemies, in the same order
local folder: Folder? = nil
local started = false
local nextPick = 0

-- 9.x loot: the loot's outlines make room before more enemies are outlined (client/LootOutline.luau sets it).
EnemyOutline.onSqueeze = nil :: ((number) -> ())?

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local COLORS = {
	zombie = rgb(OutlinePick.color("zombie")),
	human = rgb(OutlinePick.color("human")),
}

-- The body's humanoid and root, looked up once and kept while still inside.
local function partsOf(enemy: Enemy, now: number): (Humanoid?, BasePart?)
	local model = enemy.model
	local humanoid, root = enemy.humanoid, enemy.root
	if humanoid and root and humanoid.Parent == model and root.Parent == model then
		return humanoid, root
	end
	if now < enemy.retry then
		return nil, nil
	end
	enemy.retry = now + RETRY
	local foundHumanoid = model:FindFirstChildOfClass("Humanoid")
	local found = model:FindFirstChild("HumanoidRootPart")
	local foundRoot = if found and found:IsA("BasePart") then found else nil
	enemy.humanoid, enemy.root = foundHumanoid, foundRoot
	return foundHumanoid, foundRoot
end

-- The pool's local folder (in the workspace: a Highlight renders there; this client's only, never streamed).
local function holder(): Folder
	local made = folder
	if made and made.Parent == workspace then
		return made
	end
	local fresh = Instance.new("Folder")
	fresh.Name = "EnemyOutlines"
	fresh.Parent = workspace
	folder = fresh
	return fresh
end

-- The outline comes off (its Highlight back in the pool).
local function release(slot: Slot)
	local death = slot.death
	if death then
		death:Disconnect()
		slot.death = nil
	end
	local enemy = slot.enemy
	if enemy then
		enemy.slot = nil
		enemy.entry.outlined = false
		slot.enemy = nil
	end
	slot.highlight.Enabled = false
	slot.highlight.Adornee = nil
end

-- A free Highlight: an unused one, or a new one while the pool is under the limit.
local function freeSlot(): Slot?
	for index = #slots, 1, -1 do
		local slot = slots[index]
		if not slot.highlight.Parent then
			-- (destroyed with its folder by something else: forgotten, a new one is made)
			release(slot)
			table.remove(slots, index)
		elseif not slot.enemy then
			return slot
		end
	end
	if #slots >= OutlinePick.limit then
		return nil
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "EnemyOutline"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- never through walls
	highlight.FillTransparency = 1 -- no fill: an outline only
	highlight.OutlineTransparency = Tuning.Transparency
	highlight.Enabled = false
	highlight.Parent = holder()
	local slot: Slot = { highlight = highlight, enemy = nil, death = nil }
	table.insert(slots, slot)
	return slot
end

local function assign(enemy: Enemy)
	local slot = freeSlot()
	if not slot then
		return
	end
	slot.enemy = enemy
	enemy.slot = slot
	enemy.entry.outlined = true
	local highlight = slot.highlight
	highlight.OutlineColor = if enemy.entry.human then COLORS.human else COLORS.zombie
	highlight.Adornee = enemy.model
	highlight.Enabled = true
	-- Its death takes the outline off at once (not at the next pick): no outline on a falling corpse.
	local humanoid = enemy.humanoid
	if humanoid then
		slot.death = humanoid.HealthChanged:Connect(function(health: number)
			if slot.enemy == enemy and health <= 0 then
				release(slot)
			end
		end)
	end
end

-- Every Tuning.Every seconds: the nearest living enemies within range wear the outlines.
local function pick()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	table.clear(entries)
	table.clear(order)
	for _, enemy in enemies do
		local humanoid, root = partsOf(enemy, now)
		local entry = enemy.entry
		if root then
			entry.distance = (root.Position - eye).Magnitude
			entry.alive = humanoid ~= nil and humanoid.Health > 0
		else
			entry.distance = math.huge
			entry.alive = false
		end
		table.insert(entries, entry)
		table.insert(order, enemy)
	end
	local chosen = OutlinePick.choose(entries, DeviceBudget.count(Tuning.Count), DeviceBudget.range(Tuning.Range))
	-- Off first (their Highlights go back to the pool), then on.
	for index, enemy in order do
		local slot = enemy.slot
		if slot and chosen[index] == nil then
			release(slot)
		end
	end
	-- 9.x loot: the loot's outlines make room for these first (one budget, the enemies before the loot)
	local squeeze = EnemyOutline.onSqueeze
	if squeeze then
		local count = 0
		for _ in chosen do
			count += 1
		end
		pcall(squeeze, count)
	end
	for index in chosen do
		local enemy = order[index]
		if not enemy.slot then
			assign(enemy)
		end
	end
end

-- ── The enemies ────────────────────────────────────────────────────────────

local function add(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local model = child :: Model
	if byModel[model] then
		return
	end
	local kind = model:GetAttribute("Zombie")
	local tone: OutlinePick.Tone = OutlinePick.tone(if type(kind) == "string" then kind else nil)
	local enemy: Enemy = {
		model = model,
		entry = { distance = math.huge, alive = false, human = tone == "human", outlined = false },
		humanoid = nil,
		root = nil,
		retry = 0,
		slot = nil,
	}
	byModel[model] = enemy
	table.insert(enemies, enemy)
end

-- Gone from its folder (destroyed, or streamed out): forgotten, its outline back in the pool.
local function drop(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local model = child :: Model
	local enemy = byModel[model]
	if not enemy then
		return
	end
	byModel[model] = nil
	local at = table.find(enemies, enemy)
	if at then
		table.remove(enemies, at)
	end
	local slot = enemy.slot
	if slot then
		release(slot)
	end
end

-- The folder of zombies (made by the server, maybe after this client starts).
local function watch(name: string)
	local function hook(found: Instance)
		for _, child in found:GetChildren() do
			add(child)
		end
		found.ChildAdded:Connect(add)
		found.ChildRemoved:Connect(drop)
	end
	local found = workspace:FindFirstChild(name)
	if found then
		hook(found)
		return
	end
	local waiting: RBXScriptConnection? = nil
	waiting = workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == name and waiting then
			waiting:Disconnect()
			waiting = nil
			hook(child)
		end
	end)
end

-- ── The budget ────────────────────────────────────────────────────────────

-- 9.x loot: the enemies wearing an outline now (the shared budget: the loot takes what is left).
function EnemyOutline.drawn(): number
	local count = 0
	for _, slot in slots do
		if slot.enemy then
			count += 1
		end
	end
	return count
end

function EnemyOutline.start()
	if started then
		return
	end
	started = true
	watch("Zombies")
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextPick then
			return
		end
		nextPick = now + Tuning.Every
		pick()
	end)
end

return EnemyOutline
