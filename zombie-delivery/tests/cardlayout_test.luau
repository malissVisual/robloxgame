-- Logic test of 6.18, the UI kit's layout maths (shared/CardLayout.luau; client/CardKit.luau draws with it): when the
-- hero stands beside the rows, the columns' widths, the hero's heights (a popup's, the phone home's), its big value,
-- the words at its foot (JOBS' 6.17 numbers kept), when it carries its button, a row's name column and its action.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local CardLayout = require("./CardLayout")
local Config = require("./Config")

local KIT = Config.UiKit
local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The split ───────────────────────────────────────────────────────────────
check("Config.UiKit: the sizes in order", KIT.HeroMin < KIT.HeroMax and KIT.HomeHeroMin < KIT.HomeHeroMax and KIT.HeroShare > 0 and KIT.HeroShare < 1
	and KIT.Row >= KIT.Add and KIT.Row >= 44 and KIT.Button >= 44 and KIT.HomeButton >= 36 and KIT.Thumb >= KIT.Icon and KIT.Chip > 0)
check("a wide body (the desktop popup, 760) splits: the hero on the left", CardLayout.side(760) and CardLayout.side(KIT.SplitMin))
check("a narrow one stacks (the upright phone, 294; a phone's popup, 358)", not CardLayout.side(294) and not CardLayout.side(358) and not CardLayout.side(KIT.SplitMin - 1))
local hero, rows = CardLayout.columns(760)
check("side by side: the hero's share, the rows the rest, 10 px between", hero == math.floor(760 * KIT.HeroShare) - 5 and hero + rows + 10 == 760, `{hero} {rows}`)
local whole, rest = CardLayout.columns(320)
check("stacked: both whole", whole == 320 and rest == 320)

-- ── The hero ────────────────────────────────────────────────────────────────
check("a popup's hero: its room, clamped", CardLayout.heroHeight(100) == KIT.HeroMin and CardLayout.heroHeight(280.7) == 280 and CardLayout.heroHeight(900) == KIT.HeroMax)
check("its value: big on a tall hero, smaller else", CardLayout.valueSize(KIT.PayTall) == KIT.PayBig and CardLayout.valueSize(KIT.PayTall - 1) == KIT.PayMid and KIT.PayBig > KIT.PayMid)
local lines, height = CardLayout.heroInfo(52, true, false, 44)
check("JOBS' words at the foot as in 6.17 (head, pay, facts, gap, button; 4 px apart)", #lines == 5 and height == 16 + (52 + 2) + 18 + 4 + 44 + 4 * 4, height)
local homeLines, homeH = CardLayout.heroInfo(KIT.HomeValue, true, true, 0)
check("the home's hero without a button: head, value, facts, bar", #homeLines == 4 and homeH == 16 + KIT.HomeValue + 2 + 18 + 4 + 3 * 4, homeH)
check("… it fits the least home hero with its ribbon over it", homeH + CardLayout.EDGE + 34 <= KIT.HomeHeroMin)
local _, withButton = CardLayout.heroInfo(KIT.HomeValue, true, true, KIT.HomeButton)
check("… with its button it fits from ButtonHeroMin", withButton + CardLayout.EDGE + 34 <= KIT.ButtonHeroMin, withButton)
check("the home's hero: the view's room, clamped", CardLayout.homeHero(1000, 38, 60) == KIT.HomeHeroMax and CardLayout.homeHero(200, 38, 60) == KIT.HomeHeroMin and CardLayout.homeHero(250, 38, 60) == 152)
check("the button from ButtonHeroMin", CardLayout.hasButton(KIT.ButtonHeroMin) and not CardLayout.hasButton(KIT.ButtonHeroMin - 1))
check("stack: the lines and the gaps between them", CardLayout.stack({ 10, 20, 30 }, 4) == 68 and CardLayout.stack({}, 4) == 0 and CardLayout.stack({ 5 }, 4) == 5)

-- ── The row ─────────────────────────────────────────────────────────────────
check("the round action: Add px; a lock's words widen it", CardLayout.action(nil) == KIT.Add and CardLayout.action(10) == KIT.Add and CardLayout.action(60) == 74)
local x, w = CardLayout.rowText(KIT.Thumb, 44, KIT.Add, 60)
check("JOBS' row name column as in 6.17 (thumb + 10 + the danger's 44)", x == KIT.Thumb + 10 + 44 and w == -(x + KIT.Add + 60 + 24), `{x} {w}`)
local ax, aw = CardLayout.rowText(KIT.Icon, 0, KIT.Add, 0)
check("an app's row: no tag, no value: the name has the room", ax == KIT.Icon + 10 and aw == -(ax + KIT.Add + 24))
check("on the upright phone (294 px) an app's name keeps at least 150 px", 294 + aw >= 150, 294 + aw)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECKS FAILED`)
end
