-- Regression checks for readable short-screen phones and live/safe order presentation.
local Phone = require("./PhoneLayout")
local function check(name: string, value: boolean)
	assert(value, name)
	print("ok    " .. name)
end

for _, screen in {{1920,1000,false},{1280,650,false},{900,500,false},{320,448,true},{390,800,true},{844,350,true},{667,335,true},{640,324,true},{640,316,true},{1024,720,true}} do
	local w,h,touch = screen[1],screen[2],screen[3]
	local fit = Phone.fit(w,h,touch,.9)
	check(`{w}x{h}: fits horizontally`, fit.width*fit.scale <= w-32+.001)
	check(`{w}x{h}: fits vertically`, fit.height*fit.scale <= h-32+.001)
	check(`{w}x{h}: readable scale`, fit.scale >= .83)
	if touch then check(`{w}x{h}: touch target >=44`, 54*fit.scale >= 44) end
end
-- 6.0.1: the phone never turns sideways; a short wide screen gets a shorter upright phone that scrolls.
check("a wide short phone stays upright", Phone.fit(844,350,true,1).width == 340 and Phone.fit(844,350,true,1).sideways == nil)
check("narrow short phone scrolls instead of shrinking", Phone.fit(320,448,true,1).height < 680)
check("a short desktop shrinks the phone a little, never under SHORT_SCALE", Phone.fit(900,500,false,1).scale >= Phone.SHORT_SCALE and Phone.fit(900,500,false,1).scale < 1)
check("a tall desktop keeps the full phone", Phone.fit(1920,1080,false,.95).scale == .95 and Phone.fit(1920,1080,false,.95).height == 680)
-- 6.0.1: every app opens in a centred popup: 760 x 520 at the desktop scale, within 92 % / 86 % of the screen.
for _, screen in {{1920,1000,false},{1280,650,false},{900,500,false},{1150,680,false},{320,448,true},{390,800,true},{844,350,true},{667,335,true},{640,324,true},{640,316,true},{1024,720,true}} do
	local w,h,touch = screen[1],screen[2],screen[3]
	local pop = Phone.popup(w,h,touch,if touch then 1 else math.clamp(math.min(w/1150,h/680),.85,1.1))
	check(`{w}x{h}: the popup fits 92 % of the width`, pop.width*pop.scale <= w*.92+.001)
	check(`{w}x{h}: the popup fits 86 % of the height`, pop.height*pop.scale <= h*.86+.001)
	check(`{w}x{h}: the popup is at most 760 x 520`, pop.width <= 760 and pop.height <= 520)
	if touch then check(`{w}x{h}: popup touch targets >=36`, 54*pop.scale >= 36 and pop.scale == 1) end
end
-- 6.14: NEXT MISSION and WORK (the home's two wide tiles) stand wholly above the fold, on the shortest phone too.
for _, screen in {{1920,1000,false},{1280,650,false},{900,500,false},{320,448,true},{390,800,true},{844,350,true},{844,390,true},{667,335,true},{640,324,true},{640,316,true}} do
	local w,h,touch = screen[1],screen[2],screen[3]
	check(`{w}x{h}: NEXT MISSION and WORK above the fold`, Phone.mainVisible(Phone.fit(w,h,touch,.9)))
end
check("6.14: NEXT MISSION is the taller tile, touch-sized", Phone.NEXT_H > Phone.WORK_H and Phone.WORK_H >= 54)
-- 6.14 review: the home's list is the phone's height less its frame (BEZELS) and its chrome; where each tile is comes
-- from the layout (Phone.reveal scrolls with it: no stale positions right after opening or a resize).
check("the home's view: the phone less its frame and chrome", Phone.homeView(Phone.fit(1920,1000,false,.9)) == 680 - Phone.BEZELS - Phone.HOME_CHROME)
local nextTop, nextH = Phone.tileSpan(true, 1)
local workTop, workH = Phone.tileSpan(true, 2)
local firstTop, firstH = Phone.tileSpan(false, 1)
local secondTop = Phone.tileSpan(false, 2)
local mapTop = Phone.tileSpan(false, 3)
check("the tiles' spans: NEXT, WORK under it, the grid two to a row", nextTop == Phone.HOME_HEAD and nextH == Phone.NEXT_H and workTop == nextTop + Phone.NEXT_H + Phone.MAIN_GAP and workH == Phone.WORK_H
	and firstTop == workTop + Phone.WORK_H + Phone.MAIN_GAP and firstH == Phone.TILE_H and secondTop == firstTop and mapTop == firstTop + Phone.TILE_H + Phone.TILE_GAP)
check("reveal: a tile in view keeps the scroll", Phone.reveal(mapTop, Phone.TILE_H, 0, 500) == 0)
local short = Phone.homeView(Phone.fit(640,316,true,.9))
local bagTop = Phone.tileSpan(false, 5)
local y = Phone.reveal(bagTop, Phone.TILE_H, 0, short)
check("reveal: a tile under the fold scrolls up just enough (640 x 316)", y > 0 and bagTop + Phone.TILE_H <= y + short and bagTop >= y)
check("reveal: a tile over the top scrolls back", Phone.reveal(nextTop, nextH, 200, short) == math.max(0, nextTop - 8))
local desk = Phone.popup(1150,680,false,1)
check("the desktop popup is 760 x 520", desk.width == 760 and desk.height == 520 and desk.wide)
check("a narrow phone's popup has one column", not Phone.popup(390,800,true,1).wide)
check("a tablet's popup has two columns", Phone.popup(1024,720,true,1).wide)
check("no job: board instead of invented contract", not Phone.summary(nil,100).active)
local summary = Phone.summary({stopLabel="Harbor warehouse",total=2,pay=180,endsAt=376,timeLimit=400,position={X=30,Z=40},orders={{state="open"},{state="done"},{state="open"}}},100,0,0)
check("current server stop title", summary.title == "HARBOR WAREHOUSE")
check("counts only open orders", summary.count == 2)
check("real countdown / pay", summary.left == 276 and summary.pay == 180)
check("remaining share from actual time limit", math.abs(summary.share-.69)<.0001)
check("distance labelled in studs", summary.meta == "2 pieces · 50 studs away")
local expired = Phone.summary({endsAt=90,timeLimit=10,pay=50},100)
check("expired countdown clamped", expired.left == 0 and expired.share == 0)
local short = Phone.summary({cargo="Letters",customer="Marge"},100)
check("fallback payload keeps useful title", short.title == "MARGE")
check("unknown clock is not fabricated", short.left == nil and short.share == 0)
check("no distance without player position", not string.find(short.meta,"studs"))
print("ALL CHECKS PASSED")
