--!strict
-- 8.2 SANDBOX, showing off: what every player's collection is worth, where everybody sees it (the numbers are
-- Config.SandboxLeaders', the rules shared/SandboxLeadersRules.luau's). server/SandboxBoot.luau starts it after the
-- collection; the city never does.
--   * Roblox's player list (leaderstats): the folder server/PlayerData.luau makes when a save loads loses the city's
--     columns (Level, Money, Deliveries: the sandbox has no levels) and gets the sandbox's, in Stats' order: "💰 $" (the
--     money, an IntValue: the list sorts by it), "📈 $/min" (what the pieces on show earn a minute,
--     Collection.incomePerMinute, a NumberValue to a tenth) and "⭐ Collection" (what everything the player owns is
--     worth, on show or not: SandboxLeadersRules.summary). Written when the money (PlayerData.Changed) or the collection
--     (Collection.onChanged) changes, at most every Every s a player: the changes in between wait for that moment, the
--     last one always lands.
--   * The TOP MOVERS board: a wooden alpine signboard (two posts on stone footings, a planked panel, a little gable
--     roof, a flower box) at the crossroads' south-east corner, across Main Street from the signpost
--     (SandboxLeadersRules.spot: off the roads, their shoulders, the plots, the lamps and the trees; its face to the
--     crossroads). The same board on both faces (a SurfaceGui each): this server's players ranked by what their
--     collection is worth (SandboxLeadersRules.rank), each with $ a minute, legendaries and the all-time best; written
--     at most every BoardEvery s, when a collection changes or somebody joins or leaves.
--   * The all-time best (AllTime.On): the best collection worth each player ever had, in the OrderedDataStore
--     AllTime.Store (key: the user id), read once when they join; a new best is written (UpdateAsync: only ever up, a
--     higher one from another server stays) at most every AllTime.Every s a player, never from Studio unless
--     AllTime.Studio. Every store call is in a pcall: without the store (Studio without API access, an outage: one
--     warning) the ALL-TIME column shows the best seen on this server. (A best newer than the last write may be lost
--     when the server shuts down within AllTime.Every s of it.)
-- No remote and nothing per frame: the list and the board reach the clients by Roblox's own replication.
--
--   SandboxLeaders.start()          builds the board (workspace.Sandbox, else the workspace) and listens
--   SandboxLeaders.rows()           the board's rows now (SandboxLeadersRules.Row, ranked; the players whose save has
--                                   loaded, not the ones leaving)
--   SandboxLeaders.board()          the board's Model "TopMovers" (nil before start)
--   SandboxLeaders.best(userId)     the all-time best known for a player (the store's and this server's; 0: none)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.SandboxLeadersRules)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)

local SandboxLeaders = {}

local S = Config.SandboxLeaders
local B = S.Board
local MARK = "SandboxColumns" -- the leaderstats folder's attribute once it shows the sandbox's columns
local CITY_STATS = { "Level", "Money", "Deliveries" } -- server/PlayerData.luau's (the city's) columns
local MAX_INT = 2 ^ 31 - 1

