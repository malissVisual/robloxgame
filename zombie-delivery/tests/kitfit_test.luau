-- 5.0, the worn kit (shared/KitFit.luau, server/KitWear.luau): what a player wears for the kit they own, and how
-- Codex's art, authored for a nominal block R15 body, is fitted to the body parts the character really has.
-- Run with tests/run_tests.py.
local KitFit = require("./KitFit")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end
local function same(a: { number }, b: { number }): boolean
	return near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3])
end
local function count(t: { [string]: string }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- The outfit -------------------------------------------------------------------------------------------------------

check("nothing owned: nothing worn", count(KitFit.outfit({})) == 0)
-- 6.6: no backpack slot any more (one carrying item): an old kit's backpack ids wear nothing
local old = KitFit.outfit({ backpack = true, bigpack = true } :: any)
check("6.6: an old backpack is never worn", count(old) == 0 and (old :: any).pack == nil and (old :: any).load == nil)
local all = KitFit.outfit({ backpack = true, shoes = true, jacket = true } :: any)
check("everything: shoes, jacket (6.6: no pack, no parcel)", all.shoes == "shoes" and all.jacket == "jacket" and count(all) == 2)
check("a false entry is not owned", count(KitFit.outfit({ shoes = false, jacket = false })) == 0)
-- 6.0: the plastic bag in the hand, the best vest over the courier's
local bagged = KitFit.outfit({ bag = true })
check("the bag in the hand", bagged.hand == "bag" and count(bagged) == 1)
check("the Kevlar vest", KitFit.outfit({ kevlar = true }).vest == "kevlar")
local vests = KitFit.outfit({ kevlar = true, heavy = true, bag = true })
check("both vests: only the heavy armour", vests.vest == "heavy" and vests.hand == "bag" and count(vests) == 2)
check("a false bag or vest is not worn", count(KitFit.outfit({ bag = false, kevlar = false, heavy = false, hivis = false })) == 0)
-- 6.0.1: the Courier Vest (the red reflective one) in the same slot; an armoured vest is worn instead of it
local hivis = KitFit.outfit({ hivis = true, bag = true })
check("the Courier Vest", hivis.vest == "hivis" and hivis.hand == "bag" and count(hivis) == 2)
check("the Courier Vest and the Kevlar: the Kevlar shows", KitFit.outfit({ hivis = true, kevlar = true }).vest == "kevlar")
check("the Courier Vest and the heavy armour: the armour shows", KitFit.outfit({ hivis = true, kevlar = true, heavy = true }).vest == "heavy")

-- The factors ------------------------------------------------------------------------------------------------------

check("the nominal torso: 1, 1, 1", same(KitFit.factors("UpperTorso", { 2, 1.6, 1 }), { 1, 1, 1 }))
check("a wider, deeper torso", same(KitFit.factors("UpperTorso", { 2.4, 1.6, 1.3 }), { 1.2, 1, 1.3 }))
check("the nominal foot", same(KitFit.factors("LeftFoot", { 1, 0.3, 1.2 }), { 1, 1, 1 }))
check("a short foot", same(KitFit.factors("RightFoot", { 1, 0.3, 1 }), { 1, 1, 1 / 1.2 }))
check("clamped below", same(KitFit.factors("UpperTorso", { 0.1, 1.6, 1 }), { KitFit.Min, 1, 1 }))
check("clamped above", same(KitFit.factors("UpperTorso", { 20, 1.6, 1 }), { KitFit.Max, 1, 1 }))
check("a broken size: 1", same(KitFit.factors("UpperTorso", { 0, 0 / 0, math.huge }), { 1, 1, 1 }))
check("an unknown bone: 1", same(KitFit.factors("Tail", { 5, 5, 5 }), { 1, 1, 1 }))
local hand = KitFit.factors("RightHand", { 1.2, 0.5, 1 })
check("the hand: one factor for all three axes", near(hand[1], 1.1) and near(hand[2], 1.1) and near(hand[3], 1.1), hand[1])
local bigHand = KitFit.factors("RightHand", { 3, 3, 3 })
check("the hand: clamped tighter", near(bigHand[1], KitFit.HandMax) and near(bigHand[2], KitFit.HandMax))

-- The fit ----------------------------------------------------------------------------------------------------------

local pieces = {
	{ name = "Body", size = { 1, 2, 0.5 }, at = { 0.5, -0.2, 1 }, attach = "UpperTorso", finish = "cloth" },
	{ name = "Top", size = { 1, 0.2, 0.5 }, at = { 0, 0.7, 1 }, attach = "UpperTorso", finish = "cloth", turn = { 0, 180, 0 } },
	{ name = "Side", size = { 1, 0.2, 0.4 }, at = { 0, 0, 0 }, attach = "UpperTorso", finish = "cloth", turn = { 0, 0, 90 } },
	{ name = "Sole", size = { 1, 0.1, 1.4 }, at = { 0, -0.2, 0 }, attach = "LeftFoot", finish = "sole" },
}
local scales = { UpperTorso = { 1.5, 1, 2 } }
local fitted = KitFit.fit(pieces, scales)
check("a copy per piece", #fitted == 4 and fitted[1] ~= pieces[1])
check("the offset scales per axis", same(fitted[1].at, { 0.75, -0.2, 2 }), fitted[1].at[3])
check("the size scales per axis", same(fitted[1].size, { 1.5, 2, 1 }))
check("turned half round: still per axis", same(fitted[2].size, { 1.5, 0.2, 1 }) and same(fitted[2].at, { 0, 0.7, 2 }))
check("turned a quarter about Z: x and y swap their factors", same(fitted[3].size, { 1, 0.3, 0.8 }), `{fitted[3].size[1]} {fitted[3].size[2]}`)
check("a bone not measured: as authored", same(fitted[4].size, pieces[4].size) and same(fitted[4].at, pieces[4].at))
check("the other fields are kept", fitted[2].name == "Top" and fitted[2].finish == "cloth" and fitted[2].turn == pieces[2].turn)
check("the input is not changed", same(pieces[1].size, { 1, 2, 0.5 }) and same(pieces[1].at, { 0.5, -0.2, 1 }))
local uniform = KitFit.fit(pieces, { UpperTorso = { 1.2, 1.2, 1.2 } })
check("a uniform scale: every size by it, whatever the turn", same(uniform[3].size, { 1.2, 0.24, 0.48 }) and same(uniform[2].size, { 1.2, 0.24, 0.6 }))
local oblique = KitFit.fit({ { size = { 1, 1, 1 }, at = { 0, 0, 0 }, attach = "UpperTorso", turn = { 0, 0, 45 } } }, { UpperTorso = { 2, 1, 1 } })
check("an oblique piece: between the factors", oblique[1].size[1] > 1 and oblique[1].size[1] < 2 and near(oblique[1].size[3], 1))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
