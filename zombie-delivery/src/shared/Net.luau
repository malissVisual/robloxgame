--!strict
-- RemoteEvents. The server creates them on first require, the client waits for them. 5.7: Net.limit and Net.latest,
-- the server's rate limit per player and remote (Config.Robust.Limits).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestState", -- client → server: send me everything (after loading)
	"State", -- server → client: money, owned cars / guns, upgrades, stats of the equipped car and gun
	"SpawnCar", -- client → server: bring my car next to me
	"RequestOffers", -- client → server: the job board was opened
	"Offers", -- server → client: ({ { index, stars, cargo, customer, address, distance, pay, time } }, refreshAt, info) 3.7: sorted ★ → ★★★★, index = the offer's id, refreshAt = GetServerTimeNow() of the next offers (pushed then); 4.7: info = { tiers = { { stars, name, fee, rerolled, open, level, licence? } }, streak }
	"AcceptJob", -- client → server: take offer (index)
	"CancelJob", -- client → server: give the active job up
	"Job", -- server → client: the active job ({ … } or nil when none)
	"DeliveryResult", -- server → client: { success, reason?, payout? }
	"Fire", -- client → server: a shot at a point (Vector3): the hand gun, out of the window or the car gun; 3.8.2: + the part of a zombie hanging on a car when that is what was aimed at (server/Gun.luau latchedHit)
	"Tracer", -- server → clients: (from, to, color, shooter userId)
	"Hit", -- server → client: the shooter's hit marker (position, damage, crit, killed)
	"Reward", -- server → client: money popped from a kill (position, amount)
	"Bump", -- server → client: the car hit something heavy, keep this share of the speed
	"Buy", -- client → server: buy (kind = "car" | "weapon" | "item" | "cargun", id, amount for items)
	"Equip", -- client → server: equip (kind, id)
	"Upgrade", -- client → server: next level of an upgrade track (id; 3.5: "stage" = the equipped car's next stage)
	"Notice", -- server → client: a short toast (text)
	"Play", -- client → server: PLAY was pressed on the start screen (the car comes now)
	"UseItem", -- client → server: use a consumable (id, aimed point or nil)
	"Boost", -- server → client: nitro (seconds, speed multiplier)
	"OpenShop", -- server → client: a shop prompt was used (shop id, focused item id or nil)
	"Paint", -- client → server: buy / apply a paint job on the equipped car (paint id)
	"AcceptEmployer", -- client → server: take a job from the employer whose board you stand at (employer id)
	"Aiming", -- client → server: aiming on foot or not (the gun arm goes up / down for everybody)
	"Admin", -- client → server: an admin command (name, argument) — only for admins (server/Admin.luau)
	"CrewInvite", -- client → server: invite a player into my job (userId); server → client: an invitation (from userId, job name)
	"CrewAnswer", -- client → server: accept / decline an invitation (from userId, accepted)
	"CrewState", -- server → client: my crew (owner, members, pay shares) or nil
	"Leaderboard", -- client → server: send me the board; server → client: the rows (name, level, rank, deliveries, earned)
	"Estate", -- client → server: (action "buy" | "sell" | "home", estate id); server → client: open the listing (estate id)
	"Business", -- client → server: (action "hire" | "fire" | "upgrade" | "collect" | "open", arg); server → client: the company state
	"CarCall", -- server → client: your car is on the way (seconds left, car model) or arrived / failed (nil)
	"Missions", -- client → server: ("open") or ("start", mission id); server → client: the progress (MissionsState)
	"CrewBoard", -- client → server: looking for a crew (mission id or "any") or not (nil); server → clients: who is looking
	"Challenges", -- client → server: ("open") or ("title", title or nil); server → client: ("state", …) or ("unlocked", …)
	"Garage", -- 3.4: client → server: ("take", car id) or ("refresh"); server → client: the garage window (server/Garages.luau)
	"Repair", -- 3.4: server → client: a repair started ({ car, shop, seconds, total, fee }) or ended (nil) (server/Repair.luau)
	"Tutorial", -- 3.7: server → client: (phase, data?): welcome / board / job / retry / done / say, or nil (5.0: also "phone", Marge gave it, and "message", { from, text, gps? } a text for the phone: server/VanQuest.luau); client → server: ("go") or ("skip") (server/Tutorial.luau)
	"Explore", -- 3.7: server → client: ("state", cells string, places list) on joining, ("cells", list) newly uncovered, ("place", id) discovered
	"Holster", -- 3.9: client → server: (holstered boolean) the gun away (B) or in the hand; the server sets the character's Holstered attribute (server/CloseCombat.luau)
	"Melee", -- 3.9: client → server: (the swing's direction, a unit Vector3, or nil) a punch (holstered) or a strike with the gun (V); checked on the server
	"CarDoor", -- 3.10: client → server: ("out") E in a car seat: out of it at your door (server/Vehicles.luau, client/CarBoarding.luau)
	"Gear", -- 4.6: client → server: ("buy" | "install" | "remove", gear id) for the equipped car at Wrench Garage (server/Shops.luau)
	"RerollTier", -- 4.7: client → server: (tier) new ordinary offers of that danger level on my board, for Config.Jobs.Choice.RerollFee × its stars, once per board (server/Jobs.luau)
	"RoadEvent", -- 4.8: server → client: a road event's card ({ kind = "addon", title, text, pay, endsAt }) or nil to close it; client → server: ("accept" | "decline") the add-on (server/Jobs.luau, client/RoadEventUi.luau)
	"Kit", -- 5.0: client → server: ("buy", kit id) personal gear at Last Stop Supplies (server/Shops.luau, Config.Kit)
	"PhoneHold", -- 5.0: client → server: (holding boolean) the phone window opened / closed; the server shows the phone in your right hand to everybody while you are on foot with your hands free (server/KitWear.luau, the character attribute PhoneHeld)
	"PutDown", -- 4.2: client → server: () the touch PUT DOWN / LET GO / SET DOWN button: what the G prompt in your hands does (server/Cargo.luau, server/Equipment.luau)
	"PinOrder", -- 5.2: client → server: (order id or nil) the GPS follows that order of your run (the phone's ORDERS app, server/Jobs.luau)
	"Fuel", -- 5.4: client → server: ("tow") the phone's TOW: your empty car to the nearest gas station's pump (server/Fuel.luau)
	"Bus", -- 5.5: client → server: ("stop") on a city bus: the bell (off at the next stop), or off now while it stands at a stop (server/Buses.luau, client/BusRide.luau)
	"Zip", -- 5.6: client → server: ("letgo") Space on a zip line, low over a platform's roof (server/ZipLines.luau checks it); 5.7: the ladder climbs are walked on the client (client/Interact.luau), the server sets their end
}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Net = {}

function Net.get(name: string): RemoteEvent
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), "unknown remote " .. name)
	return remote