-- The board's looks: alpine wood, a dark green painted panel, gold letters.
local WOOD = Color3.fromRGB(132, 92, 58)
local DARK = Color3.fromRGB(90, 60, 40)
local ROOF = Color3.fromRGB(96, 56, 42)
local STONE = Color3.fromRGB(124, 122, 116)
local PAINT = Color3.fromRGB(34, 52, 40)
local STRIPE = Color3.fromRGB(58, 82, 64)
local CREAM = Color3.fromRGB(250, 242, 222)
local GOLD = Color3.fromRGB(255, 206, 92)
local GREEN = Color3.fromRGB(132, 226, 124)
local LEGEND = Color3.fromRGB(255, 178, 36) -- (Config.Collection's legendary)
local BEST = Color3.fromRGB(176, 204, 230)
local MUTED = Color3.fromRGB(196, 210, 192)
local BLOOM = Color3.fromRGB(214, 48, 52)
local LEAVES = Color3.fromRGB(64, 120, 52)
local MEDALS = { Color3.fromRGB(255, 196, 64), Color3.fromRGB(206, 212, 222), Color3.fromRGB(214, 140, 84) }
local PLAIN = Color3.fromRGB(84, 64, 48) -- a rank past the medals
local INK = Color3.fromRGB(40, 30, 22)

type Columns = { money: IntValue, income: NumberValue, value: IntValue }
type Watch = { at: number, waiting: boolean }
type Cells = { frame: Frame, badge: Frame, labels: { [string]: TextLabel } }
type Face = { rows: { Cells }, empty: TextLabel }
type Best = { stored: number, top: number, pending: number?, last: number, waiting: boolean, asked: boolean, loaded: boolean }

local watched: { [Player]: Watch } = {} -- the players whose save has loaded: their list columns' last write
local gone: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- leaving (PlayerRemoving fired)
local faces: { Face } = {}
local model: Model? = nil
local boardAt = -math.huge
local boardWaiting = false
local bests: { [number]: Best } = {} -- by user id (a player who left keeps theirs: a write may still be due)
local store: OrderedDataStore? = nil
local warned = false
local started = false

local function nameOf(player: Player): string
	local display = player.DisplayName
	return if type(display) == "string" and display ~= "" then display else player.Name
end

-- ── The all-time best ──────────────────────────────────────────────────────

local function warnOnce(what: string, err: any)
	if not warned then
		warned = true
		warn(`[SandboxLeaders] the all-time store {what}: {err} (the ALL-TIME column shows this server's best)`)
	end
end

local function bestOf(userId: number): Best
	local best = bests[userId]
	if not best then
		best = { stored = 0, top = 0, pending = nil, last = -math.huge, waiting = false, asked = false, loaded = false }
		bests[userId] = best
	end
	return best :: Best
end

local function canWrite(): boolean
	return store ~= nil and (S.AllTime.Studio or not RunService:IsStudio())
end

local boardSoon: () -> ()
local writeBest: (userId: number) -> ()

-- A best waiting to be written: once AllTime.Every s after the player's last write (one wait at a time).
local function scheduleWrite(userId: number)
	local best = bestOf(userId)
	if best.waiting or best.pending == nil or not best.loaded then
		return
	end
	best.waiting = true
	task.delay(math.max(0, best.last + S.AllTime.Every - os.clock()), writeBest, userId)
end

writeBest = function(userId: number)
	local best = bestOf(userId)
	best.waiting = false
	local pending = best.pending
	best.pending = nil
	local ordered = store
	if pending == nil or pending <= best.stored or not ordered or not canWrite() then
		return
	end
	local value: number = pending
	best.last = os.clock()
	local before = 0
	local ok, err = pcall(function()
		ordered:UpdateAsync(tostring(userId), function(old: any): any
			before = if type(old) == "number" and old == old then old else 0
			return if before < value then value else nil -- (only ever up: nil writes nothing)
		end)
	end)
	if ok then
		best.stored = math.max(best.stored, before, value)
		best.top = math.max(best.top, best.stored)
		boardSoon()
	else
		warnOnce("could not be written", err)
		best.pending = math.max(best.pending or 0, value)
		scheduleWrite(userId) -- (again AllTime.Every s after this try)
	end
end

-- The player's best from the store, once (a write waits for it: it would only cost a request).
local function readBest(player: Player)
	local userId = player.UserId
	local best = bestOf(userId)
	if best.asked or not S.AllTime.On then
		return
	end
	best.asked = true
	local ordered = store
	if not ordered then
		best.loaded = true
		return
	end
	task.spawn(function()
		local ok, result = pcall(function(): any
			return ordered:GetAsync(tostring(userId))
		end)
		if not ok then
			warnOnce("could not be read", result)
		elseif type(result) == "number" and result == result and result < math.huge then
			best.stored = math.max(best.stored, result)
			best.top = math.max(best.top, result)
		end
		best.loaded = true
		scheduleWrite(userId)
		boardSoon()
	end)
end

-- A collection worth seen: the best this server knows, and a write when it beats the store's.
local function noteBest(userId: number, worth: number)
	if not S.AllTime.On then
		return
	end
	local value = math.floor(math.max(0, worth))
	local best = bestOf(userId)
	best.top = math.max(best.top, value)
	if canWrite() and value > best.stored and value > (best.pending or 0) then
		best.pending = value
		scheduleWrite(userId)
	end
end

function SandboxLeaders.best(userId: number): number
	local best = bests[userId]
	return if best then best.top else 0
end

-- ── The player list ────────────────────────────────────────────────────────

-- The player's list columns: PlayerData's leaderstats folder (made when the save loads) with the sandbox's columns in
-- place of the city's (once). Nil before the save has loaded.
local function columnsOf(player: Player): Columns?
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return nil
	end
	if folder:GetAttribute(MARK) ~= true then
		for _, name in CITY_STATS do
			local old = folder:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		for _, spec in { { S.Stats.Money, "IntValue" }, { S.Stats.Income, "NumberValue" }, { S.Stats.Collection, "IntValue" } } do
			if not folder:FindFirstChild(spec[1]) then
				local value = Instance.new(spec[2])
				value.Name = spec[1]
				value.Parent = folder
			end
		end
		folder:SetAttribute(MARK, true)
	end
	local money = folder:FindFirstChild(S.Stats.Money)
	local income = folder:FindFirstChild(S.Stats.Income)
	local value = folder:FindFirstChild(S.Stats.Collection)
	if money and money:IsA("IntValue") and income and income:IsA("NumberValue") and value and value:IsA("IntValue") then
		return { money = money, income = income, value = value }
	end
	return nil
end

local function write(player: Player)
	local watch = watched[player]
	if not watch or gone[player] then
		return
	end
	watch.waiting = false
	local profile = PlayerData.get(player)
	local columns = if profile then columnsOf(player) else nil
	if not profile or not columns then
		return
	end
	watch.at = os.clock()
	local summary = Rules.summary(Collection.stock(player))
	columns.money.Value = math.clamp(math.floor(profile.money), 0, MAX_INT)
	columns.income.Value = Rules.perMinute(Collection.incomePerMinute(player))
	columns.value.Value = math.clamp(math.floor(summary.value), 0, MAX_INT)
	noteBest(player.UserId, summary.value)
end

-- Something of the player's changed: their columns are written at the frame's end or, written less than Every s ago,
-- when that time is up (one wait, however many changes come). Somebody new: the board too, and their all-time best.
local function touch(player: Player)
	if gone[player] or not player.Parent or not PlayerData.get(player) then
		return
	end
	local watch = watched[player]
	if not watch then
		local fresh: Watch = { at = -math.huge, waiting = false }
		watch = fresh
		watched[player] = fresh
		readBest(player)
		boardSoon()
	end
	local w = watch :: Watch
	if w.waiting then
		return
	end
	w.waiting = true
	local wait = w.at + S.Every - os.clock()
	if wait > 0 then
		task.delay(wait, write, player)
	else
		task.defer(write, player)
	end
end

-- Leaving: no more list writes; the best they leave with still counts (written when their wait is up); the board
-- without them.
local function left(player: Player)
	if watched[player] and PlayerData.get(player) then
		noteBest(player.UserId, Rules.summary(Collection.stock(player)).value)
	end
	gone[player] = true
	watched[player] = nil
	boardSoon()
end

-- ── The board ──────────────────────────────────────────────────────────────

function SandboxLeaders.rows(): { Rules.Row }
	local rows: { Rules.Row } = {}
	for _, player in Players:GetPlayers() do
		if gone[player] or not player.Parent or not PlayerData.get(player) then
			continue
		end
		local summary = Rules.summary(Collection.stock(player))
		table.insert(rows, {
			userId = player.UserId,
			name = nameOf(player),
			value = summary.value,
			income = Collection.incomePerMinute(player),
			legendaries = summary.legendaries,
			best = if S.AllTime.On then SandboxLeaders.best(player.UserId) else nil,
			rank = 0,
		})
	end
	return Rules.rank(rows)
end

local function draw()
	boardWaiting = false
	boardAt = os.clock()
	local rows = SandboxLeaders.rows()
	for _, face in faces do
		for index, cells in face.rows do
			local row = rows[index]
			cells.frame.Visible = row ~= nil
			if row then
				local words = Rules.cells(row)
				for key, label in cells.labels do
					label.Text = words[key] or ""
				end
				cells.badge.BackgroundColor3 = MEDALS[row.rank] or PLAIN
				cells.labels.rank.TextColor3 = if MEDALS[row.rank] then INK else CREAM
			end
		end
		face.empty.Visible = #rows == 0
	end
end

boardSoon = function()
	if boardWaiting or not model then
		return
	end
	boardWaiting = true
	task.delay(math.max(0, boardAt + S.BoardEvery - os.clock()), draw)
end

local ALIGN: { [string]: Enum.TextXAlignment } = {
	left = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	right = Enum.TextXAlignment.Right,
}

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, words: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font, align: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.fromScale(w, h)
	label.BackgroundTransparency = 1
	label.Text = words
	label.TextScaled = true
	label.Font = font
	label.TextColor3 = color
	label.TextXAlignment = ALIGN[align or "center"] or Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

local function rounded(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

-- One face of the panel: the painted board, its title, the columns' titles, Rows rows (hidden while empty), a line for
-- an empty server and the footer.
local function face(panel: BasePart, side: Enum.NormalId, name: string): Face
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = side
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = B.PixelsPerStud
	gui.LightInfluence = 0
	gui.MaxDistance = B.Range
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = panel
	local paint = frame(gui, "Paint", 0.025, 0.045, 0.95, 0.91, PAINT, 0)
	rounded(paint, UDim.new(0.03, 0))
	local edge = Instance.new("UIStroke")
	edge.Color = GOLD
	edge.Thickness = 3
	edge.Transparency = 0.35
	edge.Parent = paint
	text(paint, "Title", "🏆 TOP MOVERS", 0.05, 0.03, 0.9, 0.13, GOLD, Enum.Font.GothamBlack)
	text(paint, "Subtitle", "This server · ranked by what their collection is worth", 0.05, 0.165, 0.9, 0.055, MUTED, Enum.Font.GothamMedium)
	local columns = Rules.columns(S.AllTime.On)
	local heads = frame(paint, "Heads", 0.02, 0.25, 0.96, 0.05, PAINT, 1) -- (as wide as the rows: the columns line up)
	for _, column in columns do
		text(heads, "Head_" .. column.key, column.title, column.x, 0, column.width, 1, MUTED, Enum.Font.GothamBold, column.align)
	end
	frame(paint, "Rule", 0.03, 0.315, 0.94, 0.006, GOLD, 0.4)
	local top, bottom = 0.335, 0.925
	local step = (bottom - top) / math.max(1, S.Rows)
	local rows: { Cells } = {}
	for index = 1, S.Rows do
		local row = frame(paint, `Row{index}`, 0.02, top + (index - 1) * step, 0.96, step * 0.92, STRIPE, if index == 1 then 0.35 else 0.62)
		rounded(row, UDim.new(0.2, 0))
		row.Visible = false
		local labels: { [string]: TextLabel } = {}
		local badge = frame(row, "Badge", 0, 0, 0, 0, PLAIN, 0)
		for _, column in columns do
			if column.key == "rank" then
				badge.AnchorPoint = Vector2.new(0.5, 0.5)
				badge.Position = UDim2.fromScale(column.x + column.width / 2, 0.5)
				badge.Size = UDim2.fromScale(column.width * 0.62, 0.8)
				rounded(badge, UDim.new(0.5, 0))
				labels.rank = text(badge, "rank", "", 0.1, 0.12, 0.8, 0.76, INK, Enum.Font.GothamBlack)
			else
				local color = if column.key == "value" then GOLD elseif column.key == "income" then GREEN elseif column.key == "legend" then LEGEND elseif column.key == "best" then BEST else CREAM
				local font = if column.key == "name" then Enum.Font.GothamBold else Enum.Font.GothamBlack
				labels[column.key] = text(row, column.key, "", column.x, 0.2, column.width, 0.6, color, font, column.align)
			end
		end
		rows[index] = { frame = row, badge = badge, labels = labels }
	end
	local empty = text(paint, "Empty", "Nobody here yet: bring a haul home and show it off!", 0.06, 0.5, 0.88, 0.08, CREAM, Enum.Font.GothamBold)
	text(paint, "Footer", "Pieces on show in your warehouse earn money every minute", 0.05, 0.94, 0.9, 0.045, MUTED, Enum.Font.GothamMedium)
	return { rows = rows, empty = empty }
end

local function piece(parent: Instance, class: string, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	local long, short = math.max(size.X, size.Y, size.Z), math.min(size.X, size.Y, size.Z)
	p.CastShadow = long >= 4 and size.X + size.Y + size.Z - long - short >= 1 -- (SandboxScenery.Shadow's rule)
	p.Parent = parent
	return p
end

-- The signboard at SandboxLeadersRules.spot (its frame: from the ground under the panel's middle, -Z its face, X
-- across), everything inside SandboxLeadersRules.footprint.
local function build(): Model
	local spot = Rules.spot()
	local at = CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0)
	local W, H, L, T, R = B.Width, B.Height, B.Lift, B.Thick, B.Roof
	local m = Instance.new("Model")
	m.Name = "TopMovers"
	m:SetAttribute("SandboxLeaders", true)
	-- the posts on their stone footings
	local postHeight = L + H + 1.2
	for _, side in { -1, 1 } do
		local x = side * (W / 2 + 0.5)
		piece(m, "Part", "Footing", Vector3.new(1.8, 0.9, 1.8), at * CFrame.new(x, 0.15, 0), STONE, Enum.Material.Slate, true)
		piece(m, "Part", "Post", Vector3.new(1, postHeight, 1), at * CFrame.new(x, postHeight / 2, 0), DARK, Enum.Material.Wood, true)
	end
	-- the planked panel (the board on both faces), the ledge under it, the header beam over it
	local panel = piece(m, "Part", "Panel", Vector3.new(W, H, T), at * CFrame.new(0, L + H / 2, 0), WOOD, Enum.Material.WoodPlanks, true)
	piece(m, "Part", "Ledge", Vector3.new(W + 0.4, 0.45, T + 0.7), at * CFrame.new(0, L - 0.225, 0), DARK, Enum.Material.Wood, true)
	piece(m, "Part", "Header", Vector3.new(W + 3, 0.8, T + 0.6), at * CFrame.new(0, L + H + 0.4, 0), DARK, Enum.Material.Wood, true)
	-- the gable roof, its ridge along the board (a wedge each way: its high side at the ridge), the ridge's cap
	local eave, span = L + H + 0.8, W + 2 * R.Over
	piece(m, "WedgePart", "Roof", Vector3.new(span, R.Rise, R.Run), at * CFrame.new(0, eave + R.Rise / 2, -R.Run / 2), ROOF, Enum.Material.WoodPlanks, false)
	piece(m, "WedgePart", "Roof", Vector3.new(span, R.Rise, R.Run), at * CFrame.new(0, eave + R.Rise / 2, R.Run / 2) * CFrame.Angles(0, math.pi, 0), ROOF, Enum.Material.WoodPlanks, false)
	piece(m, "Part", "RidgeCap", Vector3.new(span, 0.3, 0.6), at * CFrame.new(0, eave + R.Rise + 0.05, 0), DARK, Enum.Material.Wood, false)
	-- the flower box under the face: red geraniums
	local boxZ = -(T / 2 + 0.65)
	piece(m, "Part", "FlowerBox", Vector3.new(7, 0.9, 1.1), at * CFrame.new(0, L - 1.0, boxZ), DARK, Enum.Material.WoodPlanks, false)
	piece(m, "Part", "Leaves", Vector3.new(6.6, 0.35, 0.8), at * CFrame.new(0, L - 0.45, boxZ), LEAVES, Enum.Material.Grass, false)
	for n = 0, 5 do
		local bloom = piece(m, "Part", "Bloom", Vector3.new(0.75, 0.75, 0.75), at * CFrame.new(-2.5 + n, L - 0.3, boxZ), BLOOM, Enum.Material.SmoothPlastic, false) :: Part
		bloom.Shape = Enum.PartType.Ball
	end
	table.insert(faces, face(panel, Enum.NormalId.Front, "BoardFront"))
	table.insert(faces, face(panel, Enum.NormalId.Back, "BoardBack"))
	m.WorldPivot = at
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

function SandboxLeaders.board(): Model?
	return model
end

-- ── Starting ───────────────────────────────────────────────────────────────

function SandboxLeaders.start()
	if started then
		return
	end
	started = true
	if S.AllTime.On then
		local ok, result = pcall(function(): any
			return DataStoreService:GetOrderedDataStore(S.AllTime.Store)
		end)
		if ok and result then
			store = result
		else
			warnOnce("is not available", result)
		end
	end
	local built = build()
	built.Parent = workspace:FindFirstChild("Sandbox") or workspace
	model = built
	PlayerData.Changed:Connect(touch)
	Collection.onChanged(function(player: Player)
		touch(player)
		boardSoon()
	end)
	Players.PlayerRemoving:Connect(left)
	for _, player in Players:GetPlayers() do
		touch(player)
	end
	boardSoon()
end

return SandboxLeaders
