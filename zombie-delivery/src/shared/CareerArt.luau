--!strict
-- 6.23: the career's pictures (Codex's codex/career-thumbnails, its scenes in art/career-thumbnails/): the picture of
-- what a level opens, for the CAREER window's NEXT LEVEL hero (client/CareerUi.luau), the phone's CAREER
-- (client/PhoneMore.luau) and the ESTATE window's rows (client/EstateUi.luau). Pure data, no Roblox:
-- tests/careerart_test.luau and tools/career-thumbnails/check.py read it.
--
--   * CareerArt.Images["kind:id"]: a career picture ("rbxassetid://…"), "" until the owner uploads it
--     (tools/career-thumbnails/fill-ids.py fills it and the manifest). The job board's danger tiers (tier:1 … tier:4,
--     Config.Jobs.Tiers), the garages (garage:<id>) and the homes and offices (estate:<id>, Config.Estate.Properties):
--     the same keys in the same order as art/career-thumbnails/manifest.json `assets` (check.py checks it).
--   * CareerArt.forUnlock(unlock) -> Picture?: a shared/Career.luau unlock's picture: its own (above); a special job
--     its business's job picture (shared/JobThumbs.luau, uploaded already: Codex's career set had the same pictures);
--     a story chapter its MISSIONS picture (shared/MissionArt.luau: its own or a borrowed one); a bag, a vest, the bat
--     or a gun its 3D model (`model`, a shared/ItemLooks.luau key: client/ItemModel.luau draws it); nil for none (a
--     car, a bike, a stage, gear, the on-foot runs: their names and icons as before).
--   * CareerArt.headline(unlocks) -> Picture?: a level's one picture (the UI kit's hero shows one): the first of its
--     unlocks, in the road's order, with an image; else the first with a model; else nil (the caller's emoji or glyph).
--   * CareerArt.propertyKey(def) / CareerArt.image(key): a property's key ("garage:garage_rented", "estate:elm") and
--     an uploaded image (nil while "").
-- Not taken from Codex's set: its vehicle, bike, gear, gun and car-gun renders (the 3D models since 6.12 / 6.19 differ,
-- the inventory's live models since 6.22), the old kit (replaced in 6.6), the rewards' pictures (the CAREER window
-- shows a reward as its words and money) and its chapter scenes (one picture a chapter: MissionArt's). A picture is
-- descriptive: it grants nothing.

local JobThumbs = require(script.Parent.JobThumbs)
local MissionArt = require(script.Parent.MissionArt)

local CareerArt = {}

-- What a CardKit picture takes from here (the caller adds its emoji or glyph).
export type Picture = { image: string?, model: string? }
export type Unlock = { kind: string, id: string, name: string?, car: string? }

-- The uploaded career pictures by key (the manifest's `robloxImage`; "" = not uploaded: the fallback shows).
CareerArt.Images = {
	["tier:1"] = "",
	["tier:2"] = "",
	["tier:3"] = "",
	["tier:4"] = "",
	["garage:garage_rented"] = "",
	["garage:garage_south"] = "",
	["garage:garage_harbor"] = "",
	["garage:garage_north"] = "",
	["garage:garage_downtown"] = "",
	["estate:elm"] = "",
	["estate:birch"] = "",
	["estate:oak"] = "",
	["estate:maple"] = "",
	["estate:sunset"] = "",
	["estate:lakeside"] = "",
	["estate:office_harbor"] = "",
	["estate:pinecrest"] = "",
	["estate:oceanview"] = "",
	["estate:office_tower"] = "",
	["estate:hilltop"] = "",
	["estate:office_penthouse"] = "",
} :: { [string]: string }

-- The unlock kinds drawn as their 3D model (shared/ItemLooks.luau's "kit:<id>" and "gun:<id>").
local MODEL_KINDS: { [string]: boolean } = { kit = true, gun = true }

local function filled(image: string?): string?
	return if type(image) == "string" and image ~= "" then image else nil
end

-- An uploaded career picture, nil while its slot is empty (or for a key without one).
function CareerArt.image(key: string): string?
	return filled(CareerArt.Images[key])
end

-- A property's key (Config.Estate.Properties: a garage, else a home or an office; shared/Career.luau's unlock kinds).
function CareerArt.propertyKey(def: { id: string, kind: string }): string
	return `{if def.kind == "garage" then "garage" else "estate"}:{def.id}`
end

-- An unlock's picture (see the header), nil for none.
function CareerArt.forUnlock(unlock: Unlock): Picture?
	local key = `{unlock.kind}:{unlock.id}`
	local own = CareerArt.image(key)
	if own then
		return { image = own }
	end
	if unlock.kind == "job" then
		local asset = JobThumbs.Special[unlock.id]
		local image = if asset then filled(JobThumbs.Images[asset]) else nil
		return if image then { image = image } else nil
	elseif unlock.kind == "campaign" then
		local image = MissionArt.forCampaign(unlock.id)
		return if image then { image = image } else nil
	elseif MODEL_KINDS[unlock.kind] then
		return { model = key }
	end
	return nil
end

-- A level's one picture (see the header).
function CareerArt.headline(unlocks: { Unlock }): Picture?
	local model: Picture? = nil
	for _, unlock in unlocks do
		local picture = CareerArt.forUnlock(unlock)
		if picture and picture.image then
			return picture
		elseif picture and not model then
			model = picture
		end
	end
	return model
end

return CareerArt
