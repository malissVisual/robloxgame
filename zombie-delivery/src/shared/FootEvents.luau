--!strict
-- 5.7, life on a run on foot or by bike (Config.Jobs.FootEvents): which light road event a run gets, when, the
-- survivor's tip, the walkers at a drop, where a locked gate stands and what Marge's notices say. Pure Luau (no
-- Roblox API): server/RunEvents.luau runs the events, server/Jobs.luau asks it; tested in tests/footevents_test.luau.
--
--   FootEvents.Kinds                       the events, in the order the weights are read: runner, survivor, gate
--   FootEvents.applies(mode, tutorial, mission)   does a run of this mode get them (foot / bike; never the tutorial's
--                                          delivery or a mission; a car job has its own road events)?
--   FootEvents.pick(r1, r2)                the run's event (one of Kinds) with Chance, else nil (r1, r2: 0 … 1)
--   FootEvents.after(r)                    seconds out of the safe zone before it comes
--   FootEvents.tip(r)                      a helped survivor's tip in dollars (Tip: min … max, $5 steps)
--   FootEvents.group(r1, r2)               the walkers waiting at a drop: 0 (most drops) or Group (min … max)
--   FootEvents.gate(roadX, roadZ, dx, dz, width, fromX, fromZ)   where a locked gate stands across the sidewalk of
--                                          the road nearest a point ahead, on the side you come from: its middle
--                                          (x, z), the way along the kerb (ax, az: the gate's face looks that way) and
--                                          the way out to the sidewalk (sx, sz)
--   FootEvents.notice(kind, name?, tip?)   the toast when it starts
--   FootEvents.say(kind)                   what the survivor calls out

local Config = require(script.Parent.Config)

local FootEvents = {}

FootEvents.Kinds = { "runner", "survivor", "gate" }

local function tuning()
	return Config.Jobs.FootEvents
end

function FootEvents.applies(mode: string, tutorial: boolean?, mission: string?): boolean
	return (mode == "foot" or mode == "bike") and not tutorial and mission == nil
end

function FootEvents.pick(r1: number, r2: number): string?
	local t = tuning()
	if r1 >= t.Chance then
		return nil
	end
	local total = 0
	for _, kind in FootEvents.Kinds do
		total += math.max(0, t.Weights[kind] or 0)
	end
	if total <= 0 then
		return nil
	end
	local at = math.clamp(r2, 0, 0.999999) * total
	for _, kind in FootEvents.Kinds do
		local weight = math.max(0, t.Weights[kind] or 0)
		if at < weight then
			return kind
		end
		at -= weight
	end
	return nil
end

function FootEvents.after(r: number): number
	local after = tuning().After
	return after[1] + (after[2] - after[1]) * math.clamp(r, 0, 1)
end

function FootEvents.tip(r: number): number
	local tip = tuning().Tip
	local amount = tip[1] + (tip[2] - tip[1]) * math.clamp(r, 0, 1)
	return math.clamp(math.floor(amount / 5 + 0.5) * 5, tip[1], tip[2])
end

function FootEvents.group(r1: number, r2: number): number
	local t = tuning()
	if r1 >= t.GroupChance then
		return 0
	end
	return t.Group[1] + math.floor(math.clamp(r2, 0, 0.999999) * (t.Group[2] - t.Group[1] + 1))
end

-- The road's middle (roadX, roadZ), its direction (dx, dz: unit) and width (Map.nearestRoad), and where you come from:
-- the gate stands on your side of the road, its near end at the kerb, GateWidth studs into the sidewalk.
function FootEvents.gate(roadX: number, roadZ: number, dx: number, dz: number, width: number, fromX: number, fromZ: number): (number, number, number, number, number, number)
	local sx, sz = -dz, dx -- across the road
	if (fromX - roadX) * sx + (fromZ - roadZ) * sz < 0 then
		sx, sz = -sx, -sz
	end
	local out = width / 2 + tuning().GateWidth / 2
	return roadX + sx * out, roadZ + sz * out, dx, dz, sx, sz
end

function FootEvents.notice(kind: string, name: string?, tip: number?): string
	if kind == "runner" then
		return "🧟 A runner caught your scent: keep moving, or turn and fight!"
	elseif kind == "survivor" then
		return `🆘 {name or "Somebody"} is calling for help just ahead: walk up to them for a tip{if tip then ` (+${tip})` else ""}.`
	elseif kind == "gate" then
		return "🔒 A locked gate across the sidewalk ahead: go round it by the road."
	end
	return ""
end

function FootEvents.say(kind: string): string
	if kind == "survivor" then
		return "Hey! Over here! Got a bandage? Please!"
	end
	return ""
end

return FootEvents
