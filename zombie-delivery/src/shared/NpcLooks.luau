--!strict
-- What the world's people wear (6.8: moved here from server/Npcs.luau, which still dresses the R15 bodies with it):
-- a look per role, the skin and the hair from the name. Shared so the client draws the same people: the MISSIONS
-- window's portraits (client/Portrait.luau) build the client's bust from the very look their NPC wears in the world.
-- Pure data and one function: required by server/Npcs.luau, client/Portrait.luau and tests/missions_story_test.luau.

local NpcLooks = {}

export type Look = {
	name: string, -- shown over the head
	title: string?, -- a second line ("Rancher", "Sergeant")
	skin: { number }?, -- r, g, b
	shirt: { number }?,
	pants: { number }?,
	hat: string?, -- none | cap | cowboy | hardhat | beanie | chef | helmet
	child: boolean?, -- a kid (smaller)
	hatColor: { number }?,
	hair: { number }?, -- hair colour (nil = none showing)
	vest: { number }?, -- a vest over the shirt
	apron: { number }?, -- an apron (or overalls' bib) in front
	shoes: { number }?,
	boots: boolean?, -- the shins in the shoe colour (riding boots, army boots)
	shortSleeves: boolean?, -- forearms show the skin
	coat: { number }?, -- a long coat over everything (the doctor's white coat)
	tie: { number }?, -- a tie down the shirt front
	bandage: boolean?, -- a bandage round the head (a patient)
	walkSpeed: number?, -- studs / s (default 8, a kid 9; a patient shuffles)
}

-- The roles NpcLooks.look dresses (anything else is a townsperson).
NpcLooks.Roles = {
	"rancher", "farmer", "soldier", "officer", "worker", "foreman", "firefighter", "teacher", "kid", "shopkeeper", "grocer",
	"icecream", "mover", "cook", "clerk", "attendant", "rider", "doctor", "nurse", "patient", "banker", "guard", "townsperson",
}

local SKINS = { { 255, 224, 196 }, { 241, 194, 160 }, { 214, 160, 120 }, { 176, 122, 84 }, { 132, 88, 60 }, { 98, 66, 46 } }
local HAIRS = { { 40, 30, 24 }, { 74, 50, 32 }, { 120, 84, 50 }, { 196, 160, 100 }, { 150, 150, 150 }, { 30, 26, 26 } }
local SHIRTS = { { 70, 110, 160 }, { 160, 60, 60 }, { 90, 130, 90 }, { 200, 180, 140 }, { 120, 90, 140 }, { 60, 60, 66 }, { 210, 140, 60 } }
local PANTS = { { 50, 64, 100 }, { 60, 60, 64 }, { 110, 90, 70 }, { 40, 40, 44 }, { 150, 130, 100 } }
local BRIGHT = { { 230, 80, 70 }, { 70, 150, 230 }, { 250, 200, 60 }, { 110, 200, 110 }, { 230, 120, 200 }, { 250, 140, 50 } }

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

-- A quick look for a role (consistent outfits): "rancher", "soldier", "officer", "farmer", "worker", "foreman",
-- "firefighter" (6.8), "teacher", "kid", "shopkeeper", "grocer", "icecream", "mover", "cook", "clerk", "attendant",
-- "rider", "doctor", "nurse", "patient", "banker", "guard", anything else = a townsperson. Skin and hair come from the
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
	if role == "rancher" then
		look.hat, look.hatColor = "cowboy", { 120, 82, 50 }
		look.shirt, look.pants, look.vest = { 168, 52, 44 }, { 58, 76, 112 }, { 96, 64, 40 }
		look.boots, look.shoes = true, { 82, 54, 34 }
	elseif role == "farmer" then
		look.hat, look.hatColor = "cowboy", { 218, 190, 120 }
		look.shirt, look.pants, look.apron = { 196, 186, 156 }, { 66, 92, 136 }, { 66, 92, 136 }
		look.shortSleeves = true
	elseif role == "soldier" or role == "officer" then
		look.hat = if role == "officer" then "cap" else "helmet"
		look.hatColor = { 74, 84, 54 }
		look.shirt, look.pants, look.vest = { 92, 102, 66 }, { 78, 86, 58 }, if role == "soldier" then { 64, 70, 46 } else nil
		look.boots, look.shoes = true, { 34, 30, 26 }
	elseif role == "worker" or role == "foreman" then
		look.hat, look.hatColor = "hardhat", if role == "foreman" then { 240, 120, 30 } else { 240, 200, 40 }
		look.shirt, look.pants, look.vest = { 70, 80, 96 }, { 64, 64, 70 }, { 210, 230, 50 }
		look.boots = true
	elseif role == "firefighter" then
		-- 6.8: Fire Station 9's people: a red helmet, a dark turnout coat with hi-vis stripes, boots.
		look.hat, look.hatColor = "hardhat", { 200, 36, 30 }
		look.shirt, look.pants, look.vest = { 44, 46, 56 }, { 44, 46, 56 }, { 226, 214, 70 }
		look.boots, look.shoes = true, { 26, 24, 22 }
	elseif role == "teacher" then
		look.hat = "none"
		look.shirt, look.pants = { 150, 96, 120 }, { 60, 60, 72 }
	elseif role == "kid" then
		look.child = true
		look.hat = if h % 3 == 0 then "cap" else if h % 3 == 1 then "beanie" else "none"
		look.hatColor = pick(BRIGHT, h, 17)
		look.shirt, look.pants = pick(BRIGHT, h, 19), pick(PANTS, h, 23)
		look.shortSleeves = true
	elseif role == "shopkeeper" or role == "grocer" then
		look.hat = if role == "grocer" then "cap" else "none"
		look.hatColor = { 60, 120, 60 }
		look.shirt, look.pants, look.apron = { 120, 160, 200 }, { 60, 60, 64 }, if role == "grocer" then { 70, 130, 70 } else { 230, 226, 214 }
	elseif role == "icecream" then
		look.hat, look.hatColor = "cap", { 250, 150, 200 }
		look.shirt, look.pants, look.apron = { 245, 245, 250 }, { 80, 120, 180 }, { 250, 170, 210 }
		look.shortSleeves = true
	elseif role == "mover" then
		look.hat, look.hatColor = "cap", { 230, 120, 40 }
		look.shirt, look.pants = { 230, 120, 40 }, { 60, 60, 70 }
		look.shortSleeves, look.boots = true, true
	elseif role == "cook" then
		look.hat, look.hatColor = "chef", { 248, 248, 248 }
		look.shirt, look.pants, look.apron = { 240, 240, 240 }, { 40, 40, 44 }, { 250, 250, 250 }
	elseif role == "clerk" then
		look.hat = "none"
		look.shirt, look.pants, look.vest = { 236, 236, 240 }, { 44, 46, 58 }, { 44, 54, 84 }
		look.shoes = { 24, 24, 26 }
	elseif role == "attendant" then
		look.hat, look.hatColor = "cap", { 200, 40, 40 }
		look.shirt, look.pants = { 200, 44, 40 }, { 50, 50, 56 }
		look.shortSleeves = true
	elseif role == "rider" then
		look.hat, look.hatColor = "helmet", { 30, 30, 34 }
		look.shirt, look.pants, look.vest = { 236, 236, 236 }, { 214, 196, 160 }, { 40, 60, 90 }
		look.boots, look.shoes = true, { 26, 22, 20 }
	elseif role == "doctor" then
		look.hat = "none"
		look.shirt, look.pants, look.coat, look.tie = { 150, 196, 220 }, { 60, 66, 80 }, { 246, 246, 248 }, { 40, 80, 140 }
		look.shoes = { 30, 30, 32 }
	elseif role == "nurse" then
		look.hat = "none"
		look.shirt, look.pants = { 96, 176, 176 }, { 96, 176, 176 }
		look.shortSleeves, look.shoes = true, { 240, 240, 240 }
	elseif role == "patient" then
		-- A hospital gown, a bandaged head, slow on the feet.
		look.hat = "none"
		look.shirt, look.pants = { 176, 206, 226 }, { 176, 206, 226 }
		look.shortSleeves, look.bandage, look.walkSpeed = true, true, 4.5
		look.shoes = { 220, 220, 216 }
	elseif role == "banker" then
		look.hat = "none"
		look.shirt, look.pants, look.vest, look.tie = { 236, 236, 240 }, { 34, 36, 46 }, { 34, 36, 46 }, { 196, 156, 50 }
		look.shoes = { 20, 20, 22 }
	elseif role == "guard" then
		look.hat, look.hatColor = "cap", { 30, 40, 70 }
		look.shirt, look.pants, look.vest = { 60, 76, 120 }, { 30, 34, 50 }, { 34, 38, 48 }
		look.boots, look.shoes = true, { 24, 22, 20 }
	else
		look.hat = if h % 5 == 0 then "cap" elseif h % 5 == 1 then "beanie" else "none"
		look.hatColor = pick(SHIRTS, h, 29)
		look.shortSleeves = h % 2 == 0
	end
	return look
end

return NpcLooks
