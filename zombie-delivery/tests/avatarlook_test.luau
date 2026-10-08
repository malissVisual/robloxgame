-- Logic test of 6.9's one body for every courier (shared/AvatarLook.luau) in the standalone Luau CLI: the classic body
-- resets every body part but the head, the proportions to the classic ones and every movement animation (the couriers
-- walk with the game's), and never touches what stays the player's (the head, the face, the clothes, the colours, the
-- accessories); the workwear colours are real colours.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local AvatarLook = require("./AvatarLook")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local body = AvatarLook.Body
for _, part in { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
	check(`the {part} is Roblox's default`, body[part] == 0 and table.find(AvatarLook.Parts, part) ~= nil)
end
check("the head is the player's own", body.Head == nil and table.find(AvatarLook.Parts, "Head") == nil)
check("the classic proportions", body.HeightScale == 1 and body.WidthScale == 1 and body.DepthScale == 1 and body.HeadScale == 1
	and body.BodyTypeScale == 0 and body.ProportionScale == 0)
for _, track in { "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim" } do
	check(`no {track} animation of the avatar's own`, body[track .. "Animation"] == 0)
end
for _, field in AvatarLook.Kept do
	check(`{field} stays the player's`, body[field] == nil)
end
for _, field in { "Head", "Face", "Shirt", "Pants", "GraphicTShirt", "MoodAnimation", "HairAccessory", "HatAccessory" } do
	check(`{field} is listed as kept`, table.find(AvatarLook.Kept, field) ~= nil)
end
local colours = 0
for field, c in AvatarLook.Workwear do
	colours += 1
	check(`the workwear's {field} is a colour`, field:sub(-5) == "Color" and #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0
		and c[2] <= 255 and c[3] >= 0 and c[3] <= 255)
end
check("the workwear colours the whole body", colours == 6)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
