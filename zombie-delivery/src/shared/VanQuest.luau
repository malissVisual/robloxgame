--!strict
-- 5.0 – 6.x, Earl's van (Config.VanQuest): the first vehicle was bought second-hand. At level 4 Marge texted you about
-- a guy out west, and Earl sold his rusty Old Van at Earl's Used Wheels (Map.VanSeller, far out on the West Highway).
-- 7.x (one car, Config.CompanyVan): retired. Every courier owns the ZDC Van from the start, so Earl sells nothing any
-- more: his lot (server/World.luau builds it and names its plate and his prompt with the words below) keeps his old van
-- for show with a SOLD tag (server/VanQuest.luau), and talking to him gets one of his lines. Pure Luau
-- (tests/vanquest_test.luau).
--
--   VanQuest.priceText()   what follows "FOR SALE" on his lot's plate ("· SOLD")
--   VanQuest.promptText()  his prompt's action ("Talk")
--   VanQuest.line(n)       his n-th line (they go round: Config.VanQuest.Lines)
--   VanQuest.tag()         the tag over his old van

local Config = require(script.Parent.Config)

local VanQuest = {}

function VanQuest.priceText(): string
	return Config.VanQuest.Sign
end

function VanQuest.promptText(): string
	return Config.VanQuest.Prompt
end

function VanQuest.line(n: number): string
	local lines = Config.VanQuest.Lines
	if #lines == 0 then
		return ""
	end
	return lines[(math.floor(n) - 1) % #lines + 1]
end

function VanQuest.tag(): string
	return Config.VanQuest.Tag
end

return VanQuest
