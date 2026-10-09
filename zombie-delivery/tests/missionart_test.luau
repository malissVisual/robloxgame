-- Logic test of 6.12.13, the mission chapters' pictures (shared/MissionArt.luau): every chapter of
-- shared/Missions.luau has an image slot (empty until Codex's art is uploaded, else an rbxassetid), the fallbacks name
-- existing job pictures (shared/JobThumbs.luau) of the client's own place, and forCampaign picks the chapter's own
-- picture, else the fallback's uploaded one, else none (the window then looks as before).
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Missions = require("./Missions")
local JobThumbs = require("./JobThumbs")
local MissionArt = require("./MissionArt")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Every chapter has a slot ----------------------------------------------------------------------

local campaigns: { [string]: boolean } = {}
local noSlot: { string } = {}
for _, campaign in Missions.Campaigns do
	campaigns[campaign.id] = true
	if type(MissionArt.Images[campaign.id]) ~= "string" then
		table.insert(noSlot, campaign.id)
	end
end
check("every chapter has an image slot", #Missions.Campaigns == 11 and #noSlot == 0, table.concat(noSlot, ", "))
local stale: { string } = {}
local badIds: { string } = {}
for id, image in MissionArt.Images do
	if not campaigns[id] then
		table.insert(stale, id)
	end
	if image ~= "" and not string.match(image, "^rbxassetid://%d+$") then
		table.insert(badIds, `{id}: {image}`)
	end
end
check("no slot for a chapter Missions no longer has", #stale == 0, table.concat(stale, ", "))
check("a slot is empty or an rbxassetid://", #badIds == 0, table.concat(badIds, ", "))

-- The fallbacks ---------------------------------------------------------------------------------

-- The client's place (shared/Cast.luau) against the business picture's name: the same place. The lab's picture is
-- the "Research Lab" (the map and the Cast call it the Biotech Lab: JobThumbs and Codex's README say so).
local SAME_PLACE: { [string]: string } = { ["Research Lab"] = "Biotech Lab" }
local wrong: { string } = {}
local count = 0
for id, asset in MissionArt.Fallback do
	count += 1
	local picture = JobThumbs.Assets[asset]
	local client = Missions.clientOf(id)
	if not campaigns[id] then
		table.insert(wrong, `{id}: no such chapter`)
	elseif not picture or JobThumbs.Images[asset] == nil then
		table.insert(wrong, `{id}: {asset} is no JobThumbs picture`)
	elseif not client or (SAME_PLACE[picture.name] or picture.name) ~= client.place then
		table.insert(wrong, `{id}: {picture.name} is not {if client then client.place else "?"}`)
	end
end
check("every fallback names an existing job picture of the client's own place", count > 0 and #wrong == 0, table.concat(wrong, "; "))
local expected = { clinic = "clinic", market = "supermarket", army = "army", ranch = "ranch", lab = "lab", underworld = "pawnshop" }
local differs: { string } = {}
for id, asset in expected do
	if MissionArt.Fallback[id] ~= asset then
		table.insert(differs, `{id}: {MissionArt.Fallback[id] or "none"}`)
	end
end
check("the six places with a business picture: clinic, FreshMart, the base, the ranch, the lab, Vinnie's pawnshop", count == 6 and #differs == 0, table.concat(differs, ", "))
check("Dirty Money is Vinnie's: his place is Second Life Pawn, the pitch says so", (Missions.clientOf("underworld") :: any).place == "Second Life Pawn"
	and string.find((Missions.findCampaign("underworld") :: any).pitch, "Second Life Pawn", 1, true) ~= nil)
check("no business picture for Dead End Dispatch, the twins, Fire Station 9, the Power Plant, City Hall",
	not MissionArt.Fallback.dispatch and not MissionArt.Fallback.duo and not MissionArt.Fallback.firehouse and not MissionArt.Fallback.power and not MissionArt.Fallback.exodus)

-- forCampaign ----------------------------------------------------------------------------------

local savedOwn = table.clone(MissionArt.Images)
local savedJobs = table.clone(JobThumbs.Images)
for id in MissionArt.Images do
	MissionArt.Images[id] = ""
end
JobThumbs.Images.clinic = "rbxassetid://1001"
local image, source = MissionArt.forCampaign("clinic")
check("no picture of its own: the fallback's uploaded job picture (Code Red: the City Clinic)", image == "rbxassetid://1001" and source == "clinic")
check("… FreshMart for Empty Shelves, the pawnshop for Dirty Money", MissionArt.forCampaign("market") == JobThumbs.Images.supermarket and MissionArt.forCampaign("underworld") == JobThumbs.Images.pawnshop)
check("no picture and no fallback: nil (First Shift, Last Convoy, an unknown id)", MissionArt.forCampaign("dispatch") == nil and MissionArt.forCampaign("exodus") == nil and MissionArt.forCampaign("nope") == nil)
JobThumbs.Images.clinic = ""
check("the fallback's picture not uploaded: nil", MissionArt.forCampaign("clinic") == nil)
MissionArt.Images.clinic = "rbxassetid://2002"
image, source = MissionArt.forCampaign("clinic")
check("the chapter's own picture wins", image == "rbxassetid://2002" and source == "chapter")
MissionArt.Images.dispatch = "rbxassetid://3003"
check("… and gives a chapter without a fallback its banner", MissionArt.forCampaign("dispatch") == "rbxassetid://3003")
for id, value in savedOwn do
	MissionArt.Images[id] = value
end
for id, value in savedJobs do
	JobThumbs.Images[id] = value
end
local shown = 0
for _, campaign in Missions.Campaigns do
	if MissionArt.forCampaign(campaign.id) then
		shown += 1
	end
end
check("with the uploaded job pictures, at least the six fallback chapters show a picture", shown >= 6, shown)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
