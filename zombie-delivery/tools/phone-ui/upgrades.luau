-- 8.1 SANDBOX: the UPGRADES desk's window (client/UpgradeUi.luau, with client/CardKit.luau and the real shared data:
-- shared/UpgradeRules.luau, Config.SandboxUpgrades) run for real on sandbox_mock.luau's recorder, on a phone held
-- sideways (844 × 390: 844 × 354 under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen
-- (1920 × 1080): nothing when Config.Sandbox.On is false; the state asked at the start; the window only on the server's
-- "open"; one card an upgrade in Config's order with its name, level ("LV 1/4" and its segments), what it gives now
-- and next, the next price and BUY (green with the money; grey "NEED $X" without, a tap only says so; a gold MAX at the
-- top); BUY's request ({ kind = "buy", id, level }) once for a double tap; the money following the State remote; the
-- "bought" toast; no redraw for the same state; ✕, ESC, the gamepad's B, the menu and a tap beside it close it; on
-- each screen the card on the screen, every card shown (a phone: no scrolling), the texts fitting their room and a
-- phone's buttons a finger's size (44 px); a resize while open. 8.3 (design/warehouse-levels/KONTRAKT.md): five cards,
-- the ZDC Warehouse first (its own levels 1 … 5: "LV 4/5", five segments; "Garage · 2 stands" → "Next: Workshop · 4
-- stands"), all five whole on a phone held sideways (844 × 390, and 667 × 375: the cards lower); a new player's More
-- stands locked (grey "🔒 Needs the Big Warehouse" in place of the price and BUY, "Locked for now": a tap only says it,
-- never a request); the warehouse's BUY and its "bought" toast with the levels. `luau upgrades.luau -a dump` prints the
-- preview's scenes as JSON instead (sandbox_preview.py --scenes upgrades.luau).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local UpgradeRules = require("./UpgradeRules")
local MoveLayout = require("./MoveLayout")

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
	end)[1]
end
local function sentOn(remote)
	local list = {}
	for _, entry in M.sent do
		if entry.name == remote then
			table.insert(list, entry.args)
		end
	end
	return list
end
local function press(object)
	object.Activated:Fire()
end
local function key(code)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code] }, false)
end
local box = M.box
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function shown(object)
	local node = object
	while node do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end
-- Does a one-line text fit its label (after the scales above it)? A name may run long and is cut with "…"; a price,
-- a level or a button never.
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and object.Name ~= "Price" and object.Name ~= "Buy" and object.Name ~= "Level"
		if not object.TextWrapped and not truncated then
			local b = box(object)
			local room = b.x1 - b.x0
			local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
			if need > room + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(room)}`)
			end
		end
	end
	return bad
end
-- The buttons a finger taps on a phone: each at least 44 × 44 screen px.
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "UpgradeShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end

-- ── Screens ─────────────────────────────────────────────────────────────────
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end

-- ── The preview's scenes (sandbox_preview.py --scenes upgrades.luau) ────────
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
		out.trunc = p.TextTruncate ~= nil and p.TextTruncate.Name == "AtEnd"
	end
	if p.ClassName == "UICorner" then
		out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
	elseif p.ClassName == "UIStroke" then
		out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
	elseif p.ClassName == "UIScale" then
		out.scale = p.Scale
	elseif p.ClassName == "UIPadding" then
		out.pad = { p.PaddingLeft and p.PaddingLeft.Offset or 0, p.PaddingRight and p.PaddingRight.Offset or 0 }
	elseif p.ClassName == "ScrollingFrame" then
		out.canvas = { (p.CanvasPosition or M.Vector2.zero).X, (p.CanvasPosition or M.Vector2.zero).Y }
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	for _, child in n:GetChildren() do
		table.insert(kids, node(child))
	end
	if #kids > 0 then
		out.kids = kids
	end
	return out
end
local function scene(name)
	if not dump then
		return
	end
	local overlay = {}
	if M.touch then
		local TouchLayout = require("./TouchLayout")
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local UpgradeUi = require("./UpgradeUi")
screen(true, 844, 354)
Config.Sandbox.On = false
UpgradeUi.start()
check("Config.Sandbox.On false: UpgradeUi.start() does nothing", M.remotes.Upgrades == nil and #sentOn("Upgrades") == 0)
Config.Sandbox.On = true

-- ── On: the state asked, the window only on "open" ──────────────────────────
UpgradeUi.start()
local remote = M.remotes.Upgrades
check("on: the Upgrades remote asked for the state", remote ~= nil and #sentOn("Upgrades") == 1 and sentOn("Upgrades")[1][1].kind == "state")
remote.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 3, stands = 1, lights = 5, junk = 3 }, money = 2000 })
M.flush()
check("a state alone opens nothing", not UpgradeUi.isOpen() and UpgradeUi.state() ~= nil and UpgradeUi.state().money == 2000 and UpgradeUi.state().levels.junk == nil)
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
local gui = M.gui:FindFirstChild("UpgradeUi")
local window = gui and named(gui, "Upgrades")
check("\"open\" (the desk's prompt): the window in its ScreenGui \"UpgradeUi\"", UpgradeUi.isOpen() and window ~= nil and gui.ClassName == "ScreenGui")
local shade = named(gui, "UpgradeShade")
check("… modal: its shade frees the mouse (Modal)", shade ~= nil and shade.Modal == true)

local function cards()
	window = named(gui, "Upgrades")
	local list = named(window, "List")
	local out = {}
	for _, id in UpgradeRules.Order do
		table.insert(out, list:FindFirstChild(`Upgrade_{id}`))
	end
	return out
end
local function cardChecks(label)
	window = named(gui, "Upgrades")
	local cardBox = box(window)
	check(`{label}: the card on the screen`, inside(cardBox), show(cardBox))
	check(`{label}: … its texts fit`, #badTexts(window) == 0, badTexts(window)[1])
	local list = named(window, "List")
	local listBox = box(list)
	local every = true
	for _, made in cards() do
		local b = box(made)
		every = every and made ~= nil and b.y0 >= listBox.y0 - 0.5 and b.y1 <= listBox.y1 + 0.5 and b.x0 >= listBox.x0 - 0.5 and b.x1 <= listBox.x1 + 0.5
	end
	check(`{label}: … all five cards shown whole (no scrolling)`, every and #cards() == 5 and #UpgradeRules.Order == 5)
	if M.touch then
		check(`{label}: … every button a finger's size (BUY, ✕)`, #smallButtons(window) == 0, smallButtons(window)[1])
	end
