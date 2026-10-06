--!strict
-- 4.0, freight and equipment: the pure rules the server (server/Cargo.luau, server/Equipment.luau, server/Jobs.luau)
-- and the tests share. No Roblox at the top level: positions are plain { x, y, z } tables.
--
--   the hand trolley  a car with the "trolley" gear installed carries one (4.6: Config.Gear; Stream V: the
--                     TrolleyMount inside the back). You
--                     push it (the character attribute Pushing = "trolley") and it takes up to Config.Cargo.TrolleyPieces
--                     pieces of any kind except people, horses and pallets. Not on a job with the lift or the pair
--                     twist: those pieces are carried by hand (the missions are made that way).
--   the pallet jack   a pallet (the cargo kind "pallet") is too heavy for the hands: only a pallet jack lifts it
--                     (Pushing = "jack"), one at a time. A pallet uses Config.Cargo.PalletSlots of a vehicle's slots and
--                     goes only into a vehicle that takes pallets (Economy.palletsOf, Stream V: CarDef / StageDef
--                     pallets).
--
-- Kept generic for later (a semi truck with a trailer): a vehicle says how many pallets it takes, the docks and the
-- receiving spots are data (shared/Map.luau FreightDocks / ReceivingDocks), and the pallets' places in a vehicle come
-- from its own pallet slots or, without any, from its cargo slots (palletSpots).

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Freight = {}

export type Point = { x: number, y: number, z: number }

-- Are these pieces people or animals (they walk, or are led)?
local function alive(kind: string): boolean
	return kind == "horse" or kind == "kid" or kind == "patient" or kind == "survivor"
end

-- Is this cargo kind a pallet (moved only with a pallet jack)?
function Freight.isPallet(kind: string?): boolean
	return kind == "pallet"
end

-- May pieces of this kind ride on a hand trolley (a job with the lift or pair twist: no)?
function Freight.trolleyTakes(kind: string, lift: boolean?, pair: boolean?): boolean
	if alive(kind) or Freight.isPallet(kind) then
		return false
	end
	return not lift and not pair
end

-- How many pieces of a job one player may hold at once: with nothing (`tool` nil), on a trolley or on a jack. 0 means
-- not at all (a pallet by hand, a crate on a jack, a horse on a trolley); the caller says why (Freight.refusal).
-- Without a tool it is server/Cargo.luau's 3.7 rule: two of a light look, else one.
function Freight.handsMax(kind: string, look: string, lift: boolean?, pair: boolean?, tool: string?): number
	local tuning = Config.Cargo
	if tool == "jack" then
		return if Freight.isPallet(kind) then 1 else 0
	end
	if Freight.isPallet(kind) then
		return 0
	end
	if tool == "trolley" then
		return if Freight.trolleyTakes(kind, lift, pair) then math.max(1, tuning.TrolleyPieces) else 0
	end
	if alive(kind) or lift or pair or not tuning.LightLooks[look] then
		return 1
	end
	return math.max(1, tuning.HandsMax)
end

-- Why handsMax said 0, for the player.
function Freight.refusal(kind: string, lift: boolean?, pair: boolean?, tool: string?): string
	if tool == "jack" then
		return "The pallet jack only lifts pallets. Set it down (G) first."
	end
	if Freight.isPallet(kind) then
		return "Too heavy: use a pallet jack."
	end
	if lift or pair then
		return "No trolley for this one: it has to be carried by hand. Set the trolley down (G) first."
	end
	return "That does not go on a trolley. Set it down (G) first."
end

-- The walk (studs / s, the CarrySpeed attribute) with a tool: an empty trolley, a loaded one, the jack.
function Freight.walkSpeed(tool: string, count: number): number
	local tuning = Config.Cargo
	if tool == "jack" then
		return tuning.JackSpeed
	end
	return if count > 0 then tuning.TrolleyLoadedSpeed else tuning.TrolleySpeed
end

-- How many pallets a vehicle takes: Economy.palletsOf (Stream V) through a guarded lookup, 0 without it.
function Freight.palletsOf(carId: string, stage: number?): number
	local lookup = (Economy :: any).palletsOf
	if type(lookup) ~= "function" then
		return 0
	end
	local ok, value = pcall(lookup, carId, stage or 0)
	return if ok and type(value) == "number" then math.max(0, math.floor(value)) else 0
end

-- The most pallets a car takes at any of its stages (0 for a car without pallets).
function Freight.maxPallets(carId: string): number
	local most = 0
	for stage = 0, Economy.maxStage(carId) do
		most = math.max(most, Freight.palletsOf(carId, stage))
	end
	return most
end

-- How many more fit: pallets in a vehicle that takes `takes`, with `loaded` in it already.
function Freight.palletRoom(takes: number, loaded: number): number
	return math.max(0, takes - loaded)
end

