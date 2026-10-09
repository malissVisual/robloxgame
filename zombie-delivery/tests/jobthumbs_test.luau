-- Logic test of 6.12.11, the job pictures (shared/JobThumbs.luau, Codex's art/job-thumbnails/): every ordinary
-- business in Config and every special job type has a picture, the shared businesses resolve to one picture, the
-- round and the tutorial have theirs, a picture's name is the game's own name for the business, and an image id that
-- is still empty (not uploaded) gives nil (the fallback banner). tools/job-thumbnails/check.py checks the manifest.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobThumbs = require("./JobThumbs")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The pictures ---------------------------------------------------------------------------------

local count = 0
local missing: { string } = {}
for id, image in JobThumbs.Images do
	count += 1
	if not JobThumbs.Assets[id] then
		table.insert(missing, id)
	end
	if image ~= "" and not string.match(image, "^rbxassetid://%d+$") then
		table.insert(missing, `{id}: {image}`)
	end
end
for id in JobThumbs.Assets do
	if JobThumbs.Images[id] == nil then
		table.insert(missing, `{id} (no image slot)`)
	end
end
check("25 pictures, each with its name, emoji and an image slot (empty or rbxassetid://)", count == 25 and #missing == 0, table.concat(missing, ", "))

-- Every job is mapped --------------------------------------------------------------------------

local unmapped: { string } = {}
local wrongName: { string } = {}
for _, business in Config.Jobs.Businesses do
	local asset = JobThumbs.Ordinary[business.id]
	if not asset or not JobThumbs.Assets[asset] then
		table.insert(unmapped, business.id)
	elseif JobThumbs.Assets[asset].name ~= business.place then
		table.insert(wrongName, `{business.id}: {JobThumbs.Assets[asset].name} / {business.place}`)
	end
end
check("every ordinary business in Config has a picture", #Config.Jobs.Businesses >= 19 and #unmapped == 0, table.concat(unmapped, ", "))
check("an ordinary picture's name is the business's own name (Config place)", #wrongName == 0, table.concat(wrongName, "; "))
local businessIds: { [string]: boolean } = {}
for _, business in Config.Jobs.Businesses do
	businessIds[business.id] = true
end
local stale: { string } = {}
for id in JobThumbs.Ordinary do
	if not businessIds[id] then
		table.insert(stale, id)
	end
end
check("no ordinary entry for a business Config no longer has", #stale == 0, table.concat(stale, ", "))

local specials: { string } = {}
local typeIds: { [string]: boolean } = {}
for _, def in Config.JobTypes do
	typeIds[def.id] = true
	local asset = JobThumbs.Special[def.id]
	if not asset or not JobThumbs.Assets[asset] then
		table.insert(specials, def.id)
	end
end
check("every special job type has a picture", #Config.JobTypes >= 12 and #specials == 0, table.concat(specials, ", "))
local staleTypes: { string } = {}
for id in JobThumbs.Special do
	if not typeIds[id] then
		table.insert(staleTypes, id)
	end
end
check("no special entry for a job type Config no longer has", #staleTypes == 0, table.concat(staleTypes, ", "))
check("the round and the tutorial have pictures", JobThumbs.Assets[JobThumbs.Round] ~= nil and JobThumbs.Assets[JobThumbs.Tutorial] ~= nil)
check("the round is The Daily Undead and its business is the paper round's", JobThumbs.Round == JobThumbs.Ordinary[Config.Jobs.Round.Business])

local used: { [string]: boolean } = { [JobThumbs.Round] = true, [JobThumbs.Tutorial] = true }
for _, asset in JobThumbs.Ordinary do
	used[asset] = true
end
for _, asset in JobThumbs.Special do
	used[asset] = true
end
local unused: { string } = {}
for id in JobThumbs.Assets do
	if not used[id] then
		table.insert(unused, id)
	end
end
check("every picture is used by a job", #unused == 0, table.concat(unused, ", "))

-- The aliases ----------------------------------------------------------------------------------

local function name(info: any): string?
	local _, label = JobThumbs.forJob(info)
	return label
end
check("the cakes are the bakery's", name({ business = "cake" }) == "Daily Bread Bakery" and JobThumbs.assetFor({ business = "cake" }) == JobThumbs.assetFor({ business = "bakery" }))
check("the samples are the lab's", JobThumbs.assetFor({ business = "samples" }) == "lab" and name({ business = "lab" }) == "Research Lab")
check("the Pizza Rush is Luigi's", JobThumbs.assetFor({ special = "pizzarush" }) == JobThumbs.assetFor({ business = "pizzeria" }))
check("Cash Transport is the bank's, the Freight Run the warehouse's", name({ special = "cashrun" }) == "First Zombie Bank" and name({ special = "freightrun" }) == "Harbor Warehouse")
check("the ice cream route and delivery share Frosty's", JobThumbs.assetFor({ special = "icecream" }) == JobThumbs.assetFor({ business = "icecream" }))
check("a board row's special: its jobType.id (special is true there)", JobThumbs.assetFor({ special = true, jobType = { id = "schoolrun", name = "School Run" } }) == "school")
check("the round: The Daily Undead", name({ round = true }) == "The Daily Undead" and name({ round = true, business = "news" }) == "The Daily Undead")
check("the tutorial: the Post Office", name({ tutorial = true }) == "Post Office")
check("a job without a picture (a mission, an unknown id, nothing) has none", name({ mission = { name = "Code Red" } }) == nil and name({ business = "nope" }) == nil and name({ special = "nope" }) == nil and name(nil) == nil and name({}) == nil)

-- An empty image gives nil ---------------------------------------------------------------------

local saved = JobThumbs.Images.pizzeria -- (6.12.11: uploaded; emptied here for the fallback)
JobThumbs.Images.pizzeria = ""
local image, label, emoji = JobThumbs.forJob({ business = "pizzeria" })
check("an empty image id: no image, the name and the emoji (the fallback banner)", image == nil and label == "Luigi's Pizza" and emoji == "🍕")
JobThumbs.Images.pizzeria = "rbxassetid://123456"
local uploaded = JobThumbs.forJob({ special = "pizzarush" })
check("an uploaded image: its id, for every job that shares it", uploaded == "rbxassetid://123456" and JobThumbs.forJob({ business = "pizzeria" }) == "rbxassetid://123456")
JobThumbs.Images.pizzeria = ""
check("empty again: nil", JobThumbs.forJob({ business = "pizzeria" }) == nil)
JobThumbs.Images.pizzeria = saved
local filled = 0
for _, id in JobThumbs.Images do
	if string.match(id, "^rbxassetid://%d+$") then
		filled += 1
	end
end
check("the owner's 25 pictures are uploaded (6.12.11)", filled == 25, filled)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