end

-- ── The phone ───────────────────────────────────────────────────────────────
cardChecks("844 x 390")
local warehouse, stands, lights, engine, danny = table.unpack(cards())
check("the cards in Config's order: ZDC Warehouse (8.3), More stands, Showroom lights, Van engine, Danny's training", named(warehouse, "UpgradeName").Text == "ZDC Warehouse"
	and named(warehouse, "Emoji").Text == "🏭" and named(stands, "UpgradeName").Text == "More stands" and named(lights, "UpgradeName").Text == "Showroom lights"
	and named(engine, "UpgradeName").Text == "Van engine" and named(danny, "UpgradeName").Text == "Danny's training")
local function litOf(card, color)
	local n = 0
	for i = 1, 6 do
		local segment = named(card, `Level{i}`)
		n += if segment and segment.BackgroundColor3 == color then 1 else 0
	end
	return n
end
local money = require("./CardKit").Color.money
check("8.3: the ZDC Warehouse at its level 4 (upgrade 3): LV 4/5, five segments, four lit", named(warehouse, "Level").Text == "LV 4/5" and named(warehouse, "Level5") ~= nil
	and named(warehouse, "Level6") == nil and litOf(warehouse, money) == 4, named(warehouse, "Level").Text)
check("… \"Big Warehouse · 12 stands\" now, \"Logistics Center · 24 stands\" next, $30,000, NEED $28,000", named(warehouse, "Now").Text == "Big Warehouse · 12 stands"
	and named(warehouse, "Next").Text == "Next: Logistics Center · 24 stands" and named(warehouse, "Price").Text == "$30,000" and named(warehouse, "Buy").Text == "NEED $28,000",
	`{named(warehouse, "Now").Text} / {named(warehouse, "Next").Text}`)
check("More stands at 1 with $2,000: LV 1/4, 14 stands, next 16, $2,500, a grey NEED $500", named(stands, "Level").Text == "LV 1/4" and named(stands, "Now").Text == "14 display stands"
	and named(stands, "Next").Text == "Next: 16 display stands" and named(stands, "Price").Text == "$2,500" and named(stands, "Buy").Text == "NEED $500"
	and named(stands, "Buy").BackgroundColor3 == require("./CardKit").Buttons.shut.face, named(stands, "Buy").Text)
check("… its level's segments: one lit of four", litOf(stands, money) == 1 and named(stands, "Level4") ~= nil and named(stands, "Level5") == nil)
check("Showroom lights at its top: a gold MAX, \"Top level\", no price, no BUY", named(lights, "Max") ~= nil and named(lights, "Max").Text == "MAX" and named(lights, "Buy") == nil
	and named(lights, "Price") == nil and named(lights, "Next").Text == "Top level" and named(lights, "Now").Text == "Income ×1.61")
