--!strict
-- RemoteEvents. The server creates them on first require, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestState", -- client → server: send me everything (after loading)
	"State", -- server → client: money, owned cars / guns, upgrades, stats of the equipped car and gun
	"SpawnCar", -- client → server: bring my car next to me
	"RequestOffers", -- client → server: the job board was opened
	"Offers", -- server → client: { { index, stars, cargo, customer, address, distance, pay, time } }
	"AcceptJob", -- client → server: take offer (index)
	"CancelJob", -- client → server: give the active job up
	"Job", -- server → client: the active job ({ … } or nil when none)
	"DeliveryResult", -- server → client: { success, reason?, payout? }
	"Fire", -- client → server: a shot at a point (Vector3): the hand gun, out of the window or the car gun
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

return Net
