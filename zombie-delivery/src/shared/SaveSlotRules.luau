--!strict
-- 10.1, the save slots' rules (Config.SaveSlots): each slot's DataStore key, a slot asked for checked, and what the
-- start screen shows of a slot (its summary, read from the stored save as it is). Pure (tests/saveslots_test.luau):
-- server/SaveSlots.luau reads the slots with it, server/PlayerData.luau takes the key of the slot picked, client/Menu.luau
-- writes the cards' lines with it.
--
--   SaveSlotRules.key(userId, slot) -> string     slot 1 "Player_<id>" (the save of before 10.1), slot n "Player_<id>_slot<n>"
--   SaveSlotRules.slot(raw) -> number?            a whole number 1 … Config.SaveSlots.Count, else nil
--   SaveSlotRules.real(saved) -> boolean          a save with a game in it (its money; a lock-only record is not)
--   SaveSlotRules.summary(slot, saved) -> Summary what the slot's card shows: empty, or its courier (look, name), the
--                                                 warehouse's level and name, the money, the pieces in the collection,
--                                                 the moves finished, the time played and when it was saved
--   SaveSlotRules.latest(summaries) -> number?    the slot saved last (the one CONTINUE offers first)
--   SaveSlotRules.played(seconds) -> string       "12 min", "2 h 05 min" ("" under a minute)
--   SaveSlotRules.ago(savedAt, now) -> string     "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago" ("": never)
--   SaveSlotRules.money(n) -> string              "$12,400"

local Config = require(script.Parent.Config)
local CharacterLooks = require(script.Parent.CharacterLooks)
local CollectionRules = require(script.Parent.CollectionRules)
local SandboxBadgeRules = require(script.Parent.SandboxBadgeRules)
local UpgradeRules = require(script.Parent.UpgradeRules)

local SaveSlotRules = {}

export type Summary = {
	slot: number,
	empty: boolean,
	name: string?,
	look: CharacterLooks.Look?,
	level: number,
	levelName: string,
	money: number,
	pieces: number,
	moves: number,
	played: number,
	savedAt: number?,
}

local function whole(n: any): number
	return if type(n) == "number" and n == n and n > -math.huge and n < math.huge then math.max(0, math.floor(n)) else 0
end

function SaveSlotRules.key(userId: number, slot: number): string
	return if slot <= 1 then `Player_{userId}` else `Player_{userId}_slot{slot}`
end

function SaveSlotRules.slot(raw: any): number?
	if type(raw) ~= "number" or raw ~= raw or raw % 1 ~= 0 or raw < 1 or raw > Config.SaveSlots.Count then
		return nil
	end
	return raw
end

function SaveSlotRules.real(saved: any): boolean
	return type(saved) == "table" and type(saved.money) == "number"
end

local function levelName(level: number): string
	local list = Config.Warehouse.Levels
	local def = list[math.clamp(level, 1, #list)]
	return if def then def.name else "Warehouse"
end

function SaveSlotRules.summary(slot: number, saved: any): Summary
	if not SaveSlotRules.real(saved) then
		return { slot = slot, empty = true, level = 1, levelName = levelName(1), money = 0, pieces = 0, moves = 0, played = 0 }
	end
	local level = UpgradeRules.warehouseLevel(UpgradeRules.fromSave(saved))
	local character = if type(saved.character) == "table" then saved.character else nil
	local name = if character then CharacterLooks.name(character.name) else nil
	return {
		slot = slot,
		empty = false,
		name = name,
		look = if character then CharacterLooks.clean(character) else nil,
		level = level,
		levelName = levelName(level),
		money = whole(saved.money),
		pieces = #CollectionRules.fromSave(saved).entries,
		moves = SandboxBadgeRules.movesFromSave(saved),
		played = whole(saved.playTime),
		savedAt = if whole(saved.savedAt) > 0 then whole(saved.savedAt) else nil,
	}
end

function SaveSlotRules.latest(summaries: { Summary }): number?
	local best: number?, at = nil, -1
	for _, summary in summaries do
		if not summary.empty and (summary.savedAt or 0) > at then
			best, at = summary.slot, summary.savedAt or 0
		end
	end
	return best
end

function SaveSlotRules.played(seconds: number): string
	local minutes = math.floor(whole(seconds) / 60)
	if minutes < 1 then
		return ""
	elseif minutes < 60 then
		return `{minutes} min`
	end
	return string.format("%d h %02d min", minutes // 60, minutes % 60)
end

function SaveSlotRules.ago(savedAt: number?, now: number): string
	if not savedAt or savedAt <= 0 then
		return ""
	end
	local seconds = math.max(0, now - savedAt)
	if seconds < 120 then
		return "just now"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)} min ago`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)} h ago`
	elseif seconds < 2 * 86400 then
		return "yesterday"
	end
	return `{math.floor(seconds / 86400)} days ago`
end

function SaveSlotRules.money(n: number): string
	local text = tostring(whole(n))
	local out = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return "$" .. out
end

return SaveSlotRules
