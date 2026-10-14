-- 8.3 SANDBOX: the PAINT shop's window (client/VanPaintUi.luau, with client/CardKit.luau and the real shared data:
-- shared/VanPaintRules.luau, Config.VanPaint; its 3D picture client/VanPaintPreview.luau recorded: what it is asked to
-- show) run for real on sandbox_mock.luau's recorder, on a phone held sideways (844 × 390: 844 × 354 under Roblox's top
-- bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080): nothing when Config.Sandbox.On is
-- false; the state asked at the start; the window only on the server's "open"; the picture of your van in what you wear;
-- the PAINT tab's swatches in Config's order (their chips, names and lines: ✓ ON VAN, OWNED, the price, 🔒 LOCKED), the
-- swatch you wear looked at first; a tapped swatch looked at (the picture with it and the livery you wear; its name,
-- line and button: BUY $X once for a double tap, NEED $X saying how much is missing, 🔒 LOCKED saying what unlocks it,
-- WEAR, ✓ ON YOUR VAN); the server's "bought" / "worn" toasts and the state drawn again; the LIVERY tab (a band on your
-- body's colour, the picture with your paint); the money from the State remote lighting BUY; a paid milestone opening
-- Collector gold; no redraw for the same state; ✕, ESC, the gamepad's B, the menu and a tap beside it close it (the
-- picture dropped); the gamepad's selection landing on the swatch you wear and kept inside; on each screen the card on
-- the screen, the texts fitting their room, every swatch in the grid's width and a phone's buttons a finger's size
-- (44 px); a resize while open. `luau vanpaint.luau -a dump` prints the preview's scenes as JSON instead
-- (sandbox_preview.py --scenes vanpaint.luau).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local Rules = require("./VanPaintRules")
local MoveLayout = require("./MoveLayout")
local CardKit = require("./CardKit")

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
-- Does a one-line text fit its label (after the scales above it)? A name or a line may run long and is cut with "…"; a
-- price, a status or a button never.
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and object.Name ~= "Status" and object.Name ~= "Action"
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
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "PaintShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
local function rgb(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function isRgb(c, want)
	return c ~= nil and rgb(c) == string.format("%d,%d,%d", want[1], want[2], want[3])
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

-- ── The preview's scenes (sandbox_preview.py --scenes vanpaint.luau) ────────
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
local PaintUi = require("./VanPaintUi")
screen(true, 844, 354)
Config.Sandbox.On = false
PaintUi.start()
check("Config.Sandbox.On false: VanPaintUi.start() does nothing", M.remotes.VanPaint == nil and #sentOn("VanPaint") == 0)
Config.Sandbox.On = true

-- ── On: the state asked, the window only on "open" ──────────────────────────
PaintUi.start()
local remote = M.remotes.VanPaint
check("on: the VanPaint remote asked for the state", remote ~= nil and #sentOn("VanPaint") == 1 and sentOn("VanPaint")[1][1].kind == "state")
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "junk", 5 }, worn = { paint = "red", livery = "zdc" }, money = 900, paid = {} })
M.flush()
check("a state alone opens nothing (junk owned ids dropped)", not PaintUi.isOpen() and PaintUi.state() ~= nil and PaintUi.state().money == 900 and PaintUi.state().owned.red == true
	and PaintUi.state().owned.junk == nil)
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
local gui = M.gui:FindFirstChild("VanPaintUi")
local window = gui and named(gui, "VanPaint")
check("\"open\" (the van's prompt): the window in its ScreenGui \"VanPaintUi\"", PaintUi.isOpen() and window ~= nil and gui.ClassName == "ScreenGui")
check("… modal: its shade frees the mouse (Modal)", named(gui, "PaintShade") ~= nil and named(gui, "PaintShade").Modal == true)
local shows = M.paintShows
local function lastShow()
	return shows[#shows]
end
check("… the picture: your van in what you wear (Fire red, ZDC classic) in the Picture frame", #shows >= 1 and lastShow().look.paint == "red" and lastShow().look.livery == "zdc"
	and lastShow().holder == named(window, "Picture"))

local function swatches()
	window = named(gui, "VanPaint")
	local grid = named(window, "Grid")
	local out = {}
	for _, child in grid:GetChildren() do
		if string.sub(child.Name, 1, 7) == "Swatch_" then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.Position.Y.Offset < b.Position.Y.Offset or (a.Position.Y.Offset == b.Position.Y.Offset and a.Position.X.Offset < b.Position.X.Offset)
	end)
	return out
