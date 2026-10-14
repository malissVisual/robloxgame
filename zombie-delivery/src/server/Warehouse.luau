--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on every player plot. Builds each plot's
-- building once from shared/WarehouseLayout.luau (anchored parts: corrugated metal walls, the gable roof, the open
-- roller door, the hall's lights, the concrete floor's paint, the ZDC sign, the owner's sign, the STOCK board, the
-- display stands and the UNLOAD HERE bay outside) and keeps it in step with its owner (SandboxPlots) and their
-- collection (server/Collection.luau):
--   * the owner's sign over the door: "<Name>'s Warehouse", or FOR RENT on a free plot;
--   * every display stand: its number plate, the piece on show as its 3D model (FurnitureLooks.build, dressed by
--     FurnitureMesh in the owner's Blender look once imported; anchored, in the podium's middle, looking south to its
--     aisle) and a tag over it (its name in its rarity's colour, "+$X/min");
--   * the stands' prompts, for the owner only (tagged like a job's prompt: client/CargoPrompts.luau hides them from
--     everybody else, and the server checks who used one): an empty stand's "Display" (E) asks the owner's client to
--     pick a piece of the stock (Collection.openPicker); a full one's "Take down" (E, Collection.undisplay) and "Sell"
--     (hold F, Collection.sell). The answers go out as Notices (the client's toasts); a sale's own message is the
--     collection's ("sold");
--   * the STOCK board inside: "📦 N pieces in stock · $X/min" and how many stands are on show;
--   * 8.1, the upgrades: the hall has WarehouseLayout.capacity() stands (20); the owner's first Collection.stands of
--     them stand there (the start's 12 and the More stands bought), the others are only their painted spot (their
--     podium, top and plate hidden and not solid, no prompts); the tags' $/min are × the owner's Showroom lights
--     (Collection.boost); the UPGRADES desk at the back wall has the owner's "Upgrades" prompt (E: Upgrades.open, the
--     window client/UpgradeUi.luau; somebody else's use gets a notice, as at the stands);
--   * 8.2: the owner's Blender look (server/WarehouseMesh.luau, once ZDCWarehouseArt is imported): the layout's visual
--     pieces carry the attribute WarehouseVisual and are hidden under the model (the solid ones still collide).
-- A collection's changes (Collection.onChanged) rebuild only the stands whose piece changed, Config.Warehouse.Rebuild
-- apart at most; an owner who leaves takes their pieces with them (the plot is FOR RENT again). Nothing runs per frame.
-- The van's unloading is the moves' (the plot's unload circle); here only its bay is painted.
--
--   Warehouse.start()           builds every plot's warehouse (workspace.Warehouses) and follows owners and collections
--   Warehouse.model(id)         plot `id`'s warehouse Model (nil before start)
--   Warehouse.shown(id, i)      the Model on show on that plot's stand i (nil: the stand is empty)
--   Warehouse.terminal(id)      8.1: plot `id`'s UPGRADES desk (its part with the prompt; nil before start)
--   Warehouse.isOpen(id, i)     8.1: does plot `id`'s stand i stand there (the owner has it)?

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FurnitureLooks = require(Shared.FurnitureLooks)
local CollectionRules = require(Shared.CollectionRules)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)
local WarehouseLayout = require(Shared.WarehouseLayout)
local Collection = require(script.Parent.Collection)
local FurnitureMesh = require(script.Parent.FurnitureMesh)
local SandboxPlots = require(script.Parent.SandboxPlots)
local Upgrades = require(script.Parent.Upgrades) -- 8.1: the UPGRADES desk's window
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

local function buildPlot(parent: Instance, plot: SandboxMap.Plot): PlotState
	local model = Instance.new("Model")
	model.Name = `Warehouse{plot.id}`
	model:SetAttribute("Plot", plot.id)
	local podiums: { [number]: BasePart } = {}
	local standParts: { [number]: { BasePart } } = {}
	local solid: { [BasePart]: boolean } = {}
	local ownerLabels: { TextLabel } = {}
	local stockLabels: { TextLabel } = {}
	local desk: BasePart? = nil
	for _, d in WarehouseLayout.pieces(plot) do
		local part, labels = build(model, d)
		if d.name == "OwnerSign" then
			ownerLabels = labels
		elseif d.name == "StockBoard" then
			stockLabels = labels
		elseif d.name == "TerminalDesk" then
			desk = part
		end
		if d.stand then
			standParts[d.stand] = standParts[d.stand] or {}
			table.insert(standParts[d.stand], part)
			solid[part] = d.solid == true
			if d.name == `Stand{d.stand}` then
				podiums[d.stand] = part
			end
		end
	end
	local pieces = Instance.new("Folder")
	pieces.Name = "Shown"
	pieces.Parent = model
	local stands: { Stand } = {}
	for i = 1, WarehouseLayout.capacity() do
		local podium = podiums[i]
		local spot = WarehouseLayout.stand(plot, i) :: WarehouseLayout.Stand
		-- the prompts at the podium's front edge (the aisle it looks at: +Z south, -Z north), at hand height
		local front = if spot.yaw == 0 then -1 else 1
		local anchor = Instance.new("Attachment")
		anchor.Name = "Prompts"
		anchor.CFrame = CFrame.new(0, 1.6, front * (podium.Size.Z / 2 - 0.3)) -- (its offset in the podium)
		anchor.Parent = podium
		local tag, tagLabels = makeTag(podium)
		local stand: Stand = { index = i, podium = podium, parts = standParts[i] or { podium }, solid = solid, open = true, anchor = anchor, prompts = nil, tag = tag, tagLabels = tagLabels, shown = nil }
		setOpen(stand, i <= WarehouseLayout.count()) -- (an upgrade stand: its spot only, until an owner has it)
		stands[i] = stand
	end
	-- 8.1: the UPGRADES desk's prompt at its front edge (south: the hall), at hand height
	local terminal = desk :: BasePart
	local deskAnchor = Instance.new("Attachment")
	deskAnchor.Name = "Prompts"
	deskAnchor.CFrame = CFrame.new(0, 0.6, terminal.Size.Z / 2 + 0.2)
	deskAnchor.Parent = terminal
	model.WorldPivot = CFrame.new(plot.warehouse.x, 0, plot.warehouse.z)
	WarehouseMesh.dress(model) -- 8.2: the owner's Blender look, once imported (no import: as built)
	model.Parent = parent
	return {
		plot = plot,
		model = model,
		pieces = pieces,
		stands = stands,
		desk = terminal,
		deskPrompt = nil,
		owner = nil,
		ownerLabels = ownerLabels,
		stockLabels = stockLabels,
		pending = false,
	}
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

-- The piece on show on a stand: its model at the podium's middle, looking south (anchored, nothing to touch).
local function place(state: PlotState, stand: Stand, entry: Collection.Entry): (Model, number)
	local spot = WarehouseLayout.stand(state.plot, stand.index) :: WarehouseLayout.Stand
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
	local count = if owner then Collection.stands(owner) else WarehouseLayout.count()
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

-- The plot was claimed (owner) or freed (nil): the sign, the prompts, the pieces.
local function owned(state: PlotState, owner: Player?)
	state.owner = owner
	setLines(state.ownerLabels, WarehouseLayout.ownerLines(if owner then owner.DisplayName else nil, state.plot.id))
	remakePrompts(state, owner)
	for player in busy do
		if player.Parent == nil then
			busy[player] = nil
		end
	end
	refresh(state)
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

function Warehouse.start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "Warehouses"
	for _, plot in SandboxMap.Plots do
		states[plot.id] = buildPlot(folder, plot)
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
	for id, state in states do
		local owner = SandboxPlots.owner(id)
		if owner then
			owned(state, owner)
		end
	end
end

return Warehouse
