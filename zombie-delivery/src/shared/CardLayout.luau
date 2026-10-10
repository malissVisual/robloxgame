--!strict
-- 6.18, the UI kit's pure layout maths (the owner: "I need it unified so the phone looks like that [JOBS], and the
-- other popups too"). client/CardKit.luau draws the cards; this module only measures, so tests/cardlayout_test.luau
-- can check it without Roblox. The sizes are Config.UiKit's.
--   CardLayout.side(width)                       is a body this wide split: the hero on the left, the rows right?
--   CardLayout.columns(width)                    the hero's and the rows' widths (px; side by side or both whole)
--   CardLayout.heroHeight(room)                  a popup's hero: the popup's room, between HeroMin and HeroMax
--   CardLayout.valueSize(height)                 the hero's big value (PayBig on a tall hero, else PayMid)
--   CardLayout.stack(lines, gap)                 the height of lines in a list with gaps between them
--   CardLayout.heroInfo(value, facts, bar, button) the hero's words at its foot (head, value, facts, bar, button)
--   CardLayout.homeHero(view, above, below)      the phone home's hero: what the view leaves over the header and one
--                                                row, between HomeHeroMin and HomeHeroMax
--   CardLayout.hasButton(height)                 does a hero this tall carry its big button (else it is the button)
--   CardLayout.action(lockWidth)                 the round action's width (a lock's words widen it)
--   CardLayout.rowText(thumb, tag, action, value) a row's name column: its x and the width it leaves (UDim offset)

local Config = require(script.Parent.Config)

local KIT = Config.UiKit
local CardLayout = {}

CardLayout.HEAD = 16 -- the hero's head line (its title and tag)
CardLayout.FACTS = 18 -- the hero's facts line
CardLayout.BAR = 4 -- the hero's bar (a goal's progress)
CardLayout.LIST_GAP = 4 -- the gap between the hero's lines
CardLayout.EDGE = 14 -- the hero's words from its foot
CardLayout.SHADE = 28 -- the shade's extra height over the words

function CardLayout.side(width: number): boolean
	return width >= KIT.SplitMin
end

function CardLayout.columns(width: number): (number, number)
	if CardLayout.side(width) then
		local hero = math.floor(width * KIT.HeroShare) - 5
		return hero, width - hero - 10
	end
	return width, width
end

function CardLayout.heroHeight(room: number): number
	return math.clamp(math.floor(room), KIT.HeroMin, KIT.HeroMax)
end

function CardLayout.valueSize(height: number): number
	return if height >= KIT.PayTall then KIT.PayBig else KIT.PayMid
end

function CardLayout.stack(lines: { number }, gap: number): number
	local total = 0
	for _, line in lines do
		total += line
	end
	return total + gap * math.max(0, #lines - 1)
end

-- The hero's lines at its foot, top to bottom: the head, the value (+2 px), the facts, a bar, a 4 px gap and the button
-- (`button` its height, 0 none). JOBS: the head, the pay, the facts, the gap, the 44 px button.
function CardLayout.heroInfo(value: number, facts: boolean, bar: boolean, button: number): ({ number }, number)
	local lines = { CardLayout.HEAD, value + 2 }
	if facts then
		table.insert(lines, CardLayout.FACTS)
	end
	if bar then
		table.insert(lines, CardLayout.BAR)
	end
	if button > 0 then
		table.insert(lines, 4)
		table.insert(lines, button)
	end
	return lines, CardLayout.stack(lines, CardLayout.LIST_GAP)
end

function CardLayout.homeHero(view: number, above: number, below: number): number
	return math.clamp(math.floor(view - above - below), KIT.HomeHeroMin, KIT.HomeHeroMax)
end

function CardLayout.hasButton(height: number): boolean
	return height >= KIT.ButtonHeroMin
end

function CardLayout.action(lockWidth: number?): number
	return if lockWidth then math.max(KIT.Add, lockWidth + 14) else KIT.Add
end

-- A row's name column: from the thumb (+10 px) and the tag (danger stars, `tag` px), to the value and the action
-- (each with its gaps). Returns its x and its width as a UDim offset (negative: the row's width less the rest).
function CardLayout.rowText(thumb: number, tag: number, action: number, value: number): (number, number)
	local x = thumb + 10 + tag
	return x, -(x + action + value + 24)
end

return CardLayout
