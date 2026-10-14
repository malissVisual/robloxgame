-- 8.3 SANDBOX, the PAINT shop on the server: the real server/VanPaint.luau with the real server/PlayerData.luau
-- (VanPaintServer.luau, PlayerDataServer.luau through tests/run_tests.py; shared/VanLook.luau on the recorder) on
-- tests/runtime/CollectionRuntime.luau's players, DataStore, clock and Net and tests/runtime/VanPaintRuntime.luau's vans.
-- Joining (the state once; a new player: the factory's look), the van painted as it is built (the hook before it still
-- called; the panels, the stripes, the logo's ink, the Blender look's pieces and its attributes, the roof's stripes;
-- nothing that collides changed), the 🎨 Paint van prompt (the owner's only, on at home, off away, its press opens the
-- window or says why not), buying (the money taken with the reason "VanPaint", owned for good, worn at once, the live van
-- repainted, "bought"), wearing (free; only what you own), the refusals (no money, an unknown id, a locked premium, owned
-- already, no save, garbage on the remote, the rate limit), the premium unlocked by the collection book's milestone (the
-- state follows the paid milestone), the admin's UNLOCK / RESET, and the save round trip (the flag, twice; an old save,
-- a lock-only record). Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local P = require("./VanPaintRuntime")
local Config = require("./Config")
local Rules = require("./VanPaintRules")
local SandboxMap = require("./SandboxMap")
local PlayerData = require("./PlayerDataServer")
local VanPaint = require("./VanPaintServer")
local M = P.Mock

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
local function kinds(messages: { any }, kind: string): { any }
	local out = {}
	for _, m in messages do
		if type(m) == "table" and m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end
