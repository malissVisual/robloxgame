--!strict
-- 6.12.13: the mission chapters' pictures (the owner: "make pictures for the missions too"): which picture opens a
-- chapter in the MISSIONS window (client/MissionArtUi.luau draws the banner, client/MissionsUi.luau places it).
-- Pure data, no Roblox: tests/missionart_test.luau and tools/mission-art/fill-ids.py read it.
--
--   * MissionArt.Images[campaignId]: the chapter's own picture ("rbxassetid://…"), "" until Codex draws it and the
--     owner uploads it (design/mission-art/BRIEF.md: art/mission-art/<campaignId>.png and its manifest.json;
--     tools/mission-art/fill-ids.py fills the ids). One slot per shared/Missions.luau chapter, in Missions.Campaigns'
--     order.
--   * MissionArt.Fallback[campaignId]: meanwhile, a business picture of the job list (a shared/JobThumbs.luau asset
--     id) where the client's place really is that business: Doctor Ellie's City Clinic, Raj's FreshMart, Captain
--     Maria's Military Base, Walt's Silver Spur Ranch, Doctor Hiro's Biotech Lab (the "Research Lab" picture) and
--     Vinnie's Second Life Pawn (the chapter's pitch and the Cast put Vinnie there; the bank is only where two of its
--     missions go). Dead End Dispatch, the twins' Survivor Camp, Fire Station 9, the Power Plant and City Hall have no
--     business picture: they wait for their own.
--   * MissionArt.forCampaign(id) -> (image?, source?): the chapter's own image, else its fallback's uploaded image,
--     else nil (no banner: the chapter looks as it did before 6.12.13). `source` says which: "chapter" or the
--     JobThumbs asset id.
-- A picture is descriptive: it grants nothing.

local JobThumbs = require(script.Parent.JobThumbs)

local MissionArt = {}

-- The chapters' own pictures by campaign id (the manifest's `robloxImage`; "" = not drawn or not uploaded yet).
MissionArt.Images = {
	dispatch = "",
	clinic = "",
	market = "",
	duo = "",
	firehouse = "",
	army = "",
	power = "",
	ranch = "",
	lab = "",
	underworld = "",
	exodus = "",
} :: { [string]: string }

-- Until a chapter has its own: the job list's picture of the client's place (JobThumbs asset id), where it matches.
MissionArt.Fallback = {
	clinic = "clinic", -- Doctor Ellie, City Clinic
	market = "supermarket", -- Raj, FreshMart
	army = "army", -- Captain Maria, the Military Base
	ranch = "ranch", -- Walt, Silver Spur Ranch
	lab = "lab", -- Doctor Hiro, the Biotech Lab (JobThumbs' "Research Lab")
	underworld = "pawnshop", -- Vinnie, Second Life Pawn
} :: { [string]: string }

local function filled(image: string?): string?
	return if type(image) == "string" and image ~= "" then image else nil
end

-- The picture that opens a chapter (see the header): its own, else its fallback's, else nil.
function MissionArt.forCampaign(id: string): (string?, string?)
	local own = filled(MissionArt.Images[id])
	if own then
		return own, "chapter"
	end
	local asset = MissionArt.Fallback[id]
	local image = if asset then filled(JobThumbs.Images[asset]) else nil
	if image then
		return image, asset
	end
	return nil, nil
end

return MissionArt
