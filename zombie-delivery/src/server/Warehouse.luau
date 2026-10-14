--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on every player plot. Builds each plot's
-- building from shared/WarehouseLayout.luau (anchored parts: corrugated metal walls, the roof, the open roller door,
-- the hall's lights, the concrete floor's paint, the ZDC sign, the owner's sign, the STOCK board, the display stands
-- and the UNLOAD HERE bay outside) and keeps it in step with its owner (SandboxPlots) and their collection
-- (server/Collection.luau):
--   * the owner's sign over the door: "<Name>'s Warehouse", or FOR RENT on a free plot;
--   * every display stand: its number plate, the piece on show as its 3D model (FurnitureLooks.build, dressed by
--     FurnitureMesh in the owner's Blender look once imported; anchored, in the podium's middle, looking along the
--     stand's yaw to its aisle) and a tag over it (its name in its rarity's colour, "+$X/min");
--   * the stands' prompts, for the owner only (tagged like a job's prompt: client/CargoPrompts.luau hides them from
--     everybody else, and the server checks who used one): an empty stand's "Display" (E) asks the owner's client to
--     pick a piece of the stock (Collection.openPicker); a full one's "Take down" (E, Collection.undisplay) and "Sell"
--     (hold F, Collection.sell). The answers go out as Notices (the client's toasts); a sale's own message is the
--     collection's ("sold");
--   * the STOCK board inside: "📦 N pieces in stock · $X/min" and how many stands are on show;
--   * 8.1, the upgrades: the hall has WarehouseLayout.capacity(level) stands; the owner's first Collection.stands of
--     them stand there (the level's big ones and the More stands bought), the others are only their painted spot
--     (their podium, top and plate hidden and not solid, no prompts); the tags' $/min are × the owner's Showroom
--     lights (Collection.boost); the UPGRADES desk has the owner's "Upgrades" prompt (E: Upgrades.open, the window
--     client/UpgradeUi.luau; somebody else's use gets a notice, as at the stands) on the desk's front, the way the
--     layout turns it;
--   * 8.2: the owner's Blender look (server/WarehouseMesh.luau, once ZDCWarehouseArt is imported): the layout's visual
--     pieces carry the attribute WarehouseVisual and are hidden under the model (the solid ones still collide);
--   * 8.3 (design/warehouse-levels/KONTRAKT.md), the warehouse's five levels: each plot is built at its owner's level
--     (UpgradeRules.warehouseLevel of Upgrades.levels: 1 Garage … 5 Logistics Center; a free plot at
--     Config.Warehouse.FreeLevel, the garage FOR RENT) from WarehouseLayout.site(plot, level): that level's own building
--     and stands. When the level changes (a plot claimed or freed, SandboxPlots.onChanged; the owner's save loaded or
--     the ZDC Warehouse upgrade bought, Upgrades.onChanged) the plot's Model is built anew: the old one goes with the
--     pieces it showed, the new one gets the level's stands, desk and signs, the owner's fresh prompts, and refresh puts
--     the pieces back on their stands (a stand keeps its number: a piece on show stays on it). The plot's state (what
--     the prompts' handlers hold) is kept, so the API below always answers for the building there now. The Model has
--     the attribute Level (1 … 5, set before WarehouseMesh dresses it), workspace.Warehouses the attribute
--     Level<plot id> (the clients' copy: client/SandboxGuide.luau, shared/SoundPlan.luau). A rebuild only on a real
--     change of level.
-- A collection's changes (Collection.onChanged) rebuild only the stands whose piece changed, Config.Warehouse.Rebuild
-- apart at most; an owner who leaves takes their pieces with them (the plot is FOR RENT again). Nothing runs per frame.
-- The van's unloading is the moves' (the plot's unload circle); here only its bay is painted.
--
--   Warehouse.start()           builds every plot's warehouse (workspace.Warehouses) and follows owners, their
--                               collections and their warehouse levels
--   Warehouse.model(id)         plot `id`'s warehouse Model (nil before start; 8.3: a new one after a level change)
--   Warehouse.shown(id, i)      the Model on show on that plot's stand i (nil: the stand is empty)
--   Warehouse.terminal(id)      8.1: plot `id`'s UPGRADES desk (its part with the prompt; nil before start)
--   Warehouse.isOpen(id, i)     8.1: does plot `id`'s stand i stand there (the owner has it)?
--   Warehouse.level(id)         8.3: the level plot `id`'s warehouse is built at (1 … 5; nil before start)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FurnitureLooks = require(Shared.FurnitureLooks)
local CollectionRules = require(Shared.CollectionRules)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)
local UpgradeRules = require(Shared.UpgradeRules) -- 8.3: the owner's warehouse level
local WarehouseLayout = require(Shared.WarehouseLayout)
local Collection = require(script.Parent.Collection)
local FurnitureMesh = require(script.Parent.FurnitureMesh)
local SandboxPlots = require(script.Parent.SandboxPlots)
local Upgrades = require(script.Parent.Upgrades) -- 8.1: the UPGRADES desk's window; 8.3: the owner's levels
local WarehouseMesh = require(script.Parent.WarehouseMesh) -- 8.2: the owner's Blender warehouse

local T = Config.Warehouse

local Warehouse = {}

type Shown = { uid: string, item: string, variant: number, model: Model, height: number }
type Prompts = { display: ProximityPrompt, takeDown: ProximityPrompt, sell: ProximityPrompt }
type Stand = {
	index: number,
	podium: BasePart,
	parts: { BasePart }, -- 8.1: its podium, top and plate (hidden while the stand is not the owner's)
	solid: { [BasePart]: boolean }, -- 8.1: which of them collide when it stands there
	open: boolean, -- 8.1: it stands there (one of the owner's Collection.stands)
	anchor: Attachment,
	prompts: Prompts?,
	tag: BillboardGui,
	tagLabels: { TextLabel },
	shown: Shown?,
}
type PlotState = {
	plot: SandboxMap.Plot,
	site: SandboxMap.Plot, -- 8.3: the plot at the level its building is (WarehouseLayout.site: a Site)
	level: number, -- 8.3: 1 … 5
	parent: Instance, -- 8.3: workspace.Warehouses (a rebuilt Model goes there)
	model: Model,
	pieces: Folder,
	stands: { Stand },
	desk: BasePart, -- 8.1: the UPGRADES desk (its prompt's anchor)
	deskPrompt: ProximityPrompt?,
	owner: Player?,
	ownerLabels: { TextLabel },
	stockLabels: { TextLabel },
	pending: boolean,
}

local states: { [number]: PlotState } = {}
local busy: { [Player]: number } = {} -- a player's next prompt use (os.clock): a double press does one thing
local notice = Net.get("Notice")
local started = false

local FONTS: { [string]: Enum.Font } = { Black = Enum.Font.GothamBlack, Bold = Enum.Font.GothamBold, Medium = Enum.Font.GothamMedium }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- ── The building ─────────────────────────────────────────────────────────────

local function faceSize(face: string, size: { number }): (number, number)
	if face == "Left" or face == "Right" then
		return size[3], size[2]
	elseif face == "Top" or face == "Bottom" then
		return size[1], size[3]
	end
	return size[1], size[2]
end

-- Text on one face of a part: the lines one under the other, centred, scaled to fit. Its labels (the signs' are
-- rewritten: setLines).
local function words(part: BasePart, w: WarehouseLayout.Words, size: { number }): { TextLabel }
	local width, height = faceSize(w.face, size)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Words" .. w.face
	gui.Face = (Enum.NormalId :: any)[w.face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.clamp(math.floor(1000 / math.max(width, height, 0.1)), 25, 100)
	gui.LightInfluence = if w.lit then 0 else 0.3
	gui.MaxDistance = math.clamp(Config.Performance.SignPerStud * height, 60, Config.Performance.NameBoardRange)
	gui.Parent = part
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.02, 0)
	list.Parent = gui
	local labels: { TextLabel } = {}
	for index, line in w.lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{index}`
		label.LayoutOrder = index
		label.Size = UDim2.fromScale(0.94, line.size)
		label.BackgroundTransparency = 1
		label.Font = FONTS[line.font or "Medium"] or Enum.Font.GothamMedium
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = rgb(line.color)
		label.Parent = gui
		labels[index] = label
	end
	return labels
end

local function setLines(labels: { TextLabel }, lines: { WarehouseLayout.Line })
	for index, label in labels do
		local line = lines[index]
		label.Text = if line then line.text else ""
		if line then
			label.TextColor3 = rgb(line.color)
		end
	end
end

-- One piece of the layout as an anchored part (its text's labels: the last face's).
local function build(parent: Instance, d: WarehouseLayout.Piece): (BasePart, { TextLabel })
	local p: BasePart = if d.shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = d.name
	p.Size = Vector3.new(d.size[1], d.size[2], d.size[3])
	p.CFrame = CFrame.new(d.at[1], d.at[2], d.at[3])
		* CFrame.Angles(0, math.rad(d.yaw or 0), 0)
		* CFrame.Angles(math.rad(d.pitch or 0), 0, math.rad(d.roll or 0))
	p.Color = rgb(d.color)
	p.Material = (Enum.Material :: any)[d.material]
	p.Anchored = true
	p.CanCollide = d.solid == true
	p.CanQuery = d.solid == true
	p.CanTouch = false
	p.CastShadow = d.shadow == true
	p.Transparency = d.transparency or 0
	p:SetAttribute(WarehouseMesh.Attribute, d.visual) -- 8.2: only looks (WarehouseMesh hides it under the Blender model)
	if p:IsA("Part") then
		if d.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	local labels: { TextLabel } = {}
	local faces = d.words
	if faces then
		for _, w in faces do
			labels = words(p, w, d.size)
		end
	end
	local light = d.light
	if light then
		local lamp = Instance.new("PointLight")
		lamp.Range = light.range
		lamp.Brightness = light.brightness
		lamp.Color = rgb(light.color)
		lamp.Shadows = false
		lamp.Parent = p
	end
	p.Parent = parent
	return p, labels
end

-- A stand's tag over its piece: the name in its rarity's colour, "RARE · +$3/min" (hidden while the stand is empty).
local function makeTag(podium: BasePart): (BillboardGui, { TextLabel })
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Adornee = podium
	tag.Size = UDim2.fromScale(7, 1.6) -- (studs)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	tag.MaxDistance = 48
	tag.LightInfluence = 0
	tag.Enabled = false
	tag.Parent = podium
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = back
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = back
	local labels: { TextLabel } = {}
	for index, share in { 0.52, 0.36 } do
		local label = Instance.new("TextLabel")
		label.Name = `Line{index}`
		label.LayoutOrder = index
		label.Size = UDim2.fromScale(0.92, share)
		label.BackgroundTransparency = 1
		label.Font = if index == 1 then Enum.Font.GothamBold else Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextStrokeTransparency = 0.6
		label.Text = ""
		label.Parent = back
		labels[index] = label
	end
	return tag, labels
end

-- 8.1: a stand the owner has (its podium, top and plate there; the podium and the top solid) or not (only its painted
-- spot shows: nothing to bump into).
local function setOpen(stand: Stand, open: boolean)
	if stand.open == open then
		return
	end
	stand.open = open
	for _, part in stand.parts do
		part.Transparency = if open then 0 else 1
		part.CanCollide = open and stand.solid[part] == true
		part.CanQuery = part.CanCollide
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceGui") then
				child.Enabled = open
			end
		end
	end
end

-- 8.3: where on a part a prompt's anchor goes: at its edge on the side the layout's `look` yaw faces (180 south, 0
-- north, -90 east, 90 west: the way a stand's piece or the desk looks), `out` studs past that face (less than 0:
-- inside it) and `height` over its middle. The part was built turned by its piece's own yaw, so the side is found in
-- the part's frame: a podium or a desk the layout turns keeps its prompt on its front.
local function edge(part: BasePart, partYaw: number, look: number, height: number, out: number): CFrame
	local turn = math.rad(look - partYaw)
	local dx, dz = -math.sin(turn), -math.cos(turn) -- (the look in the part's frame: its LookVector there)
	if math.abs(dx) > math.abs(dz) then
		return CFrame.new(math.sign(dx) * (part.Size.X / 2 + out), height, 0)
	end
	return CFrame.new(0, height, math.sign(dz) * (part.Size.Z / 2 + out))
end

-- 8.3: the level a free plot shows (Config.Warehouse.FreeLevel: the garage FOR RENT).
local function freeLevel(): number
	local want = (T :: any).FreeLevel
	if type(want) ~= "number" or want ~= want then
		return 1
	end
	return math.clamp(math.floor(want), 1, WarehouseLayout.Levels)
end

-- 8.3: the level a plot's warehouse is built at: its owner's (their ZDC Warehouse upgrade; none before their save
-- loads: the garage) or a free plot's.
local function levelFor(owner: Player?): number
	if owner then
		return UpgradeRules.warehouseLevel(Upgrades.levels(owner))
	end
	return freeLevel()
end

-- Builds the plot's building at `level` into its state (8.3: at start, and again whenever the level changes): a new
-- Model under the state's parent with the level's pieces, every stand of the level (open as a free plot's; refresh
-- brings them in step with the owner), the desk, the signs' labels. No prompts and nothing on show yet.
local function buildModel(state: PlotState, level: number)
	local plot = state.plot
	local site = WarehouseLayout.site(plot, level) :: SandboxMap.Plot
	local model = Instance.new("Model")
	model.Name = `Warehouse{plot.id}`
	model:SetAttribute("Plot", plot.id)
	local podiums: { [number]: BasePart } = {}
	local podiumYaws: { [number]: number } = {}
	local standParts: { [number]: { BasePart } } = {}
	local solid: { [BasePart]: boolean } = {}
	local ownerLabels: { TextLabel } = {}
	local stockLabels: { TextLabel } = {}
	local desk: BasePart? = nil
	local deskYaw = 0
	for _, d in WarehouseLayout.pieces(site) do
		local part, labels = build(model, d)
		if d.name == "OwnerSign" then
			ownerLabels = labels
		elseif d.name == "StockBoard" then
			stockLabels = labels
		elseif d.name == "TerminalDesk" then
			desk, deskYaw = part, d.yaw or 0
		end
		if d.stand then
			standParts[d.stand] = standParts[d.stand] or {}
			table.insert(standParts[d.stand], part)
			solid[part] = d.solid == true
			if d.name == `Stand{d.stand}` then
				podiums[d.stand], podiumYaws[d.stand] = part, d.yaw or 0
			end
		end
	end
	local pieces = Instance.new("Folder")
	pieces.Name = "Shown"
	pieces.Parent = model
	local stands: { Stand } = {}
	local open = WarehouseLayout.count(level)
	for i = 1, WarehouseLayout.capacity(level) do
		local podium = podiums[i]
		local spot = WarehouseLayout.stand(site, i) :: WarehouseLayout.Stand
		-- the prompts at the podium's front edge (the aisle its piece looks at), at hand height
		local anchor = Instance.new("Attachment")
		anchor.Name = "Prompts"
		anchor.CFrame = edge(podium, podiumYaws[i] or 0, spot.yaw, 1.6, -0.3) -- (its offset in the podium)
		anchor.Parent = podium
		local tag, tagLabels = makeTag(podium)
		local stand: Stand = { index = i, podium = podium, parts = standParts[i] or { podium }, solid = solid, open = true, anchor = anchor, prompts = nil, tag = tag, tagLabels = tagLabels, shown = nil }
		setOpen(stand, i <= open) -- (an upgrade stand: its spot only, until an owner has it)
		stands[i] = stand
	end
	-- 8.1: the UPGRADES desk's prompt at its front edge (the hall it faces: WarehouseLayout.terminal's yaw), at hand height
	local terminal = desk :: BasePart
	local deskAnchor = Instance.new("Attachment")
	deskAnchor.Name = "Prompts"
	deskAnchor.CFrame = edge(terminal, deskYaw, WarehouseLayout.terminal(site).yaw, 0.6, 0.2)
	deskAnchor.Parent = terminal
	model.WorldPivot = CFrame.new(site.warehouse.x, 0, site.warehouse.z)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- 8.2 perf: with StreamingEnabled the hall streams whole
	model:SetAttribute("Level", level) -- 8.3 (before the dress: WarehouseMesh.level reads it)
	WarehouseMesh.dress(model) -- 8.2: the owner's Blender look, once imported (no import: as built)
	model.Parent = state.parent
	state.parent:SetAttribute(`Level{plot.id}`, level) -- 8.3: the clients' copy of the level
	state.site, state.level, state.model, state.pieces, state.stands = site, level, model, pieces, stands
	state.desk, state.ownerLabels, state.stockLabels = terminal, ownerLabels, stockLabels
end

local function buildPlot(parent: Instance, plot: SandboxMap.Plot, level: number): PlotState
	local state: PlotState = {
		plot = plot,
		site = WarehouseLayout.site(plot, level) :: SandboxMap.Plot,
		level = level,
		parent = parent,
		model = nil :: any, -- (buildModel's, below)
		pieces = nil :: any,
		stands = {},
		desk = nil :: any,
		deskPrompt = nil,
		owner = nil,
		ownerLabels = {},
		stockLabels = {},
		pending = false,
	}
	buildModel(state, level)
	return state
end

-- ── What a shown piece earns ─────────────────────────────────────────────────
-- The collection's rules (shared/CollectionRules.luau) decide a piece's rarity and its income a minute, the same the
-- server pays (server/Collection.luau) and the picker shows (client/WarehouseUi.luau).

local function rarityOf(entry: Collection.Entry): string?
	return CollectionRules.rarityOf(CollectionRules.defOf(entry.item))
end

local function ratesOf(onStand: { [number]: Collection.Entry }, boost: number): { [number]: number }
	local rates: { [number]: number } = {}
	for index, entry in onStand do
		rates[index] = CollectionRules.income(entry :: any, boost)
	end
	return rates
end

-- ── The stands ───────────────────────────────────────────────────────────────

-- The piece on show on a stand: its model at the podium's middle, looking the stand's way (south to its aisle and the
-- door, or the way the level turns it; anchored, nothing to touch). 8.3: the stand of the level built there now.
local function place(state: PlotState, stand: Stand, entry: Collection.Entry): (Model, number)
	local spot = WarehouseLayout.stand(state.site, stand.index) :: WarehouseLayout.Stand
	local model = FurnitureLooks.build(entry.item, entry.variant)
	FurnitureMesh.dress(model, entry.item, entry.variant) -- (the owner's Blender look, once imported)
	local root = model.PrimaryPart
	local height = if root then root.Size.Y else 2
	model:PivotTo(CFrame.new(spot.x, spot.y + height / 2, spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
	model.Name = `Shown{stand.index}`
	model:SetAttribute("Stand", stand.index)
	model:SetAttribute("Uid", entry.uid)
	model.Parent = state.pieces
	return model, height
end

-- Brings every stand, the tags, the prompts and the STOCK board in step with the owner's collection.
local function refresh(state: PlotState)
	local owner = state.owner
	local entries: { Collection.Entry } = if owner then Collection.stock(owner) else {}
	local onStand: { [number]: Collection.Entry } = {}
	local stock, shown = 0, 0
	for _, entry in entries do
		local at = entry.stand
		if at == nil then
			stock += 1
		elseif state.stands[at] and onStand[at] == nil then
			onStand[at] = entry
			shown += 1
		end
	end
	local income = if owner then Collection.incomePerMinute(owner) else 0
	local rates = ratesOf(onStand, if owner then Collection.boost(owner) else 1)
	local count = if owner then Collection.stands(owner) else WarehouseLayout.count(state.level) -- (8.3: a free plot's level)
	for index, stand in state.stands do
		setOpen(stand, index <= count)
		local entry = if stand.open then onStand[index] else nil
		local current = stand.shown
		if current and (entry == nil or current.uid ~= entry.uid or current.item ~= entry.item or current.variant ~= entry.variant) then
			current.model:Destroy()
			stand.shown = nil
		end
		if entry and stand.shown == nil then
			local ok, model, height = pcall(place, state, stand, entry)
			if ok then
				stand.shown = { uid = entry.uid, item = entry.item, variant = entry.variant, model = model, height = height }
			else
				warn(`Warehouse: plot {state.plot.id} stand {index}: {model}`)
			end
		end
		local now = stand.shown
		if entry and now then
			setLines(stand.tagLabels, WarehouseLayout.tagLines(entry.name, rarityOf(entry), rates[index] or 0))
			-- (over the piece: from the podium's middle up past its top)
			local top = WarehouseLayout.FloorTop + T.StandHeight + now.height
			stand.tag.StudsOffsetWorldSpace = Vector3.new(0, top + 1.3 - stand.podium.Position.Y, 0)
			stand.tag.Enabled = true
		else
			stand.tag.Enabled = false
		end
		local prompts = stand.prompts
		if prompts then
			prompts.display.Enabled = stand.open and entry == nil
			prompts.takeDown.Enabled = entry ~= nil
			prompts.sell.Enabled = entry ~= nil
			prompts.display.ObjectText = `Stand {index}`
			prompts.takeDown.ObjectText = if entry then entry.name else ""
			prompts.sell.ObjectText = if entry then entry.name else ""
		end
	end
	setLines(state.stockLabels, WarehouseLayout.stockLines(stock, income, shown, math.min(count, #state.stands)))
end

-- A refresh soon (the changes of one collection this close together: one).
local function schedule(state: PlotState)
	if state.pending then
		return
	end
	state.pending = true
	task.delay(T.Rebuild, function()
		state.pending = false
		refresh(state)
	end)
end

local function entryOn(player: Player, index: number): Collection.Entry?
	for _, entry in Collection.stock(player) do
		if entry.stand == index then
			return entry
		end
	end
	return nil
end

-- A stand's prompt used: the server checks it is the owner (another player's client shows no prompts of a warehouse
-- not theirs, but a client can't be trusted).
local function use(state: PlotState, stand: Stand, by: Player, action: string)
	local owner = state.owner
	if by ~= owner then
		notice:FireClient(by, if owner then `This is {owner.DisplayName}'s warehouse.` else "This warehouse is for rent.")
		return
	end
	local now = os.clock()
	if (busy[by] or 0) > now then
		return
	end
	busy[by] = now + 0.4
	if action == "display" then
		Collection.openPicker(by, stand.index)
		return
	end
	local entry = entryOn(by, stand.index)
	if not entry then
		notice:FireClient(by, "Nothing is on show on this stand.")
		schedule(state)
		return
	end
	if action == "takeDown" then
		local ok, why = Collection.undisplay(by, entry.uid)
		notice:FireClient(by, if ok then `{entry.name} is back in your stock.` else why or "You can't take it down now.")
	else
		local money, why = Collection.sell(by, entry.uid)
		if money == nil then
			notice:FireClient(by, why or "You can't sell it now.")
		end
	end
end

local function prompt(stand: Stand, name: string, action: string, key: Enum.KeyCode, pad: Enum.KeyCode, hold: number, owner: Player): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = ""
	p.KeyboardKeyCode = key
	p.GamepadKeyCode = pad
	p.HoldDuration = hold
	p.MaxActivationDistance = T.PromptDistance
	p.RequiresLineOfSight = false
	p.Enabled = false
	-- the owner's only: client/CargoPrompts.luau hides a tagged prompt of somebody else's
	p:SetAttribute("CargoOwner", owner.UserId)
	CollectionService:AddTag(p, Config.Cargo.PromptTag)
	p.Parent = stand.anchor
	return p
end

-- 8.1: the UPGRADES desk's prompt used: the owner's window (Upgrades.open), anybody else a notice.
local function useDesk(state: PlotState, by: Player)
	local owner = state.owner
	if by ~= owner then
		notice:FireClient(by, if owner then `This is {owner.DisplayName}'s warehouse.` else "This warehouse is for rent.")
		return
	end
	local now = os.clock()
	if (busy[by] or 0) > now then
		return
	end
	busy[by] = now + 0.4
	Upgrades.open(by)
end

-- New prompts for a new owner (a prompt hidden for a player stays hidden on their client: fresh ones show right).
local function remakePrompts(state: PlotState, owner: Player?)
	local oldDesk = state.deskPrompt
	if oldDesk then
		oldDesk:Destroy()
		state.deskPrompt = nil
	end
	if owner then
		local desk = Instance.new("ProximityPrompt")
		desk.Name = "Upgrades"
		desk.ActionText = "Upgrades"
		desk.ObjectText = "ZDC UPGRADES"
		desk.KeyboardKeyCode = Enum.KeyCode.E
		desk.GamepadKeyCode = Enum.KeyCode.ButtonX
		desk.HoldDuration = 0
		desk.MaxActivationDistance = T.PromptDistance
		desk.RequiresLineOfSight = false
		desk:SetAttribute("CargoOwner", owner.UserId) -- (the owner's only: client/CargoPrompts.luau hides it from others)
		CollectionService:AddTag(desk, Config.Cargo.PromptTag)
		desk.Parent = state.desk:FindFirstChild("Prompts")
		desk.Triggered:Connect(function(by: Player)
			useDesk(state, by)
		end)
		state.deskPrompt = desk
	end
	for _, stand in state.stands do
		local old = stand.prompts
		if old then
			old.display:Destroy()
			old.takeDown:Destroy()
			old.sell:Destroy()
			stand.prompts = nil
		end
		if owner then
			local made: Prompts = {
				display = prompt(stand, "Display", "Display", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0, owner),
				takeDown = prompt(stand, "TakeDown", "Take down", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0, owner),
				sell = prompt(stand, "Sell", "Sell", Enum.KeyCode.F, Enum.KeyCode.ButtonY, T.SellHold, owner),
			}
			made.display.Triggered:Connect(function(by: Player)
				use(state, stand, by, "display")
			end)
			made.takeDown.Triggered:Connect(function(by: Player)
				use(state, stand, by, "takeDown")
			end)
			made.sell.Triggered:Connect(function(by: Player)
				use(state, stand, by, "sell")
			end)
			stand.prompts = made
		end
	end
end

-- The owner's sign, their prompts (fresh ones) and the pieces on the stands, as the plot's owner is now.
local function dressOwner(state: PlotState)
	local owner = state.owner
	setLines(state.ownerLabels, WarehouseLayout.ownerLines(if owner then owner.DisplayName else nil, state.plot.id))
	remakePrompts(state, owner)
	refresh(state)
end

-- 8.3: the plot's warehouse at `level`: nothing when it is built at that level already (→ false); else the old Model
-- goes (with the pieces it showed and its prompts), the level's is built in the same state (the API and the handlers
-- the prompts hold answer for it), and the sign, the owner's prompts and the pieces on their stands come back (→ true).
local function setLevel(state: PlotState, level: number): boolean
	if level == state.level then
		return false
	end
	for _, stand in state.stands do
		local shown = stand.shown
		if shown then
			shown.model:Destroy()
			stand.shown = nil
		end
	end
	state.deskPrompt = nil -- (it goes with the old desk)
	state.model:Destroy()
	buildModel(state, level)
	dressOwner(state)
	return true
end

-- The plot was claimed (owner) or freed (nil): 8.3: the building at the level that goes with it; the sign, the
-- prompts, the pieces.
local function owned(state: PlotState, owner: Player?)
	state.owner = owner
	for player in busy do
		if player.Parent == nil then
			busy[player] = nil
		end
	end
	if not setLevel(state, levelFor(owner)) then
		dressOwner(state)
	end
end

-- ── The API ──────────────────────────────────────────────────────────────────

function Warehouse.model(id: number): Model?
	local state = states[id]
	return if state then state.model else nil
end

function Warehouse.shown(id: number, index: number): Model?
	local state = states[id]
	local stand = if state then state.stands[index] else nil
	local shown = if stand then stand.shown else nil
	return if shown then shown.model else nil
end

function Warehouse.terminal(id: number): BasePart?
	local state = states[id]
	return if state then state.desk else nil
end

function Warehouse.isOpen(id: number, index: number): boolean
	local state = states[id]
	local stand = if state then state.stands[index] else nil
	return stand ~= nil and stand.open
end

function Warehouse.level(id: number): number?
	local state = states[id]
	return if state then state.level else nil
end

function Warehouse.start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "Warehouses"
	for _, plot in SandboxMap.Plots do
		states[plot.id] = buildPlot(folder, plot, levelFor(SandboxPlots.owner(plot.id))) -- (8.3: an owner from before: theirs)
	end
	folder.Parent = workspace
	SandboxPlots.onChanged(function(id: number, player: Player?)
		local state = states[id]
		if state then
			owned(state, player)
		end
	end)
	Collection.onChanged(function(player: Player)
		for _, state in states do
			if state.owner == player then
				schedule(state)
			end
		end
	end)
	-- 8.3: the owner's levels changed (their save loaded, the ZDC Warehouse bought, the admin's MAX / RESET): their
	-- plot rebuilt when its level is another now (the other upgrades: nothing here, the collection's change refreshes)
	Upgrades.onChanged(function(player: Player)
		for _, state in states do
			if state.owner == player then
				setLevel(state, levelFor(player))
			end
		end
	end)
	for id, state in states do
		local owner = SandboxPlots.owner(id)
		if owner then
			owned(state, owner)
		end
	end
end

return Warehouse
