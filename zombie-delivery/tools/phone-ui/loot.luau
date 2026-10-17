-- 9.x loot: the stars over the pieces, the toast and the outlines on this client, run for real on sandbox_mock.luau's
-- recorder (lootenv.py's folder): the real client/LootStars.luau and client/LootOutline.luau beside client/Hud.luau's
-- column (sandbox_mock's Hud: its slot "loot" under the toasts, where Hud's layout puts it), a stand-in camera, your
-- character and a house's pieces tagged as the server tags them (Config.Loot.Tag: Rarity, Stars, Value, FurnitureId,
-- MoveSpot), on a phone held sideways (844 × 390, 667 × 375: the touch layout, DeviceBudget's share and reach) and a
-- computer (1280 × 800, 1920 × 1080):
--   * the stars: the nearest few within reach (a phone 4 within 24 studs, a computer 8 within 40), a BillboardGui each
--     sized like Danny's bubble (its words never cut, a phone's text 11 px and more, a pill a fraction of the screen),
--     never drawn through a wall (AlwaysOnTop false), over the piece's top; ★ × its stars in its tier's colour, near
--     (Stars.Near) its tier's name and value too; faded with the distance; none while a window covers the screen; none
--     over the piece in your hands; a piece streamed in or gone (the tag's signals) followed;
--   * the first sight: an Epic or Legendary piece of a house in sight sparkles once (a ParticleEmitter, its default
--     sparkle texture) with its sound (the sheets': "ding", "stored_fanfare"); not through a wall; not a stand's piece;
--   * the toast: your pick-up of an Uncommon or better ("+ RARE Grandma's Clock ★★★ $450": its parts in their colours,
--     the name shortened to fit), a Common none, once a piece, Toast.Gap apart (the next waits), Toast.Most at once;
--     your load (the piece welded into a van after it left your hands) toasts too, set down does not; in the HUD's
--     column at the HUD's scale: on the screen, clear of the touch buttons, the jump button and the thumbstick;
--   * the outlines: a Highlight per piece (the tier's colour, its soft fill, Occluded), the rarest first, never past
--     the shared budget (31 − Config.Outline.Spare − the enemies outlined: M.enemies), a Common none, the enemies'
--     squeeze takes the plainest off at once, a piece gone gives its Highlight back;
--   * no warnings.
-- `luau loot.luau -a dump` prints the preview's scenes as JSON instead (loot_preview.py).
local M = require("./sandbox_mock")
local Config = require("./Config")
local LootRules = require("./LootRules")
local OutlinePick = require("./OutlinePick")
local TouchLayout = require("./TouchLayout")

local dump = select(1, ...) == "dump"
local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	if not dump then
		print("ok    " .. name)
	end
end
local function all(root, predicate)
	local out = {}
	local function visit(object)
		if predicate(object) then
			table.insert(out, object)
		end
		for _, child in object:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return out
end
local function named(root, name)
	return all(root, function(object)
		return object.Name == name
	end)
end
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end

-- ── The stand-ins ───────────────────────────────────────────────────────────
local L = Config.Loot
local S, T = L.Stars, L.Toast
local TAG = L.Tag
local V3 = M.Vector3.new
local vmeta = getmetatable(V3(0, 0, 0))
vmeta.__add = function(a, b)
	return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
M.methods.FindFirstAncestorOfClass = function(self, class)
	local node = self.Parent
	while node do
		if node.ClassName == class then
			return node
		end
		node = node.Parent
	end
	return nil
end
M.emits = {}
M.methods.Emit = function(self, n)
	table.insert(M.emits, { emitter = self, n = n })
end
M.rayHit = nil
M.workspace.Raycast = function()
	return M.rayHit
end
local added, removed = M.signal(), M.signal()
M.tagged[TAG] = {}
M.services.CollectionService.GetInstanceAddedSignal = function()
	return added
end
M.services.CollectionService.GetInstanceRemovedSignal = function()
	return removed
end
local camera = M.workspace.CurrentCamera
camera.CFrame = M.CFrame.new(0, 5, 0)
local character = M.player.Character
M.root.Position = V3(0, 3, -2)
M.root.Parent = character
local house = M.make("Folder", { Name = "House" }, M.workspace)

-- A piece of a house (MoveSpot) or of a stand (none), as the server tags it, `away` studs in front of the camera.
local pieces = {}
local function piece(spot, item, rarity, value, x, away, stand)
	local model = M.make("Model", { Name = item }, house)
	local root = M.make("Part", { Name = "Root", Position = V3(x, 1.5, -away), Size = V3(2, 3, 2) }, model)
	model.PrimaryPart = root
	model:SetAttribute("FurnitureId", item)
	model:SetAttribute("MoveSpot", if stand then nil else spot)
	for key, v in LootRules.attributes(rarity, value) do
		model:SetAttribute(key, v)
	end
	table.insert(M.tagged[TAG], model)
	pieces[spot] = model
	return model
end
local function stream(model)
	added:Fire(model)
end
local function unstream(model) -- (destroyed or streamed out: the tag's removed signal, no longer tagged)
	model.Parent = nil
	table.remove(M.tagged[TAG], table.find(M.tagged[TAG], model) :: number)
	removed:Fire(model)
end
local function distance(model)
	return (model.PrimaryPart.Position - camera.CFrame.Position).Magnitude
end
-- the camera at (0, 5, 0): a piece's distance √(x² + 3.5² + away²)
piece(1, "grandfather_clock", "rare", 1350, 0.5, 3.5) -- (near: its words too)
piece(2, "oil_painting", "legendary", 6000, -2, 6)
piece(3, "arcade_cabinet", "epic", 2800, 3, 10)
piece(4, "sofa", "uncommon", 350, -4, 15) -- (past a phone's Fade: fading)
piece(5, "dining_chair", "common", 40, 2, 17)
piece(6, "piano", "rare", 1200, 0, 30) -- (past a phone's reach, within a computer's)
piece(7, "jukebox", "epic", 3400, 6, 21, true) -- (a stand's piece: no MoveSpot, no first-sight sparkle)

local LootStars = require("./LootStars")
local LootOutline = require("./LootOutline")
local EnemyOutline = require("./EnemyOutline")

local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
end
local function look()
	M.resume() -- (LootStars' loop: one look)
end
local function tierColor(rarity)
	local c = LootRules.color(rarity)
	return M.Color3.fromRGB(c[1], c[2], c[3])
end
local function sameColor(a, b)
	return a and b and math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end
local function bubbleOf(model)
	for _, gui in LootStars.bubbles() do
		if gui.Adornee == model.PrimaryPart then
			return gui
		end
	end
	return nil
end
local function child(object, name)
	return object:FindFirstChild(name, true)
end
local function fits(label)
	return M.textWidth(label.Text, label.TextSize, label.Font) <= label.Size.X.Offset + 0.5
end

-- ── The preview's scenes (loot_preview.py) ──────────────────────────────────
local scenes = {}
local function color(c)
	return if type(c) == "table" and c.R then { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } else nil
end
local function udim2(u)
	return if type(u) == "table" and type(u.X) == "table" then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
end
local function node(n)
	local p = n._p
	local out = { c = p.ClassName, n = p.Name }
	if p.Visible == false then
		out.vis = false
	end
	out.pos, out.size = udim2(p.Position), udim2(p.Size)
	if p.AnchorPoint then
		out.anchor = { p.AnchorPoint.X, p.AnchorPoint.Y }
	end
	out.z, out.order = p.ZIndex, p.LayoutOrder
	out.bg, out.bgT = color(p.BackgroundColor3), p.BackgroundTransparency
	out.clip = p.ClipsDescendants
	if p.Text and p.Text ~= "" then
		out.text, out.ts = p.Text, p.TextSize
		out.tc, out.tt = color(p.TextColor3), p.TextTransparency
		out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
		out.font = if p.Font then p.Font.Name else nil
		out.wrap = p.TextWrapped == true
	end
	if p.ClassName == "UICorner" then
		out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
	elseif p.ClassName == "UIStroke" then
		out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
	elseif p.ClassName == "UIScale" then
		out.scale = p.Scale
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	for _, kid in n:GetChildren() do
		table.insert(kids, node(kid))
	end
	if #kids > 0 then
		out.kids = kids
	end
	return out
end
-- A point in the world on the screen (the stand-in camera at (0, 5, 0) looking along −Z, about 70° high).
local function project(at)
	local f = M.height * 0.72
	local depth = math.max(0.5, -at.Z)
	return M.width / 2 + f * at.X / depth, M.height * 0.55 - f * (at.Y - 5) / depth
end
local function scene(name)
	if not dump then
		return
	end
	local tree = node(M.gui)
	-- the BillboardGuis drawn where they stand over their pieces (a ScreenGui of the preview's own, under the HUD)
	local holder = { c = "ScreenGui", n = "Billboards", display = -1, enabled = true, kids = {} }
	local overlay = {}
	for spot, model in pieces do
		local root = model.PrimaryPart
		if model.Parent and distance(model) < 45 then
			local x, y = project(root.Position)
			local s = M.height * 0.72 / math.max(0.5, -root.Position.Z)
			table.insert(overlay, { kind = "piece", box = { x0 = x - s, y0 = y - 1.5 * s, x1 = x + s, y1 = y + 1.5 * s }, label = model.Name, color = color(tierColor(model:GetAttribute("Rarity"))) })
		end
	end
	for _, gui in LootStars.bubbles() do
		local root = gui.Adornee
		local top = root.Position + gui.StudsOffsetWorldSpace
		local x, y = project(top)
		local w, h = gui.Size.X.Offset, gui.Size.Y.Offset
		local frame = { c = "Frame", n = "Bubble", pos = { 0, x - w / 2, 0, y - h }, size = { 0, w, 0, h }, bgT = 1, kids = {} }
		for _, kid in gui:GetChildren() do
			table.insert(frame.kids, node(kid))
		end
		table.insert(holder.kids, frame)
	end
	tree.kids = tree.kids or {}
	table.insert(tree.kids, 1, holder)
	if M.touch then
		local S2 = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S2)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = tree })
end

-- ── A phone held sideways: the stars ────────────────────────────────────────
screen(true, 844, 390)
local Lite = Config.Performance.Lite
local reach, most = S.Range * Lite.Range, math.max(1, math.floor(S.Count * Lite.Count + 0.5))
LootStars.start()
local shownNow = LootStars.bubbles()
check(`a phone: the {most} nearest pieces within {reach} studs show their stars`, #shownNow == most, #shownNow)
local nearest = { pieces[1], pieces[2], pieces[3], pieces[4] }
local every = true
for _, model in nearest do
	every = every and bubbleOf(model) ~= nil
end
check("… the nearest four (the clock, the painting, the cabinet, the sofa), not the chair farther, not the piano past the reach", every and bubbleOf(pieces[5]) == nil and bubbleOf(pieces[6]) == nil)
local clockGui = bubbleOf(pieces[1]) :: any
check("a bubble: a BillboardGui on the piece's root, never through a wall (AlwaysOnTop false), unlit, its reach the device's", clockGui.ClassName == "BillboardGui" and clockGui.AlwaysOnTop == false
	and clockGui.LightInfluence == 0 and clockGui.MaxDistance == reach and clockGui.ResetOnSpawn == false)
check("… over the piece's top (half its height + Lift)", math.abs(clockGui.StudsOffsetWorldSpace.Y - (1.5 + S.Lift)) < 1e-6)
local stars, info = child(clockGui, "Stars"), child(clockGui, "Info")
check("the clock (near, Rare): ★★★ in Rare's colour, and its tier and value: \"RARE · $1,350\"", stars.Text == "★★★" and sameColor(stars.TextColor3, tierColor("rare"))
	and info.Visible == true and info.Text == "RARE · $1,350", info.Text)
check("… sized like Danny's bubble (Tall px high), its words never cut, readable (11 px and more)", clockGui.Size.Y.Offset == S.Tall and fits(stars) and fits(info)
	and stars.TextSize >= 11 and info.TextSize >= 11 and clockGui.Size.X.Offset == S.Pad + stars.Size.X.Offset + 5 + info.Size.X.Offset + S.Pad)
check("… a small part of the screen (under a quarter of its width)", clockGui.Size.X.Offset <= M.width / 4, clockGui.Size.X.Offset)
local sofaGui = bubbleOf(pieces[4]) :: any
check("the sofa (farther, Uncommon): ★★ only, in Uncommon's colour", child(sofaGui, "Stars").Text == "★★" and child(sofaGui, "Info").Visible == false
	and sameColor(child(sofaGui, "Stars").TextColor3, tierColor("uncommon")) and sofaGui.Size.X.Offset == S.Pad + child(sofaGui, "Stars").Size.X.Offset + S.Pad)
local legend = bubbleOf(pieces[2]) :: any
check("the painting (Legendary): ★★★★★ in Legendary's gold", child(legend, "Stars").Text == "★★★★★" and sameColor(child(legend, "Stars").TextColor3, tierColor("legendary")))
local near0 = child(clockGui, "Stars").TextTransparency
local far = child(sofaGui, "Stars").TextTransparency
check("the fade: the near one as drawn, the farther one fading (a phone's shorter reach)", near0 == 0 and far > 0 and far < 1, far)
scene("loot-phone-stars")

-- the first sight
local sparkles = named(house, "LootSparkle")
check("the first sight: the Epic cabinet and the Legendary painting sparkle (a ParticleEmitter in its root, its default texture: no new asset)", #sparkles == 2
	and sparkles[1].ClassName == "ParticleEmitter" and sparkles[1].Texture == nil and #M.emits == 2, #sparkles)
local heardDing, heardFanfare = table.find(M.played, "ding") ~= nil, table.find(M.played, "stored_fanfare") ~= nil
check("… with their sounds of the sheets (Epic's ding, Legendary's fanfare)", heardDing and heardFanfare, table.concat(M.played, ","))
look()
check("… once (a second look: no second sparkle)", #named(house, "LootSparkle") == 2 and #M.emits == 2)
local hidden = piece(8, "antique_vase", "epic", 3000, -1, 8)
local wall = M.make("Part", { Name = "Wall" }, M.workspace)
M.rayHit = { Instance = wall, Position = V3(0, 3, -4) }
stream(hidden)
look()
check("an Epic piece behind a wall: no sparkle yet (a ray from the camera: not through walls)", #named(hidden, "LootSparkle") == 0)
M.rayHit = nil
look()
check("… in sight: it sparkles", #named(hidden, "LootSparkle") == 1)
check("a stand's Epic piece (no MoveSpot): never sparkles", #named(pieces[7], "LootSparkle") == 0)
unstream(hidden)
pieces[8] = nil
local held = piece(9, "jukebox", "epic", 3400, 1, 9)
M.make("WeldConstraint", { Part0 = M.root, Part1 = held.PrimaryPart }, held.PrimaryPart)
stream(held)
look()
check("an Epic piece first seen in somebody's hands or a van (welded): no sparkle (not where the house held it)", #named(held, "LootSparkle") == 0)
unstream(held)
pieces[9] = nil
look()
check("a piece gone (the tag removed): its bubble goes with it", bubbleOf(hidden) == nil and #LootStars.bubbles() == most)

-- a window over the game, the piece in your hands
LootStars.covered = function()
	return true
end
look()
check("a window covers the game: no stars at all", #LootStars.bubbles() == 0)
LootStars.covered = function()
	return false
end
look()
check("… closed: they come back", #LootStars.bubbles() == most)

-- ── The toast ───────────────────────────────────────────────────────────────
local slot = M.topStack:FindFirstChild("Slot_loot")
local function toasts()
	local list = {}
	local found = M.topStack:FindFirstChild("Slot_loot")
	for _, kid in (if found then found:GetChildren() else {}) do
		if kid.Name == "LootToast" and kid.Parent then
			table.insert(list, kid)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end
check("(no toast yet)", slot == nil or #toasts() == 0)
pieces[1].PrimaryPart.Position = V3(0.5, 2, -3) -- (in your hands)
character:SetAttribute("MoveCarry", 1)
look()
local list = toasts()
check("your pick-up of the Rare clock: a toast in the HUD's column (its slot \"loot\")", #list == 1, #list)
local strip = list[1]
local words = {}
for _, name in { "Head", "PieceName", "Stars", "Value" } do
	table.insert(words, child(strip, name).Text)
end
check("… \"+ RARE Grandfather Clock ★★★ $1,350\" (LootRules.toastText's words)", table.concat(words, " ") == LootRules.toastText("rare", "Grandfather Clock", 1350), table.concat(words, " "))
check("… the head and the stars in Rare's colour, the value money green, a rule in Rare's colour", sameColor(child(strip, "Head").TextColor3, tierColor("rare"))
	and sameColor(child(strip, "Stars").TextColor3, tierColor("rare")) and sameColor(child(strip, "Value").TextColor3, M.MTheme.Colors.money)
	and sameColor(child(strip, "Rule").BackgroundColor3, tierColor("rare")))
local parts = { child(strip, "Head"), child(strip, "Stars"), child(strip, "Value") }
local cut = false
for _, label in parts do
	cut = cut or not fits(label)
end
check("… its words never cut (the name shortened to fit at most), within Toast.Width", not cut and strip.Size.X.Offset <= T.Width and child(strip, "PieceName").Size.X.Offset >= 24)
check("no stars over the piece in your hands", bubbleOf(pieces[1]) == nil)
local function onScreen(b)
	return b.x0 >= 0 and b.y0 >= 0 and b.x1 <= M.width and b.y1 <= M.height
end
local function clearOfTouch(b)
	local S2 = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	local c = TouchLayout.cluster(M.width, M.height, S2)
	for _, other in { c.jump, c.thumb, c.fire, c.sprint, c.act, c.holster } do
		if overlap(b, other) then
			return false
		end
	end
	return not (M.leftColumn and overlap(b, M.leftColumn))
end
check("… on the screen, clear of the touch buttons, the jump button, the thumbstick and the left column", onScreen(box(strip)) and clearOfTouch(box(strip)), show(box(strip)))
scene("loot-phone-toast")

-- a Common none; once a piece; the gap; Most at once
character:SetAttribute("MoveCarry", nil)
look()
pieces[5].PrimaryPart.Position = V3(1, 2, -3)
character:SetAttribute("MoveCarry", 5)
look()
check("a Common picked up: no toast (Toast.From: Uncommon)", #toasts() == 1)
character:SetAttribute("MoveCarry", nil)
look()
pieces[1].PrimaryPart.Position = V3(0.5, 2, -3)
character:SetAttribute("MoveCarry", 1)
look()
check("the clock picked up again: no second toast (once a piece)", #toasts() == 1)
character:SetAttribute("MoveCarry", nil)
look()
pieces[4].PrimaryPart.Position = V3(-1, 2, -3)
character:SetAttribute("MoveCarry", 4)
look()
check(`the sofa at once after: it waits for the gap ({T.Gap} s)`, #toasts() == 1)
M.now += T.Gap + 0.01
look()
check("… then shows", #toasts() == 2 and child(toasts()[2], "Head").Text == "+ UNCOMMON")
check("… under the one before (the column's order)", toasts()[2].LayoutOrder > toasts()[1].LayoutOrder and box(toasts()[2]).y0 >= box(toasts()[1]).y1)
-- the load: a piece that left your hands welded into a van
character:SetAttribute("MoveCarry", nil)
look()
local cabinet = pieces[3]
cabinet.PrimaryPart.Position = V3(9, 2, -20) -- (out of your reach when it was lifted: no pick-up toast)
character:SetAttribute("MoveCarry", 3)
M.now += T.Gap + 0.01
look()
check("(the cabinet lifted far off: no pick-up toast)", #toasts() == 2)
character:SetAttribute("MoveCarry", nil)
cabinet.PrimaryPart.Position = V3(1, 2, -6)
look()
check("… out of your hands, on the floor: no load toast", #toasts() == 2)
local van = M.make("Model", { Name = "Sprinter" }, M.workspace)
local bed = M.make("Part", { Name = "BodyRoot" }, van)
M.make("WeldConstraint", { Part0 = bed, Part1 = cabinet.PrimaryPart }, cabinet.PrimaryPart)
look()
list = toasts()
check("your load of the Epic cabinet (welded into the van): its toast, the oldest gone (Toast.Most at once)", #list == T.Most and child(list[#list], "Head").Text == "+ EPIC", #list)
check("… an Epic one with its sound", M.played[#M.played] == "ding")
M.flush() -- (Toast.Seconds later)
check("… and they go after Toast.Seconds", #toasts() == 0)

-- ── A smaller phone and a computer ──────────────────────────────────────────
screen(true, 667, 375)
look()
check("667 × 375: the same stars", #LootStars.bubbles() == most)
screen(false, 1280, 800)
look()
local pc = LootStars.bubbles()
check(`a computer: up to {S.Count} within {S.Range} studs: the piano at 30 studs too`, #pc >= 6 and #pc <= S.Count and bubbleOf(pieces[6]) ~= nil and (bubbleOf(pieces[6]) :: any).MaxDistance == S.Range, #pc)
check("… the piano far: ★★★ faded but drawn", child(bubbleOf(pieces[6]), "Stars").TextTransparency > 0 and child(bubbleOf(pieces[6]), "Stars").TextTransparency < 1)
pieces[2].PrimaryPart.Position = V3(-2, 2, -3)
character:SetAttribute("MoveCarry", 2)
M.now += T.Gap + 0.01
look()
local pcToast = toasts()[1]
check("a computer: the Legendary painting's toast in the column at the left, on the screen", pcToast ~= nil and child(pcToast, "Head").Text == "+ LEGENDARY" and onScreen(box(pcToast)) and box(pcToast).x0 < M.width / 3)
character:SetAttribute("MoveCarry", nil)
pieces[2].PrimaryPart.Position = V3(-2, 1.5, -6)
look()
scene("loot-computer")
screen(false, 1920, 1080)
look()
check("1920 × 1080: the same", #LootStars.bubbles() == #pc)
M.flush()

-- ── The outlines: one budget with the enemies ───────────────────────────────
screen(false, 1280, 800)
for spot = 20, 50 do
	local rarity = Config.Collection.Order[spot % 5 + 1]
	stream(piece(spot, "sofa", rarity, 350, (spot % 7) - 3, 4 + spot % 20))
end
local O = L.Outline
M.enemies = 0
LootOutline.start()
local function lit()
	local out = {}
	local folder = M.workspace:FindFirstChild("LootOutlines")
	for _, h in (if folder then folder:GetChildren() else {}) do
		if h.Enabled and h.Adornee then
			table.insert(out, h)
		end
	end
	return out
end
local function pick()
	M.now += O.Every + 0.01
	M.services.RunService.Heartbeat:Fire()
end
pick()
local worn = lit()
check(`the outlines: {O.Count} at most on a computer, within the budget`, #worn == math.min(O.Count, OutlinePick.BUDGET), #worn)
local right, commons, rarest = true, 0, true
local lowest = 5
for _, h in worn do
	local model = h.Adornee
	local rarity = model:GetAttribute("Rarity")
	right = right and h.DepthMode == M.Enum.HighlightDepthMode.Occluded and h.FillTransparency == O.Fill and h.OutlineTransparency == O.Edge
		and sameColor(h.OutlineColor, tierColor(rarity)) and sameColor(h.FillColor, tierColor(rarity))
	if rarity == "common" then
		commons += 1
	end
	lowest = math.min(lowest, LootRules.rank(rarity))
end
for _, model in M.tagged[TAG] do
	if model.Parent and distance(model) <= O.Range and LootRules.rank(model:GetAttribute("Rarity")) > lowest then
		local has = false
		for _, h in worn do
			has = has or h.Adornee == model
		end
		rarest = rarest and has
	end
end
check("… each in its tier's colour, its soft fill (FillTransparency), Occluded (never through a wall)", right)
check("… no Common outlined, the rarer ones before the plainer", commons == 0 and rarest)
M.enemies = 14
pick()
check(`14 enemies outlined: the loot takes what is left ({OutlinePick.BUDGET - 14})`, #lit() == OutlinePick.BUDGET - 14, #lit())
check("(LootOutline makes room for the enemies: EnemyOutline.onSqueeze)", EnemyOutline.onSqueeze == LootOutline.squeeze)
EnemyOutline.onSqueeze(OutlinePick.BUDGET - 2)
local left = lit()
check("the enemies about to take more: the plainest outlines come off at once", #left == 2 and LootRules.rank(left[1].Adornee:GetAttribute("Rarity")) == 5 and LootRules.rank(left[2].Adornee:GetAttribute("Rarity")) == 5)
M.enemies = 0
pick()
local before = #lit()
local gone = lit()[1].Adornee
unstream(gone)
check("a piece gone: its Highlight back in the pool", #lit() == before - 1)
M.touch = true
pick()
check("a phone: DeviceBudget's share", #lit() == math.max(1, math.floor(O.Count * Lite.Count + 0.5)))
LootOutline.setOn(false)
check("off (this client): every loot outline off at once", #lit() == 0)

check("no warnings", #M.warnings == 0, M.warnings[1])
if dump then
	local function encode(value, out)
		local t = type(value)
		if t == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				table.insert(out, "null")
			elseif value == math.floor(value) and math.abs(value) < 1e15 then
				table.insert(out, string.format("%d", value))
			else
				table.insert(out, string.format("%.3f", value))
			end
		elseif t == "string" then
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(ch)
				return string.format("\\u%04x", string.byte(ch))
			end) .. '"')
		elseif t == "boolean" then
			table.insert(out, tostring(value))
		elseif t == "table" then
			if #value > 0 or next(value) == nil then
				table.insert(out, "[")
				for k, v in value do
					if k > 1 then
						table.insert(out, ",")
					end
					encode(v, out)
				end
				table.insert(out, "]")
			else
				table.insert(out, "{")
				local first = true
				for k, v in value do
					if not first then
						table.insert(out, ",")
					end
					first = false
					encode(tostring(k), out)
					table.insert(out, ":")
					encode(v, out)
				end
				table.insert(out, "}")
			end
		else
			table.insert(out, "null")
		end
	end
	local out = {}
	encode(scenes, out)
	print(table.concat(out))
else
	print("ALL LOOT CHECKS PASSED")
end
