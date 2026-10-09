-- 6.8, the MISSIONS window's measures (client/MissionsLayout.luau): it fits a 1280 × 720 monitor and an iPhone SE
-- held sideways (and the screens around them), the text stays readable, the touch targets big, and a small screen
-- stacks the clients on top of the chapter.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local MissionsLayout = require("./MissionsLayout")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local TOPBAR = 36 -- Roblox's top bar (the ScreenGui's area is the viewport under it)
local SCREENS = {
	{ name = "1280 × 720", x = 1280, y = 720 - TOPBAR },
	{ name = "1920 × 1080", x = 1920, y = 1080 - TOPBAR },
	{ name = "1366 × 768", x = 1366, y = 768 - TOPBAR },
	{ name = "1024 × 768 (iPad)", x = 1024, y = 768 - TOPBAR },
	{ name = "iPhone SE sideways (667 × 375)", x = 667, y = 375 - TOPBAR },
	{ name = "a phone sideways (844 × 390)", x = 844, y = 390 - TOPBAR },
	{ name = "a small window (800 × 600)", x = 800, y = 600 - TOPBAR },
}

for _, screen in SCREENS do
	local layout = MissionsLayout.fit(screen.x, screen.y)
	local onScreenW, onScreenH = layout.width * layout.scale, layout.height * layout.scale
	check(`{screen.name}: the window fits the screen`, onScreenW <= screen.x - MissionsLayout.Margin + 0.5 and onScreenH <= screen.y - MissionsLayout.Margin + 0.5,
		`{math.floor(onScreenW)} × {math.floor(onScreenH)}`)
	check(`{screen.name}: readable text (≥ 11 px on screen)`, layout.small * layout.scale >= 9 and layout.text * layout.scale >= 11, layout.text * layout.scale)
	check(`{screen.name}: START and a client card are big enough to tap (≥ 36 px)`, layout.start * layout.scale >= 36 and layout.cardH * layout.scale >= 44)
	local page = MissionsLayout.pageHeight(layout)
	if layout.narrow then
		check(`{screen.name}: narrow: the strip on top leaves the chapter room`, page - layout.stripH >= 170, page - layout.stripH)
	else
		check(`{screen.name}: wide: the column and the chapter side by side, a hero portrait`, layout.width - layout.listW >= 560 and page >= 400 and layout.heroH <= page, `{layout.width - layout.listW} × {page}`)
	end
	-- 6.8 review: START in view (it sat under the fold at 1280 × 720, two screens down on a phone): the action bar
	-- under the chapter ends inside the window's content, holds START, and the chapter above it still scrolls a story.
	local parts = MissionsLayout.parts(layout)
	check(`{screen.name}: START in view: the action bar under the chapter, inside the window`, parts.barTop >= parts.chapterTop + parts.chapterH
		and parts.barTop + parts.barH <= parts.contentH and parts.barH >= layout.start and parts.chapterTop >= layout.tabs,
		`bar {parts.barTop} – {parts.barTop + parts.barH} of {parts.contentH}`)
	check(`{screen.name}: the chapter keeps room above the bar`, parts.chapterH >= (if layout.narrow then 140 else 360), parts.chapterH)
	-- 6.12.13: the chapter's picture banner (client/MissionArtUi.luau) fits the chapter's view whole.
	check(`{screen.name}: the picture banner fits the chapter's view`, layout.art >= 96 and layout.art <= parts.chapterH - 8, `{layout.art} of {parts.chapterH}`)
end

do
	local monitor = MissionsLayout.fit(1280, 720 - TOPBAR)
	check("1280 × 720: the full window at about scale 1, side by side", not monitor.narrow and monitor.width == 1000 and monitor.height == 640 and math.abs(monitor.scale - 1) < 0.05, monitor.scale)
	local phone = MissionsLayout.fit(667, 375 - TOPBAR)
	check("iPhone SE: stacked (the clients on top), the slim chrome, the bigger text", phone.narrow and phone.scale >= MissionsLayout.MinScale and phone.header < 78 and phone.text > monitor.text)
	check("iPhone SE: a smaller hero portrait (6.8 review)", phone.heroW <= 80 and phone.heroW < monitor.heroW, phone.heroW)
	-- 6.12.13: at 1280 × 720 the banner opens the chapter at 2.6 : 1 (its width: the window less the column and
	-- MissionsUi's inset, listW + 22, the list's padding 13 and the row's 4); on a phone it sits above the story path.
	local artW = monitor.width - (monitor.listW + 22) - 13 - 4
	check("1280 × 720: the picture banner opens the chapter at 2.6 : 1", monitor.artOnTop and math.floor(artW / MissionsLayout.ArtRatio + 0.5) <= monitor.art,
		`{artW} / {MissionsLayout.ArtRatio} > {monitor.art}`)
	check("iPhone SE: the banner sits above the story path (the hero and the action card first)", not phone.artOnTop and phone.art < monitor.art)
	local big = MissionsLayout.fit(3840, 2160)
	check("a 4K screen: never bigger than MaxScale", big.scale <= MissionsLayout.MaxScale and not big.narrow)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