end

-- ── 5.7: rate limits (the server) ──────────────────────────────────────────
-- A token bucket per player and name: perSecond requests in a burst, then perSecond a second.

type Bucket = { tokens: number, at: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
type Waiting = { args: { any }, n: number, scheduled: boolean }
local waiting: { [Player]: { [string]: Waiting } } = {}

local function bucketOf(player: Player, name: string, perSecond: number): Bucket
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local bucket = mine[name]
	local now = os.clock()
	if not bucket then
		bucket = { tokens = math.max(1, perSecond), at = now }
		mine[name] = bucket
	else
		bucket.tokens = math.min(math.max(1, perSecond), bucket.tokens + (now - bucket.at) * perSecond)
		bucket.at = now
	end
	return bucket
end

-- May this request from the player go on? False when they sent more than perSecond a second (drop it).
function Net.limit(player: Player, name: string, perSecond: number): boolean
	local bucket = bucketOf(player, name, perSecond)
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

-- Like Net.limit, for a remote that carries a state (the aim, a pinned order, "send me the board"): a request over the
-- limit is not lost, the last one waits and fn(player, ...) runs with it once there is room again (the earlier ones
-- in between are dropped). A burst is answered once more at its end, never with stale arguments.
function Net.latest(player: Player, name: string, perSecond: number, fn: (Player, ...any) -> (), ...: any)
	local mine = waiting[player]
	if not mine then
		mine = {}
		waiting[player] = mine
	end
	local found = mine[name]
	if not (found and found.scheduled) and Net.limit(player, name, perSecond) then
		fn(player, ...)
		return
	end
	local entry: Waiting = found or { args = {}, n = 0, scheduled = false }
	mine[name] = entry
	entry.args, entry.n = { ... }, select("#", ...)
	if entry.scheduled then
		return -- (the newest arguments go when the wait is over)
	end
	entry.scheduled = true
	local bucket = bucketOf(player, name, perSecond)
	local wait = math.max(0, (1 - bucket.tokens) / math.max(perSecond, 0.01))
	task.delay(wait, function()
		entry.scheduled = false
		local list = waiting[player]
		if not player.Parent or not list or list[name] ~= entry then
			return
		end
		list[name] = nil
		Net.latest(player, name, perSecond, fn, table.unpack(entry.args, 1, entry.n))
	end)
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		waiting[player] = nil
	end)
end

return Net
