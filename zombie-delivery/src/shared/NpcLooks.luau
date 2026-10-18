--!strict
-- What the world's people wear (6.8: moved here from server/Npcs.luau, which still dresses the R15 bodies with it):
-- a look per role, the skin and the hair from the name. 10.6 (only the sandbox is the game): two roles are left, the
-- crew's mover (shared/CrewRules.luau dresses Danny and the others on it) and the townsperson (shared/Visitors.luau
-- dresses the showroom's visitors on it); the city's employers, receivers, kids, soldiers, doctors, patients, Marge
-- and Walt went with it. Pure data and one function: required by shared/CrewRules.luau and shared/Visitors.luau.

local NpcLooks = {}

export type Look = {
	name: string, -- shown over the head
	title: string?, -- a second line ("Mover", "Collector")
	skin: { number }?, -- r, g, b
	shirt: { number }?,
	pants: { number }?,
	hat: string?, -- none | cap | beanie | helmet
	hatColor: { number }?,
	hair: { number }?, -- hair colour (nil = none showing)
	vest: { number }?, -- a vest over the shirt
	apron: { number }?, -- an apron (or overalls' bib) in front
	shoes: { number }?,
	boots: boolean?, -- the shins in the shoe colour (work boots)
	shortSleeves: boolean?, -- forearms show the skin
	coat: { number }?, -- a long coat over everything
	tie: { number }?, -- a tie down the shirt front
	walkSpeed: number?, -- studs / s (default 8)
}

-- The roles NpcLooks.look dresses (anything else is a townsperson).
NpcLooks.Roles = { "mover", "townsperson" }

local SKINS = { { 255, 224, 196 }, { 241, 194, 160 }, { 214, 160, 120 }, { 176, 122, 84 }, { 132, 88, 60 }, { 98, 66, 46 } }
local HAIRS = { { 40, 30, 24 }, { 74, 50, 32 }, { 120, 84, 50 }, { 196, 160, 100 }, { 150, 150, 150 }, { 30, 26, 26 } }
local SHIRTS = { { 70, 110, 160 }, { 160, 60, 60 }, { 90, 130, 90 }, { 200, 180, 140 }, { 120, 90, 140 }, { 60, 60, 66 }, { 210, 140, 60 } }
local PANTS = { { 50, 64, 100 }, { 60, 60, 64 }, { 110, 90, 70 }, { 40, 40, 44 }, { 150, 130, 100 } }

local function hash(text: string): number
	local h = 7
	for n = 1, #text do
		h = (h * 31 + string.byte(text, n)) % 1000003
	end
	return h
end

local function pick<T>(list: { T }, h: number, salt: number): T
	return list[(h // salt) % #list + 1]
end

-- A quick look for a role (consistent outfits): "mover", anything else = a townsperson. Skin and hair come from the
-- name, so the same person always looks the same.
function NpcLooks.look(role: string, name: string, title: string?): Look
	local h = hash(name .. role)
	local look: Look = {
		name = name,
		title = title,
		skin = pick(SKINS, h, 1),
		hair = pick(HAIRS, h, 7),
		shirt = pick(SHIRTS, h, 11),
		pants = pick(PANTS, h, 13),
		shoes = { 46, 38, 32 },
	}
	if role == "mover" then
		look.hat, look.hatColor = "cap", { 230, 120, 40 }
		look.shirt, look.pants = { 230, 120, 40 }, { 60, 60, 70 }
		look.shortSleeves, look.boots = true, true
	else
		look.hat = if h % 5 == 0 then "cap" elseif h % 5 == 1 then "beanie" else "none"
		look.hatColor = pick(SHIRTS, h, 29)
		look.shortSleeves = h % 2 == 0
	end
	return look
end

return NpcLooks