local function lastNotice(player: any, from: number?): string
	local said = E.received(player, "Notice", from)
	return tostring(said[#said] or "")
end
local function rgbOf(c: any): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function isRgb(c: any, want: { number }): boolean
	return c ~= nil and rgbOf(c) == string.format("%d,%d,%d", want[1], want[2], want[3])
end
local function find(model: any, name: string): any
	for _, d in model:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function all(model: any, name: string): { any }
	local out = {}
	for _, d in model:GetDescendants() do
		if d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end
local function promptOf(car: any): any
	local point = car.chassis:FindFirstChild("PaintPoint")
	return point and point:FindFirstChild("PaintPrompt")
end
-- every part's collision as it is (what the paint must never change)
local function physics(model: any): string
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name ~= "VanLivery" then
			table.insert(out, `{d.Name}:{tostring(d.CanCollide)}:{tostring(d.CanQuery)}:{tostring(d.Massless)}:{tostring(d.Anchored)}`)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end

PlayerData.start()
VanPaint.start()
local spot = SandboxMap.Plots[1].vanSpot
local home = M.CFrame.new(spot.x, spot.y, spot.z)
local far = M.CFrame.new(spot.x + 80, spot.y, spot.z - 60)

-- ── Joining ────────────────────────────────────────────────────────────────
local mark = #E.sent
local A = E.join(101, "Ann") -- a new player
E.plotOf[A] = SandboxMap.Plots[1]
local profileA = PlayerData.get(A) :: any
E.flush()
local states = kinds(E.received(A, "VanPaint", mark), "state")
check("a new player: nothing bought, the factory's worn; the state goes out once (the money)", same(profileA.vanPaint, Rules.empty()) and #states == 1 and same(states[1].owned, {})
	and states[1].worn.paint == "cream" and states[1].worn.livery == "zdc" and states[1].money == Config.Sandbox.StartMoney, #states)
check("… a copy through VanPaint.saved", same(VanPaint.saved(A), Rules.empty()) and VanPaint.saved(A) ~= profileA.vanPaint)

-- ── The van as it is built ─────────────────────────────────────────────────
local styledBefore = #P.styled
local car = P.van(A, home)
check("the hook before VanPaint's (Vehicles.onStyle) still runs", #P.styled == styledBefore + 1 and P.styled[#P.styled] == car)
local model = car.model
check("the factory's look: the panels cream, the stripes ZDC red, no roof stripes, the ids on the model", isRgb(find(model, "CargoSide").Color, { 232, 226, 210 }) and isRgb(find(model, "Stripe").Color, { 179, 38, 30 })
	and model:FindFirstChild("VanLivery") == nil and model:GetAttribute("VanPaint") == "cream" and model:GetAttribute("VanLivery") == "zdc" and model:GetAttribute("PaintColor") == nil
	and model:GetAttribute("StripeColor") == nil)
local roles = 0
for _, p in car.paintParts do
	roles += if p:GetAttribute("VanPaintRole") == "body" then 1 else 0
end
check("… the panels tagged VanPaintRole \"body\" (a copy of the van knows them: the window's picture)", roles == #car.paintParts)
local prompt = promptOf(car)
check("the 🎨 Paint van prompt on the van's chassis (PaintPoint), the owner's only (tagged, CargoOwner)", prompt ~= nil and prompt.ClassName == "ProximityPrompt" and prompt.ActionText == "🎨 Paint van"
	and prompt:GetAttribute("CargoOwner") == 101 and P.tags[Config.Cargo.PromptTag] ~= nil and P.tags[Config.Cargo.PromptTag][prompt] == true and prompt.MaxActivationDistance == Config.VanPaint.Prompt.Reach)
local point = car.chassis:FindFirstChild("PaintPoint")
local at = point and point.props.Position -- (the recorder's Attachment: its own Position)
check("… on the driver's side of the cargo box (Config.VanPaint.Prompt.At in the van's frame, from the chassis' middle)", at ~= nil and math.abs(at.X - Config.VanPaint.Prompt.At[1]) < 1e-6
	and math.abs(at.Y - (Config.VanPaint.Prompt.At[2] - 1.8)) < 1e-6 and math.abs(at.Z - Config.VanPaint.Prompt.At[3]) < 1e-6)
check("… on: the van stands at its plot's vanSpot", prompt.Enabled == true)

-- the prompt pressed
mark = #E.sent
prompt.Triggered:Fire(A)
local opened = kinds(E.received(A, "VanPaint", mark), "open")
check("pressed by its owner at home: the state, then \"open\"", #opened == 1 and #kinds(E.received(A, "VanPaint", mark), "state") == 1)
local B = E.join(202, "Ben")
E.plotOf[B] = SandboxMap.Plots[2]
mark = #E.sent
prompt.Triggered:Fire(B)
check("pressed by somebody else: nothing", #E.received(B, "VanPaint", mark) == 0 and #kinds(E.received(A, "VanPaint", mark), "open") == 0)
-- driven away: off, and a press (a stale one) says why
car.chassis.CFrame = far * M.CFrame.new(0, 1.8, 0)
E.advance(Config.VanPaint.Prompt.Every + 0.01)
check("driven away from home: the prompt off (looked at every Prompt.Every s)", prompt.Enabled == false)
mark = #E.sent
prompt.Triggered:Fire(A)
check("… a press away from home: no window, says to park at the warehouse", #kinds(E.received(A, "VanPaint", mark), "open") == 0 and string.find(lastNotice(A, mark), "Park your van", 1, true) ~= nil, lastNotice(A, mark))
car.chassis.CFrame = home * M.CFrame.new(0, 1.8, 0)
E.advance(Config.VanPaint.Prompt.Every + 0.01)
check("… back home: on again", prompt.Enabled == true)
E.plotOf[A] = nil
E.advance(Config.VanPaint.Prompt.Every + 0.01)
check("no plot of your own: off", prompt.Enabled == false)
E.plotOf[A] = SandboxMap.Plots[1]
E.advance(Config.VanPaint.Prompt.Every + 0.01)

-- ── Buying ──────────────────────────────────────────────────────────────────
local before = physics(model)
local moneyAt = #money
mark = #E.sent
E.fire(A, "VanPaint", { kind = "buy", id = "red" })
E.flush()
check("Fire red with the start money ($500): bought, the money taken", profileA.money == Config.Sandbox.StartMoney - 500 and profileA.vanPaint.owned.red == true, profileA.money)
local spent = money[moneyAt + 1]
check("… PlayerData.spend: -$500, the reason \"VanPaint\" (AnalyticsPlan's sink), the SKU its id", spent ~= nil and spent.delta == -500 and spent.reason == "VanPaint" and spent.sku == "red" and #money == moneyAt + 1
	and require("./AnalyticsPlan").Sinks.VanPaint == "Shop")
check("… worn at once: the live van's panels red, its attributes say so (the Blender look's PaintColor)", profileA.vanPaint.worn.paint == "red" and isRgb(find(model, "CargoSide").Color, { 176, 32, 32 })
	and isRgb(find(model, "SideDoor").Color, { 176, 32, 32 }) and isRgb(find(model, "Roof").Color, { 176, 32, 32 }) and model:GetAttribute("VanPaint") == "red" and isRgb(model:GetAttribute("PaintColor"), { 176, 32, 32 }))
check("… the glass, the seat, the logo's ink untouched", isRgb(find(model, "Windscreen").Color, { 40, 58, 68 }) and isRgb(find(model, "DriveSeat").Color, { 232, 226, 210 }))
local msgs = E.received(A, "VanPaint", mark)
check("… the client: \"bought\" and one new state (owned, worn, the money)", #kinds(msgs, "bought") == 1 and kinds(msgs, "bought")[1].id == "red" and #kinds(msgs, "state") == 1
	and same(kinds(msgs, "state")[1].owned, { "red" }) and kinds(msgs, "state")[1].worn.paint == "red" and kinds(msgs, "state")[1].money == 0)
check("… nothing that collides changed (every part's CanCollide, CanQuery, Massless, Anchored as built)", physics(model) == before)

-- ── Refusals ────────────────────────────────────────────────────────────────
E.advance(2)
mark = #E.sent
E.fire(A, "VanPaint", { kind = "buy", id = "black" })
check("no money ($0 for Midnight black's $600): refused, the notice says the price and the money", profileA.vanPaint.owned.black == nil and profileA.money == 0
	and lastNotice(A, mark) == "Midnight black costs $600: you have $0.", lastNotice(A, mark))
check("… the state again (the window drawn anew)", #kinds(E.received(A, "VanPaint", mark), "state") == 1)
PlayerData.addMoney(A, 50000, "Admin")
mark = #E.sent
E.fire(A, "VanPaint", { kind = "buy", id = "purple" })
check("an unknown id: refused (\"That's no paint.\"), no money taken", lastNotice(A, mark) == "That's no paint." and profileA.money == 50000)
E.advance(1)
mark = #E.sent
E.fire(A, "VanPaint", { kind = "buy", id = "gold" })
check("Collector gold without the collection book's milestone: refused, says what unlocks it", profileA.vanPaint.owned.gold == nil and profileA.money == 50000
	and string.find(lastNotice(A, mark), "A legendary!", 1, true) ~= nil, lastNotice(A, mark))
E.advance(1)
mark = #E.sent
E.fire(A, "VanPaint", { kind = "buy", id = "red" })
check("owned already: refused, never paid twice", profileA.money == 50000 and string.find(lastNotice(A, mark), "yours already", 1, true) ~= nil, lastNotice(A, mark))
local stranger = E.player(303) -- here, but their save never loaded
local ok, why = VanPaint.buy(stranger, "red")
check("no save loaded: refused", ok == false and why == "Your save isn't loaded yet.", why)
E.advance(2)
local saved = table.clone(profileA.vanPaint.owned)
for _, message in { nil, "buy", 5, true, { kind = "buy" }, { kind = "buy", id = {} }, { kind = "buy", id = string.rep("x", 100) }, { kind = "wear", id = 5 }, { kind = "paint", id = "red" }, { kind = 7 } } :: { any } do
	E.advance(1)
	E.fire(A, "VanPaint", message)
end
check("the remote: garbage buys and wears nothing (no table, no id, a table id, a long id, another kind)", same(profileA.vanPaint.owned, saved) and profileA.money == 50000 and profileA.vanPaint.worn.paint == "red")
E.advance(2)
mark = #E.sent
for _ = 1, 10 do
	E.fire(A, "VanPaint", { kind = "state" })
end
local answered = #kinds(E.received(A, "VanPaint", mark), "state")
check(`the rate limit: 10 requests at once, {Config.Robust.Limits.VanPaint} answered`, answered == Config.Robust.Limits.VanPaint, answered)

-- ── Wearing ─────────────────────────────────────────────────────────────────
E.advance(2)
mark = #E.sent
E.fire(A, "VanPaint", { kind = "wear", id = "cream" })
check("wearing the factory's cream: free, the van cream again, its PaintColor gone (the Blender look's own cream)", profileA.money == 50000 and profileA.vanPaint.worn.paint == "cream"
	and isRgb(find(model, "CargoSide").Color, { 232, 226, 210 }) and model:GetAttribute("PaintColor") == nil and #kinds(E.received(A, "VanPaint", mark), "worn") == 1)
mark = #E.sent
E.fire(A, "VanPaint", { kind = "wear", id = "navy" })
check("wearing what is not yours: refused, says to buy it first", profileA.vanPaint.worn.paint == "cream" and lastNotice(A, mark) == "Navy blue isn't yours yet: buy it first.", lastNotice(A, mark))
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "red" })
check("wearing the red again: free", profileA.money == 50000 and profileA.vanPaint.worn.paint == "red" and isRgb(find(model, "CargoSide").Color, { 176, 32, 32 }))

-- ── A livery: the stripes, the logo's ink, the roof's stripes ─────────────
E.advance(1)
E.fire(A, "VanPaint", { kind = "buy", id = "racing" })
local light = Config.VanPaint.Contrast.Light
check("Racing stripes bought ($1,500), worn: the paint kept", profileA.money == 48500 and profileA.vanPaint.worn.livery == "racing" and profileA.vanPaint.worn.paint == "red")
local stripesOk = true
for _, s in all(model, "Stripe") do
	stripesOk = stripesOk and isRgb(s.Color, light)
end
local logo = find(model, "Logo")
local name = find(model, "CompanyName")
check("… the ZDC band and the badge in the light contrast on the red, the ZDC logo's letters too, the company's name not", stripesOk and isRgb(find(model, "Badge").Color, light)
	and isRgb(logo:FindFirstChild("FleetLabel"):FindFirstChildOfClass("TextLabel").TextColor3, light) and isRgb(name:FindFirstChild("FleetLabel"):FindFirstChildOfClass("TextLabel").TextColor3, { 32, 35, 38 })
	and isRgb(model:GetAttribute("StripeColor"), light))
local livery = model:FindFirstChild("VanLivery")
local roof = if livery then livery:GetChildren() else {}
local welded, quiet = true, true
local body = model:FindFirstChild("BodyRoot")
for _, p in roof do
	local weld = p:FindFirstChildOfClass("WeldConstraint")
	welded = welded and weld ~= nil and weld.Part0 == body and weld.Part1 == p and p.Anchored == false
	quiet = quiet and p.CanCollide == false and p.CanQuery == false and p.CanTouch == false and p.Massless == true and isRgb(p.Color, light)
end
check("… two roof stripes (the folder VanLivery), welded to the body that sways, nothing physical", #roof == 2 and welded and quiet, #roof)
local stripe = roof[1]
local local_ = if stripe then (home:Inverse() * stripe.CFrame).Position else nil
check("… on the high roof: a hair over Config.Sprinter.Height, along the van", local_ ~= nil and math.abs(local_.Y - (Config.Sprinter.Height + Config.VanPaint.Roof.Lift)) < 1e-6
	and stripe.Size.Z > 15 and math.abs(math.abs(local_.X) - 0.75) < 1e-6)
check("… still nothing that collides changed", physics(model) == before)
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "zdc" })
check("the ZDC classic again: the red band, no roof stripes, StripeColor gone", isRgb(find(model, "Stripe").Color, { 179, 38, 30 }) and model:FindFirstChild("VanLivery") == nil and model:GetAttribute("StripeColor") == nil)
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "racing" })

-- ── The premium: Collector gold, the collection book's milestone (8.3 economy: "A legendary!") ─────────
E.advance(2)
mark = #E.sent
local goldPrice, legendaryReward = 0, 0
for _, item in Config.VanPaint.Paints do
	if item.id == "gold" then
		goldPrice = item.price
	end
end
for _, milestone in Config.CollectionBook.Milestones do
	if milestone.id == "legendary" then
		legendaryReward = milestone.reward
	end
end
profileA.collectionBookPaid.legendary = true -- (server/CollectionBook.luau pays it: the money moves, PlayerData.Changed fires)
PlayerData.addMoney(A, legendaryReward, "BookMilestone", "legendary")
E.flush()
local after = kinds(E.received(A, "VanPaint", mark), "state")
check("the book paid \"A legendary!\": a state with the paid milestone (the window's lock opens)", #after == 1 and table.find(after[1].paid, "legendary") ~= nil, #after)
mark = #E.sent
PlayerData.addMoney(A, 10, "Admin")
E.flush()
check("… the money moving again alone sends no state", #kinds(E.received(A, "VanPaint", mark), "state") == 0)
E.advance(1)
E.fire(A, "VanPaint", { kind = "buy", id = "gold" })
check(`Collector gold bought ({goldPrice}) and worn: Metal`, profileA.vanPaint.owned.gold == true and profileA.money == 48500 + legendaryReward + 10 - goldPrice and profileA.vanPaint.worn.paint == "gold"
	and find(model, "CargoSide").Material == "Metal" and model:GetAttribute("PaintMaterial") == "Metal", profileA.money)

-- ── The owner's Blender look ───────────────────────────────────────────────
P.dress(model) -- (server/SprinterMesh.luau dresses the van: its pieces wear the attributes it reads)
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "red" })
local mesh = model:FindFirstChild("SprinterMesh")
check("the Blender look's pieces: the paint finish red, the stripe finish the racing contrast, the glass untouched", isRgb(mesh:FindFirstChild("Body_paint").Color, { 176, 32, 32 })
	and isRgb(mesh:FindFirstChild("BackDoorL_paint").Color, { 176, 32, 32 }) and isRgb(mesh:FindFirstChild("Body_stripe").Color, light) and isRgb(mesh:FindFirstChild("Body_glass").Color, { 22, 33, 42 }))
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "cream" })
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "zdc" })
check("… the factory's again: their own cream and red (FactoryColor), not the parts look's", isRgb(mesh:FindFirstChild("Body_paint").Color, { 217, 204, 176 }) and isRgb(mesh:FindFirstChild("Body_stripe").Color, { 179, 38, 30 })
	and mesh:FindFirstChild("Body_paint").Material == "SmoothPlastic")

-- ── Every spawn: a new van comes painted ──────────────────────────────────
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "gold" })
E.advance(1)
E.fire(A, "VanPaint", { kind = "wear", id = "racing" })
local van2 = P.van(A, home) -- (CAR, a move's START, PLAY again: Vehicles.spawnAt builds a new one)
check("a new van (CAR, START, PLAY): built in what you wear (gold, the racing stripes) with its prompt", isRgb(find(van2.model, "CargoSide").Color, { 214, 170, 62 }) and van2.model:FindFirstChild("VanLivery") ~= nil
	and #van2.model:FindFirstChild("VanLivery"):GetChildren() == 2 and promptOf(van2) ~= nil and promptOf(van2).Enabled == true)
local vanB = P.van(B, M.CFrame.new(SandboxMap.Plots[2].vanSpot.x, 0, SandboxMap.Plots[2].vanSpot.z))
check("another player's van: their own look (the factory's), their own prompt", isRgb(find(vanB.model, "CargoSide").Color, { 232, 226, 210 }) and promptOf(vanB):GetAttribute("CargoOwner") == 202)
P.Vehicles.onStyle(van2) -- (Vehicles.refreshStats, a repaint: the hook again on the same van)
check("the hook again on the same van: still one prompt, one set of roof stripes", #all(van2.model, "PaintPrompt") == 1 and #all(van2.model, "VanLivery") == 1
	and #van2.model:FindFirstChild("VanLivery"):GetChildren() == 2)
local rented = P.van(B, home, false, true)
check("a rental (ZDC RIDE, a lent vehicle): never painted, no prompt", promptOf(rented) == nil and rented.model:GetAttribute("VanPaint") == nil)
P.cars[B] = vanB

-- ── The admin's UNLOCK PAINTS / RESET PAINTS ──────────────────────────────
mark = #E.sent
local said = VanPaint.admin(B, "all")
E.flush()
local items = #Rules.Paints + #Rules.Liveries - 2
check(`UNLOCK PAINTS: every item but the free owned ({items}), the worn kept, the state sent`, string.find(said, "is yours", 1, true) ~= nil and (function()
	local n = 0
	for _ in (PlayerData.get(B) :: any).vanPaint.owned do
		n += 1
	end
	return n == items
end)() and (PlayerData.get(B) :: any).vanPaint.worn.paint == "cream" and #kinds(E.received(B, "VanPaint", mark), "state") == 1, said)
E.fire(B, "VanPaint", { kind = "wear", id = "chrome" })
check("… then wearing Mirror chrome is free", (PlayerData.get(B) :: any).money == Config.Sandbox.StartMoney and (PlayerData.get(B) :: any).vanPaint.worn.paint == "chrome" and find(vanB.model, "CargoSide").Material == "Foil")
said = VanPaint.admin(B, "reset")
check("RESET PAINTS: nothing bought, the van in the factory's look", string.find(said, "reset", 1, true) ~= nil and same((PlayerData.get(B) :: any).vanPaint, Rules.empty()) and isRgb(find(vanB.model, "CargoSide").Color, { 232, 226, 210 }))
check("… no save loaded: says so", string.find(VanPaint.admin(stranger, "all"), "no save", 1, true) ~= nil)

-- ── The save round trip ─────────────────────────────────────────────────────
local paintA = table.clone(profileA.vanPaint.owned)
local wornA = table.clone(profileA.vanPaint.worn)
E.leave(A)
local stored = E.saves.Player_101
check("leaving saves the paint with its flag", stored ~= nil and stored.vanPaintKept == true and stored[Rules.Flag] == true and same(stored.vanPaint.owned, paintA) and same(stored.vanPaint.worn, wornA))
mark = #E.sent
A = E.join(101, "Ann")
E.plotOf[A] = SandboxMap.Plots[1]
profileA = PlayerData.get(A) :: any
E.flush()
check("rejoining: the same paints owned and worn; the state says so", same(profileA.vanPaint.owned, paintA) and same(profileA.vanPaint.worn, wornA) and #kinds(E.received(A, "VanPaint", mark), "state") == 1
	and kinds(E.received(A, "VanPaint", mark), "state")[1].worn.paint == "gold")
local van3 = P.van(A, home)
check("… PLAY again: the van comes in gold with the racing stripes", isRgb(find(van3.model, "CargoSide").Color, { 214, 170, 62 }) and van3.model:FindFirstChild("VanLivery") ~= nil)
E.leave(A)
A = E.join(101, "Ann")
profileA = PlayerData.get(A) :: any
check("twice: the same", same(profileA.vanPaint.owned, paintA) and same(profileA.vanPaint.worn, wornA))

-- the migration: an older save, a lock-only record, a garbled one
E.saves.Player_404 = { money = 900, vanPaint = { owned = { red = true }, worn = { paint = "red", livery = "zdc" } } }
local C = E.join(404, "Cid")
check("a save from before 8.3 (no flag): its stray vanPaint not read, the factory's", same((PlayerData.get(C) :: any).vanPaint, Rules.empty()))
E.saves.Player_405 = { vanPaintKept = true, vanPaint = { owned = { red = true }, worn = { paint = "red", livery = "zdc" } } }
local D = E.join(405, "Dee")
check("a lock-only record (no money): the factory's", same((PlayerData.get(D) :: any).vanPaint, Rules.empty()))
E.saves.Player_406 = { money = 5, vanPaintKept = true, vanPaint = { owned = { red = true, cream = true, junk = true }, worn = { paint = "black", livery = "racing" } } }
local F = E.join(406, "Fay")
check("a garbled one: cleaned (known ids bought, worn only what is owned)", same((PlayerData.get(F) :: any).vanPaint, { owned = { red = true }, worn = { paint = "cream", livery = "zdc" } }))

check("no warnings", #E.warnings == 0, E.warnings[1])
print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