check("Van engine at 0: $600 in money green, a green BUY", named(engine, "Price").Text == "$600" and named(engine, "Price").TextColor3 == require("./CardKit").Color.money
	and named(engine, "Buy").Text == "BUY" and named(engine, "Next").Text == "Next: Top speed +5%")
check("the subtitle: your money", string.find(named(window, "Subtitle").Text, "$2,000", 1, true) ~= nil, named(window, "Subtitle").Text)
scene("upgrades-phone")

-- BUY
local before = #sentOn("Upgrades")
press(named(engine, "Buy"))
press(named(engine, "Buy"))
local sent = sentOn("Upgrades")
check("BUY sends { kind = \"buy\", id = \"engine\", level = 1 } once for a double tap; the button waits (…)", #sent == before + 1 and sent[#sent][1].kind == "buy" and sent[#sent][1].id == "engine"
	and sent[#sent][1].level == 1 and named(engine, "Buy").Text == "…")
local toastsBefore = #M.toasts
before = #sentOn("Upgrades")
press(named(stands, "Buy"))
check("a grey NEED button sends nothing, it says how much is missing", #sentOn("Upgrades") == before and M.toasts[#M.toasts] == "More stands: you need $500 more.", M.toasts[#M.toasts])
-- the server's answer
remote.OnClientEvent:Fire({ kind = "bought", id = "engine", level = 1 })
check("\"bought\": a toast with what it gives", M.toasts[#M.toasts] == "Van engine: level 1 · Top speed +5%" and #M.toasts == toastsBefore + 2, M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 3, stands = 1, lights = 5, engine = 1 }, money = 1400 })
M.flush()
engine = cards()[4]
check("the new state: drawn again (the engine LV 1/3, its next level $1,800, NEED $400)", named(engine, "Level").Text == "LV 1/3" and named(engine, "Price").Text == "$1,800" and named(engine, "Buy").Text == "NEED $400", named(engine, "Buy").Text)
local same = named(gui, "Upgrades")
remote.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 3, stands = 1, lights = 5, engine = 1 }, money = 1400 })
M.flush()
check("the same state again: no redraw (a tap is never lost)", named(gui, "Upgrades") == same)
-- the money from the State remote (a sale while it is open)
M.remotes.State.OnClientEvent:Fire({ money = 3000 })
M.flush()
stands = cards()[2]
check("the money follows the State remote: More stands' BUY lights up at $3,000", named(stands, "Buy").Text == "BUY" and string.find(named(named(gui, "Upgrades"), "Subtitle").Text, "$3,000", 1, true) ~= nil)
-- closing
key("Escape")
check("ESC closes it", not UpgradeUi.isOpen() and named(gui, "Upgrades") == nil)
UpgradeUi.open()
check("UpgradeUi.open() opens it again (the state kept)", UpgradeUi.isOpen() and named(gui, "Upgrades") ~= nil)
key("ButtonB")
check("the gamepad's B closes it", not UpgradeUi.isOpen())
UpgradeUi.open()
press(named(gui, "UpgradeShade"))
check("a tap beside the card closes it", not UpgradeUi.isOpen())
UpgradeUi.open()
press(named(named(gui, "Upgrades"), "Close"))
check("✕ closes it", not UpgradeUi.isOpen())

-- ── 8.3: a new player (a garage, More stands locked) ────────────────────────
remote.OnClientEvent:Fire({ kind = "state", levels = {}, money = 2000 })
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
cardChecks("844 x 390, a new player")
warehouse, stands = cards()[1], cards()[2]
check("8.3: a new player's warehouse: LV 1/5 (one segment lit of five), \"Garage · 2 stands\", next \"Workshop · 4 stands\", $1,500, a green BUY", named(warehouse, "Level").Text == "LV 1/5"
	and litOf(warehouse, money) == 1 and named(warehouse, "Level5") ~= nil and named(warehouse, "Now").Text == "Garage · 2 stands" and named(warehouse, "Next").Text == "Next: Workshop · 4 stands"
	and named(warehouse, "Price").Text == "$1,500" and named(warehouse, "Buy").Text == "BUY", `{named(warehouse, "Now").Text} / {named(warehouse, "Next").Text}`)
local locked = named(stands, "Locked")
check("… More stands locked: \"🔒 Needs the Big Warehouse\" grey in place of the price and BUY, \"Locked for now\" grey", locked ~= nil and locked.Text == "🔒 Needs the Big Warehouse"
	and locked.BackgroundColor3 == require("./CardKit").Buttons.shut.face and named(stands, "Buy") == nil and named(stands, "Price") == nil and named(stands, "Max") == nil
	and named(stands, "Next").Text == "Locked for now" and named(stands, "Next").TextColor3 ~= money, if locked then locked.Text else "no Locked")
check("… the reason inside its card, right of its words", (function()
	local b, card, words = box(locked), box(stands), box(named(stands, "Next"))
	return b.x0 >= card.x0 and b.x1 <= card.x1 + 0.5 and b.y0 >= card.y0 - 0.5 and b.y1 <= card.y1 + 0.5 and words.x1 <= b.x0 + 0.5
end)(), show(box(locked)))
local toastsNow = #M.toasts
before = #sentOn("Upgrades")
press(locked)
check("… a tap on it sends nothing, only says why", #sentOn("Upgrades") == before and #M.toasts == toastsNow + 1 and M.toasts[#M.toasts] == "More stands: 🔒 Needs the Big Warehouse", M.toasts[#M.toasts])
scene("upgrades-phone-locked")
press(named(warehouse, "Buy"))
sent = sentOn("Upgrades")
check("the warehouse's BUY sends { kind = \"buy\", id = \"warehouse\", level = 1 } (its upgrade level)", #sent == before + 1 and sent[#sent][1].kind == "buy" and sent[#sent][1].id == "warehouse" and sent[#sent][1].level == 1)
remote.OnClientEvent:Fire({ kind = "bought", id = "warehouse", level = 1 })
check("\"bought\": \"ZDC Warehouse: level 2 · Workshop · 4 stands\" (its own level, the effect with the levels)", M.toasts[#M.toasts] == "ZDC Warehouse: level 2 · Workshop · 4 stands", M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 3 }, money = 2000 })
M.flush()
stands = cards()[2]
check("at the Big Warehouse (level 4) More stands opens: its BUY, no lock, \"12 display stands\" → \"14\"", named(stands, "Locked") == nil and named(stands, "Buy") ~= nil and named(stands, "Price").Text == "$1,000"
	and named(stands, "Now").Text == "12 display stands" and named(stands, "Next").Text == "Next: 14 display stands", named(stands, "Now").Text)
remote.OnClientEvent:Fire({ kind = "bought", id = "stands", level = 1 })
check("… its \"bought\" toast counts on the warehouse's base: \"More stands: level 1 · 14 display stands\"", M.toasts[#M.toasts] == "More stands: level 1 · 14 display stands", M.toasts[#M.toasts])
UpgradeUi.close()

-- every upgrade at its top
remote.OnClientEvent:Fire({ kind = "state", levels = UpgradeRules.full(), money = 54000 })
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
cardChecks("844 x 390, everything bought")
local maxes = 0
for _, made in cards() do
	maxes += if named(made, "Max") then 1 else 0
end
check("… five gold MAX", maxes == 5)
scene("upgrades-phone-max")
UpgradeUi.close()

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
remote.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 4, stands = 2, lights = 1, danny = 3 }, money = 4200 })
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	UpgradeUi.open()
	M.flush()
	local label = `{size[1]} x {size[2] + 36}`
	cardChecks(label)
	local plan = UpgradeUi.layout(M.width, M.height, false)
	check(`{label}: … centred`, math.abs((plan.x + plan.w * plan.scale / 2) - M.width / 2) <= 1 and math.abs((plan.y + plan.h * plan.scale / 2) - M.height / 2) <= 1)
	scene(`upgrades-{size[3]}`)
	key("Escape")
end

-- ── A resize while it is open ───────────────────────────────────────────────
UpgradeUi.open()
screen(true, 844, 354)
window = named(gui, "Upgrades")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(window) - UpgradeUi.layout(844, 354, true).scale) < 0.001 and #smallButtons(window) == 0)
UpgradeUi.close()
-- 8.3: a smaller phone (667 × 375): the cards lower still, all five whole; never below their words and a finger's BUY
remote.OnClientEvent:Fire({ kind = "state", levels = {}, money = 900 })
screen(true, 667, 339)
UpgradeUi.open()
M.flush()
cardChecks("667 x 375, a new player")
local small = UpgradeUi.layout(667, 339, true)
check("… its cards lower than a computer's, never under the words (52) and a finger's BUY", small.rowH < UpgradeUi.layout(1280, 764, false).rowH and small.rowH >= 56 and small.rowH >= small.button + 8, small.rowH)
scene("upgrades-small-phone")
UpgradeUi.close()

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
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(c)
				return string.format("\\u%04x", string.byte(c))
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
	print("ALL UPGRADE UI CHECKS PASSED")
end
