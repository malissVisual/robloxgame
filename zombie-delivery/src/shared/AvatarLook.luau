--!strict
-- 6.9, one body for every courier (the owner: "everybody the same figure, the look stays the player's"): each player's
-- own Roblox avatar worn on Roblox's classic blocky R15 body. server/CourierAvatar.luau loads the player's
-- HumanoidDescription, sets the Body fields below on it and puts it on with Humanoid:ApplyDescriptionAsync:
--   - reset: the torso, the arms and the legs (Roblox's default blocky parts), the proportions (the classic ones) and
--     the avatar's own animations (every courier walks with the game's: shared/CourierMotion.luau);
--   - kept (Kept): the head with its face (a dynamic head too), the clothes (the shirt, the trousers, the t-shirt,
--     layered clothing), the skin colours, the hair, the hats and the other accessories.
-- server/Npcs.luau builds the people of the world on the same classic body. Pure data (tests/avatarlook_test.luau).
local AvatarLook = {}

-- A HumanoidDescription's fields and the values they get: Roblox's classic blocky R15 at its standard size.
AvatarLook.Body = {
	Torso = 0,
	LeftArm = 0,
	RightArm = 0,
	LeftLeg = 0,
	RightLeg = 0,
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0,
	ProportionScale = 0,
	IdleAnimation = 0,
	WalkAnimation = 0,
	RunAnimation = 0,
	JumpAnimation = 0,
	FallAnimation = 0,
	ClimbAnimation = 0,
	SwimAnimation = 0,
} :: { [string]: number }

-- The body parts reset to Roblox's defaults (the names of Enum.BodyPart; the head is the player's own).
AvatarLook.Parts = { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

-- What stays the player's (never in Body).
AvatarLook.Kept = {
	"Head", "Face", "Shirt", "Pants", "GraphicTShirt", "MoodAnimation",
	"HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor",
	"HatAccessory", "HairAccessory", "FaceAccessory", "NeckAccessory", "ShouldersAccessory", "FrontAccessory",
	"BackAccessory", "WaistAccessory",
}

-- The courier's workwear (RGB): the body every courier spawns in, worn until the player's own look is on, and for good
-- when it cannot load (a Studio test player, Roblox's avatar service down). Warm skin, a charcoal work jacket, dark
-- trousers (server/CharacterArt/Geometry.luau's courier colours).
AvatarLook.Workwear = {
	HeadColor = { 218, 166, 119 },
	LeftArmColor = { 218, 166, 119 },
	RightArmColor = { 218, 166, 119 },
	TorsoColor = { 40, 43, 47 },
	LeftLegColor = { 44, 48, 56 },
	RightLegColor = { 44, 48, 56 },
} :: { [string]: { number } }

return AvatarLook