end
local function swatch(id)
	return named(named(gui, "VanPaint"), `Swatch_{id}`)
end
local function cardChecks(label)
	window = named(gui, "VanPaint")
	local cardBox = box(window)
	check(`{label}: the card on the screen`, inside(cardBox), show(cardBox))
	check(`{label}: … its texts fit`, #badTexts(window) == 0, badTexts(window)[1])
	local grid = named(window, "Grid")
	local gridBox = box(grid)
	local fits = true
	for _, made in swatches() do
		local b = box(made)
		fits = fits and b.x0 >= gridBox.x0 - 0.5 and b.x1 <= gridBox.x1 + 0.5
	end
	local list = swatches()
	local last = list[#list]
	check(`{label}: … every swatch in the grid's width, the canvas holds them all`, fits and last ~= nil and last.Position.Y.Offset + last.Size.Y.Offset <= grid.CanvasSize.Y.Offset + 0.5)
	local picture = box(named(window, "Picture"))
	local action = box(named(window, "Action"))
	check(`{label}: … the picture over the swatch's line and button, left of the grid`, picture.y1 <= box(named(window, "SelName")).y0 + 0.5 and box(named(window, "SelInfo")).y1 <= action.y0 + 0.5
		and picture.x1 <= gridBox.x0 and action.y1 <= cardBox.y1 + 0.5 and picture.y1 - picture.y0 > 120, `{show(picture)} {show(gridBox)}`)
	if M.touch then
		check(`{label}: … every button a finger's size (the swatches, the tabs, the button, ✕)`, #smallButtons(window) == 0, smallButtons(window)[1])
	end
end

-- ── The phone ───────────────────────────────────────────────────────────────
cardChecks("844 x 390")
local list = swatches()
local order, expected = {}, {}
for _, made in list do
	table.insert(order, string.sub(made.Name, 8))
end
for _, item in Rules.Paints do
	table.insert(expected, item.id)
end
check("the PAINT tab: a swatch a colour in Config's order", table.concat(order, ",") == table.concat(expected, ","), table.concat(order, ","))
check("… the tab lit (its underline), LIVERY not", named(named(window, "Tab_paint"), "Underline") ~= nil and named(named(window, "Tab_livery"), "Underline") == nil)
check("the red's swatch: its chip in the colour, ✓ ON VAN; the cream OWNED (the factory's); white its price in green ($300 of $900); chrome $50,000 grey (8.3 economy)",
	isRgb(named(swatch("red"), "Chip").BackgroundColor3, { 176, 32, 32 }) and named(swatch("red"), "Status").Text == "✓ ON VAN" and named(swatch("cream"), "Status").Text == "OWNED"
	and named(swatch("white"), "Status").Text == "$300" and named(swatch("white"), "Status").TextColor3 == CardKit.Color.money and named(swatch("chrome"), "Status").Text == "$50,000"
	and named(swatch("chrome"), "Status").TextColor3 == CardKit.Color.dim)
check("… Collector gold: 🔒 LOCKED, a gold frame (premium)", named(swatch("gold"), "Status").Text == "🔒 LOCKED" and named(swatch("gold"), "Edge").Color == CardKit.Color.gold)
check("the swatch you wear looked at first: its frame lit, \"Fire red · paint\", on your van, ✓ ON YOUR VAN", PaintUi.view().selected == "red" and named(swatch("red"), "Edge").Thickness == 2
	and named(window, "SelName").Text == "Fire red · paint" and named(window, "SelInfo").Text == "On your van now" and named(window, "Action").Text == "✓ ON YOUR VAN")
check("the subtitle: your money", string.find(named(window, "Subtitle").Text, "$900", 1, true) ~= nil, named(window, "Subtitle").Text)
scene("paint-phone")

-- a swatch tapped: looked at, the picture shows it
local before = #shows
local card = named(gui, "VanPaint")
press(swatch("white"))
check("a tap on Arctic white: looked at (no rebuild), the picture shows it with the livery you wear", named(gui, "VanPaint") == card and PaintUi.view().selected == "white" and #shows == before + 1
	and lastShow().look.paint == "white" and lastShow().look.livery == "zdc")
check("… its line and BUY $300 (green), its frame lit, the red's not", named(window, "SelInfo").Text == "$300 · yours for good once bought" and named(window, "Action").Text == "BUY $300"
	and named(window, "Action").BackgroundColor3 == CardKit.Buttons.good.face and named(swatch("white"), "Edge").Thickness == 2 and named(swatch("red"), "Edge").Thickness == 1)
local sent = #sentOn("VanPaint")
press(named(window, "Action"))
press(named(window, "Action"))
local list2 = sentOn("VanPaint")
check("BUY sends { kind = \"buy\", id = \"white\" } once for a double tap; the button waits (…)", #list2 == sent + 1 and list2[#list2][1].kind == "buy" and list2[#list2][1].id == "white" and named(window, "Action").Text == "…")
local toasts = #M.toasts
remote.OnClientEvent:Fire({ kind = "bought", id = "white" })
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "white" }, worn = { paint = "white", livery = "zdc" }, money = 600, paid = {} })
M.flush()
check("\"bought\": the toast; the new state drawn (white ✓ ON VAN, its button ✓ ON YOUR VAN)", M.toasts[#M.toasts] == "Arctic white is yours: on your van now." and #M.toasts == toasts + 1
	and named(swatch("white"), "Status").Text == "✓ ON VAN" and named(named(gui, "VanPaint"), "Action").Text == "✓ ON YOUR VAN", M.toasts[#M.toasts])
window = named(gui, "VanPaint")
local same = window
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "white" }, worn = { paint = "white", livery = "zdc" }, money = 600, paid = {} })
M.flush()
check("the same state again: no redraw (a tap is never lost)", named(gui, "VanPaint") == same)

-- NEED, LOCKED, WEAR
press(swatch("chrome"))
check("Mirror chrome with $600: a grey NEED $49,400 (8.3 economy)", named(window, "Action").Text == "NEED $49,400" and named(window, "Action").BackgroundColor3 == CardKit.Buttons.shut.face)
sent = #sentOn("VanPaint")
press(named(window, "Action"))
check("… a tap sends nothing, it says how much is missing", #sentOn("VanPaint") == sent and M.toasts[#M.toasts] == "Mirror chrome: you need $49,400 more.", M.toasts[#M.toasts])
press(swatch("gold"))
check("Collector gold: its line says what unlocks it, 🔒 LOCKED", named(window, "SelInfo").Text == "🔒 Collection book: A legendary!" and named(window, "Action").Text == "🔒 LOCKED")
press(named(window, "Action"))
check("… a tap sends nothing, it says what unlocks it (\"…your collection book: a legendary!\", no \"!.\")", #sentOn("VanPaint") == sent
	and M.toasts[#M.toasts] == "Collector gold unlocks with your collection book: a legendary!", M.toasts[#M.toasts])
press(swatch("red"))
check("the red (yours): WEAR", named(window, "Action").Text == "WEAR" and named(window, "SelInfo").Text == "Yours: wear it for free")
press(named(window, "Action"))
list2 = sentOn("VanPaint")
check("… sends { kind = \"wear\", id = \"red\" }", #list2 == sent + 1 and list2[#list2][1].kind == "wear" and list2[#list2][1].id == "red")
remote.OnClientEvent:Fire({ kind = "worn", id = "red" })
check("\"worn\": the toast", M.toasts[#M.toasts] == "On your van now: Fire red.", M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "white" }, worn = { paint = "red", livery = "zdc" }, money = 600, paid = {} })
M.flush()
check("… a refused or answered request: the button live again", named(named(gui, "VanPaint"), "Action").Text == "✓ ON YOUR VAN")

-- the LIVERY tab
press(named(named(gui, "VanPaint"), "Tab_livery"))
M.flush()
window = named(gui, "VanPaint")
list = swatches()
order, expected = {}, {}
for _, made in list do
	table.insert(order, string.sub(made.Name, 8))
end
for _, item in Rules.Liveries do
	table.insert(expected, item.id)
end
check("LIVERY: its swatches in Config's order, the one you wear looked at (ZDC classic)", table.concat(order, ",") == table.concat(expected, ",") and PaintUi.view().tab == "livery"
	and PaintUi.view().selected == "zdc" and named(window, "Action").Text == "✓ ON YOUR VAN", table.concat(order, ","))
check("… a livery's chip: your body's red with its band (racing: the light contrast)", isRgb(named(swatch("racing"), "Chip").BackgroundColor3, { 176, 32, 32 })
	and isRgb(named(named(swatch("racing"), "Chip"), "Band").BackgroundColor3, Config.VanPaint.Contrast.Light))
press(swatch("racing"))
check("Racing stripes looked at: the picture with your paint (red); NEED $900 with $600", lastShow().look.paint == "red" and lastShow().look.livery == "racing" and #lastShow().look.roof == 2
	and named(window, "Action").Text == "NEED $900")
scene("paint-phone-livery")
-- the money from the State remote (a sale while it is open)
M.remotes.State.OnClientEvent:Fire({ money = 5000 })
M.flush()
window = named(gui, "VanPaint")
check("the money follows the State remote: BUY $1,500 lights up, the subtitle says $5,000", named(window, "Action").Text == "BUY $1,500" and string.find(named(window, "Subtitle").Text, "$5,000", 1, true) ~= nil
	and PaintUi.view().selected == "racing")
-- a milestone paid: Collector gold opens
press(named(window, "Tab_paint"))
M.flush()
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "white" }, worn = { paint = "red", livery = "zdc" }, money = 5000, paid = { "legendary" } })
M.flush()
window = named(gui, "VanPaint")
press(swatch("gold"))
check("the book paid \"A legendary!\" (8.3 economy): Collector gold BUY $5,000", named(swatch("gold"), "Status").Text == "$5,000" and named(window, "Action").Text == "BUY $5,000")
scene("paint-phone-gold")

-- closing
local cleared = M.paintCleared or 0
key("Escape")
check("ESC closes it (the picture dropped)", not PaintUi.isOpen() and named(gui, "VanPaint") == nil and (M.paintCleared or 0) == cleared + 1)
PaintUi.open()
check("VanPaintUi.open() opens it again (the state kept; what you wear looked at)", PaintUi.isOpen() and named(gui, "VanPaint") ~= nil and PaintUi.view().selected == "red" and PaintUi.view().tab == "paint")
key("ButtonB")
check("the gamepad's B closes it", not PaintUi.isOpen())
PaintUi.open()
press(named(gui, "PaintShade"))
check("a tap beside the card closes it", not PaintUi.isOpen())
PaintUi.open()
press(named(named(gui, "VanPaint"), "Close"))
check("✕ closes it", not PaintUi.isOpen())
M.services.GuiService.MenuOpened:Fire()

-- the gamepad
M.gamepad = true
PaintUi.open()
check("a gamepad: the selection lands on the swatch you wear", M.focus == swatch("red"), M.focus and M.focus.Name)
M.focus = swatch("navy")
remote.OnClientEvent:Fire({ kind = "state", owned = { "red", "white", "navy" }, worn = { paint = "red", livery = "zdc" }, money = 5000, paid = { "legendary" } })
M.flush()
check("… a redraw keeps it where it was (inside the window)", M.focus ~= nil and M.focus.Name == "Swatch_navy" and M.focus.Parent ~= nil)
check("… the window keeps the selection inside (a selection group)", named(gui, "VanPaint").SelectionGroup == true)
M.gamepad = false
PaintUi.close()

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	PaintUi.open()
	M.flush()
	local label = `{size[1]} x {size[2] + 36}`
	cardChecks(label)
	local plan = PaintUi.layout(M.width, M.height, false)
	check(`{label}: … centred`, math.abs((plan.x + plan.w * plan.scale / 2) - M.width / 2) <= 1 and math.abs((plan.y + plan.h * plan.scale / 2) - M.height / 2) <= 1)
	scene(`paint-{size[3]}`)
	key("Escape")
end

-- ── A resize while it is open ───────────────────────────────────────────────
PaintUi.open()
screen(true, 844, 354)
window = named(gui, "VanPaint")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(window) - PaintUi.layout(844, 354, true).scale) < 0.001 and #smallButtons(window) == 0)
PaintUi.close()

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
	print("ALL PAINT SHOP UI CHECKS PASSED")
end
