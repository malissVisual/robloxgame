-- Regression checks for readable short-screen phones and live/safe order presentation.
local Phone = require("./PhoneLayout")
local function check(name: string, value: boolean)
	assert(value, name)
	print("ok    " .. name)
end

for _, screen in {{1920,1000,false},{1280,650,false},{900,500,false},{320,448,true},{390,800,true},{844,350,true},{667,335,true},{1024,720,true}} do
	local w,h,touch = screen[1],screen[2],screen[3]
	local fit = Phone.fit(w,h,touch,.9)
	check(`{w}x{h}: fits horizontally`, fit.width*fit.scale <= w-32+.001)
	check(`{w}x{h}: fits vertically`, fit.height*fit.scale <= h-32+.001)
	check(`{w}x{h}: readable scale`, fit.scale >= .83)
	if touch then check(`{w}x{h}: touch target >=44`, 54*fit.scale >= 44) end
end
check("wide short phone turns sideways", Phone.fit(844,350,true,1).sideways)
check("narrow short phone scrolls instead of shrinking", not Phone.fit(320,448,true,1).sideways and Phone.fit(320,448,true,1).height < 680)
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
