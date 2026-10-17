--!strict
-- 6.23: shared/CareerArt.luau, the career's pictures (Codex's codex/career-thumbnails scenes): a slot for every danger
-- tier and every property, the special jobs' and chapters' pictures from JobThumbs / MissionArt, the kit and guns as
-- their 3D models (ItemLooks keys that build), and a level's one headline picture (an image before a model).
local Config = require("./Config")
local Career = require("./Career")
local CareerArt = require("./CareerArt")
local JobThumbs = require("./JobThumbs")
local MissionArt = require("./MissionArt")
local ItemLooks = require("./ItemLooks")

local failures = 0
local function check(name: string, ok: boolean)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name)
	end
end

-- Every slot: "" or an uploaded id; one a tier and one a property, nothing else.
local wanted: { [string]: boolean } = {}
for index in Config.Jobs.Tiers do
	wanted[`tier:{index}`] = true
end
for _, def in Config.Estate.Properties do
	wanted[CareerArt.propertyKey(def)] = true
end
local slots, extra, missing = 0, {}, {}
for key, image in CareerArt.Images do
	slots += 1
	if not wanted[key] then
		table.insert(extra, key)
	end
	if image ~= "" and not string.match(image, "^rbxassetid://%d+$") then
		table.insert(extra, `{key} = {image}`)
	end
end
for key in wanted do
	if CareerArt.Images[key] == nil then
		table.insert(missing, key)
	end
end
check(`a slot for each of the {#Config.Jobs.Tiers} tiers and {#Config.Estate.Properties} properties ({slots})`, #extra == 0
	and #missing == 0)
check("a garage's key is garage:<id>, a home's or an office's estate:<id>",
	CareerArt.propertyKey({ id = "garage_rented", kind = "garage" }) == "garage:garage_rented"
		and CareerArt.propertyKey({ id = "elm", kind = "house" }) == "estate:elm"
		and CareerArt.propertyKey({ id = "office_tower", kind = "office" }) == "estate:office_tower")

-- Every unlock on the road: its picture is the right source.
local road = Career.road()
local bad: { string } = {}
local jobs, chapters, models = 0, 0, 0
for _, step in road do
	for _, unlock in step.unlocks do
		local key = `{unlock.kind}:{unlock.id}`
		local picture = CareerArt.forUnlock(unlock)
		if unlock.kind == "job" then
			local asset = JobThumbs.Special[unlock.id]
			local image = if asset then JobThumbs.Images[asset] else nil
			jobs += 1
			if not picture or picture.image ~= image or image == "" then
				table.insert(bad, key)
			end
		elseif unlock.kind == "campaign" then
			local image = MissionArt.forCampaign(unlock.id)
			chapters += 1
			if (picture and picture.image) ~= image then
				table.insert(bad, key)
			end
		elseif unlock.kind == "kit" or unlock.kind == "gun" then
			models += 1
			if not picture or picture.model ~= key or not ItemLooks.has(key) then
				table.insert(bad, key)
			end
		elseif CareerArt.Images[key] ~= nil then
			if (picture and picture.image) ~= CareerArt.image(key) then
				table.insert(bad, key)
			end
		elseif picture ~= nil then
			table.insert(bad, `{key} (no picture expected)`)
		end
	end
end
check(`the road's unlocks: {jobs} special jobs show their business, {chapters} chapters their picture, {models} kit and guns their model`,
	#bad == 0 and jobs > 0 and chapters > 0 and models > 0)
if #bad > 0 then
	print("      " .. table.concat(bad, ", "))
end

-- A level's headline: an image before a model, the road's order, nil without either.
local saved = CareerArt.Images["tier:2"]
CareerArt.Images["tier:2"] = "rbxassetid://1"
local tote = { kind = "kit", id = "tote" }
local tier = { kind = "tier", id = "2" }
local school = { kind = "job", id = "schoolrun" }
local first = CareerArt.headline({ tote, tier, school })
check("an image comes before a model", first ~= nil and first.image == "rbxassetid://1" and first.model == nil)
local second = CareerArt.headline({ tote, { kind = "tier", id = "1" } })
check("a model when nothing has an image", second ~= nil and second.model == "kit:tote")
local third = CareerArt.headline({ { kind = "car", id = "van" }, { kind = "stage", id = "van:1", car = "van" } })
check("nothing for a level of cars and stages", third == nil)
CareerArt.Images["tier:2"] = saved
check("an empty slot is no image", CareerArt.image("tier:2") == nil and CareerArt.image("nothing") == nil)

assert(failures == 0, `{failures} career art checks failed`)
print("ALL CHECKS PASSED")
