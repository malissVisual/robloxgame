--!strict
-- 6.14, the REGULARS on the server (shared/Regulars.luau has the rules, Config.Regulars the numbers). One call from
-- server/Jobs.luau payOrder (Regulars.paid), for every order or job paid that is not a mission:
--   * the owner's tier with the order's business (its picture's: shared/JobThumbs.luau) adds its bonus to the order's
--     rated pay (before the tips and the crew's split: the crew shares it as usual);
--   * the delivery counts for that business, for the owner and every crew member paid with it, each in their own
--     profile.regulars (saved by server/PlayerData.luau). A tier reached is the analytics' RegularTierUp; the client
--     sees the new count in the State (server/Main.server.luau sendState) and says it with a toast and a sting
--     (client/RegularsApp.luau);
--   * a golden order or a regular's order (shared/SpecialOrders.luau Spec, the offer's `specialOrder`; its pay is in the
--     offer already) gives its XP multiplier;
--   * the result's lines (DeliveryResult `special`, client/SpecialOrderUi.luau): the golden order, the regular's order,
--     the owner's bonus (a crew member's: the first two);
--   * the daily tasks (server/Tasks.luau): "regular" for each who was a regular there already, "golden" for a golden
--     order.
-- Regulars.adminSet (server/Admin.luau "regulars"): every business at a count, to try the tiers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Regulars)
local PlayerData = require(script.Parent.PlayerData)

local Regulars = {}

-- What payOrder adds: the owner's bonus money, the XP's multiplier, the owner's and a crew member's result lines.
export type Paid = { money: number, xp: number, info: { [string]: any }?, crewInfo: { [string]: any }? }

-- One more delivery for `id` in `who`'s profile. Was `who` a regular there already (a tier before this one)?
local function count(who: Player, id: string): boolean
	local profile = PlayerData.get(who)
	if not profile then
		return false
	end
	local before, _, reached = Rules.add(profile.regulars, id, 1)
	if reached then
		local _, index = Rules.tierOf(before + 1)
		PlayerData.track("event", who, "RegularTierUp", index, reached.id, id) -- 6.14 (shared/AnalyticsPlan.luau)
	end
	PlayerData.notify(who) -- (the State carries the count: the REGULARS app, the badges, the tier's toast)
	return Rules.tierOf(before) ~= nil
end

-- An order paid (server/Jobs.luau payOrder): `offer` is the order's, `pay` its rated pay so far, `crew` everybody
-- paid with it besides the owner; `side`: a road event's side pick-up (it counts for nobody). Never fails the pay: a
-- problem is warned and nothing is added.
function Regulars.paid(player: Player, offer: any, pay: number, crew: { Player }, side: boolean?): Paid
	local result: Paid = { money = 0, xp = 1, info = nil, crewInfo = nil }
	if side then
		return result
	end
	local ok, err = pcall(function()
		local tasks = require(script.Parent.Tasks)
		local shared: { [string]: any } = {}
		local spec = if type(offer.specialOrder) == "table" then offer.specialOrder else nil
		if spec then
			result.xp = math.max(1, tonumber(spec.xp) or 1)
			if spec.kind == "golden" then
				shared.golden = { pay = spec.pay, xp = spec.xp }
			else
				shared.regularOrder = { pay = spec.pay, xp = spec.xp, name = Rules.nameOf(tostring(spec.business)) }
			end
		end
		local info = table.clone(shared)
		local id = Rules.businessOf(offer)
		if id then
			local profile = PlayerData.get(player)
			local tier = Rules.tierOf(if profile then profile.regulars[id] or 0 else 0)
			if tier then
				result.money = math.max(0, math.floor(pay * tier.bonus + 0.5))
				info.regular = { name = Rules.nameOf(id), tier = tier.name, icon = tier.icon, bonus = tier.bonus, money = result.money }
			end
			local everybody = table.clone(crew)
			table.insert(everybody, 1, player)
			for _, who in everybody do
				if count(who, id) then
					tasks.note(who, "regular", 1)
				end
			end
		end
		if spec and spec.kind == "golden" then
			tasks.note(player, "golden", 1)
			for _, member in crew do
				tasks.note(member, "golden", 1)
			end
		end
		result.info = if next(info) ~= nil then info else nil
		result.crewInfo = if next(shared) ~= nil then shared else nil
	end)
	if not ok then
		warn(`[Regulars] paid failed for {player.Name}: {err}`)
	end
	return result
end

-- The admin's "regulars" (server/Admin.luau): every business at `n` deliveries (0 clears them). What happened, in words.
function Regulars.adminSet(player: Player, n: any): string
	local profile = PlayerData.get(player)
	local value = tonumber(n)
	if not profile or value == nil or value ~= value then
		return "ADMIN: regulars need a number of deliveries."
	end
	local at = math.clamp(math.floor(value), 0, 1000)
	table.clear(profile.regulars)
	if at > 0 then
		for _, id in Rules.ids() do
			profile.regulars[id] = at
		end
	end
	PlayerData.notify(player)
	local tier = Rules.tierOf(at)
	return `ADMIN: every business at {at} deliveries{if tier then ` ({tier.name}, +{Rules.percent(tier.bonus)}% pay)` else ""}.`
end

return Regulars