-- How many more pieces fit in a vehicle of `capacity` slots with `loaded` in it (a trolley's Load all).
function Freight.pieceRoom(capacity: number, loaded: number): number
	return math.max(0, capacity - loaded)
end

-- What to do about a freight job the player's car cannot take: the cars that take `need` pallets (their names, the
-- stage it takes at), for the board's lock and the refusal.
function Freight.palletAdvice(need: number): string
	local names: { string } = {}
	for _, def in Config.Cars do
		if def.company and not def.employer then
			continue
		end
		for stage = 0, Economy.maxStage(def.id) do
			if Freight.palletsOf(def.id, stage) >= need then
				local stageDef = if stage > 0 then Economy.stageDef(def.id, stage) else nil
				local employer = if def.company and def.employer then Economy.findEmployer(def.employer) else nil
				table.insert(names, if stageDef then `the {def.name} as a {stageDef.name}`
					elseif employer then `the {def.name} (earned at {employer.name})`
					else `the {def.name}`)
				break
			end
		end
	end
	if #names == 0 then
		return "None of the dealer's cars takes that many pallets."
	end
	return `Pallets go in a truck: {table.concat(names, ", ")}.`
end

-- The lock of a freight job: the board's text and the card's button.
function Freight.lockText(need: number, carName: string, takes: number): (string, string)
	local takesText = if takes <= 0 then "takes no pallets" elseif takes == 1 then "takes 1 pallet" else `takes {takes} pallets`
	local text = `This job needs a truck that takes {need} {if need == 1 then "pallet" else "pallets"}: your {carName} {takesText}. {Freight.palletAdvice(need)}`
	return text, `🚚 NEEDS {need} {if need == 1 then "PALLET" else "PALLETS"}`
end

-- Where `count` pallets stand in a vehicle, from its cargo slots (bottom centres relative to the chassis, -Z the
-- front). A pallet takes a 2×2 group of slots (Config.Cargo.PalletSlots): slots 1–4 (every car's front 2×2), 5–8,
-- 9–12 (the Freight Truck's three pallet bays), in the middle of its group, on the floor. Past the groups that lie
-- on the floor the pallets go on in a row behind the last one, PalletSpacing apart (generic: a trailer later).
function Freight.palletSpots(slots: { Point }, count: number): { Point }
	local out: { Point } = {}
	if #slots == 0 or count <= 0 then
		return out
	end
	local floor = math.huge
	for _, slot in slots do
		floor = math.min(floor, slot.y)
	end
	local group = math.max(1, Config.Cargo.PalletSlots)
	for index = 1, count do
		local first = (index - 1) * group + 1
		local sumX, sumZ, onFloor = 0, 0, true
		for k = first, first + group - 1 do
			local slot = slots[k]
			if not slot or slot.y > floor + 0.01 then
				onFloor = false
				break
			end
			sumX += slot.x
			sumZ += slot.z
		end
		if onFloor then
			table.insert(out, { x = sumX / group, y = floor, z = sumZ / group })
		elseif #out > 0 then
			local last = out[#out]
			table.insert(out, { x = last.x, y = last.y, z = last.z + Config.Cargo.PalletSpacing })
		else
			-- Fewer than a group on the floor: the first pallet at the front slot, down the middle.
			local front, sum, n = math.huge, 0, 0
			for _, slot in slots do
				if slot.y <= floor + 0.01 then
					front = math.min(front, slot.z)
					sum += slot.x
					n += 1
				end
			end
			table.insert(out, { x = sum / n, y = floor, z = front - Config.Cargo.SlotDepth / 2 + Config.Cargo.PalletSpacing / 2 })
		end
	end
	return out
end

-- Where the pieces sit on a trolley's toe plate (offsets from its middle, studs): one in the middle; more two side by
-- side, the next two on top of them. `heights` are the pieces' heights, bottom first.
function Freight.trolleyStack(heights: { number }): { Point }
	local out: { Point } = {}
	local columns = { 0, 0 }
	local count = #heights
	for index, height in heights do
		local column = (index - 1) % 2 + 1
		local x = if count == 1 then 0 else (column - 1.5) * Config.Cargo.TrolleyColumnGap
		table.insert(out, { x = x, y = columns[column], z = 0 })
		columns[column] += height
	end
	return out
end

-- Has a tool been left long enough with nobody near to go home on its own?
function Freight.returnsHome(kind: string, idleSeconds: number, nobodyNear: boolean): boolean
	local wait = if kind == "jack" then Config.Cargo.JackReturnSeconds else Config.Cargo.TrolleyReturnSeconds
	return nobodyNear and idleSeconds >= wait
end

-- A job card's tip (the board): a trolley helps with Config.Cargo.TrolleyTipPieces pieces or more you carry. 4.6:
-- `has` = the car that does the job has the Hand Trolley installed (Economy.installedGear): use it; else where to get
-- it (gear at Wrench Garage, from its level).
function Freight.trolleyTip(kind: string, pieces: number, mode: string, has: boolean?): string?
	if mode ~= "carry" or pieces < Config.Cargo.TrolleyTipPieces or not Freight.trolleyTakes(kind) then
		return nil
	end
	local count = Config.Cargo.TrolleyPieces
	if has then
		return `Use your hand trolley: {count} pieces at a time (open the back, take it out with E).`
	end
	local gear = Economy.findGear("trolley")
	local level = if gear then ` from level {gear.level}` else ""
	return `A hand trolley helps: {count} pieces at a time (Hand Trolley gear at Wrench Garage{level}).`
end

return Freight
