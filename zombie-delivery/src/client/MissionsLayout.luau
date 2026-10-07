--!strict
-- 6.8, the MISSIONS window's measures (client/MissionsUi.luau) for a screen: pure numbers, no Roblox, so
-- tests/missions_layout_test.luau checks them for a 1280 × 720 monitor and an iPhone SE held sideways.
--
--   MissionsLayout.fit(x, y) -> Layout
--       x, y: the ScreenGui's area in pixels (under Roblox's top bar). The window is designed at Design (1000 × 640)
--       and scaled to the screen, never under MinScale (the text stays readable on a phone: a smaller screen gets a
--       smaller window at that scale instead). A window narrower than NarrowWidth or lower than NarrowHeight at its
--       scale is `narrow`: the clients become a strip of cards on top, the chapter fills the rest, the window's chrome
--       slims down and the text grows a step.

local MissionsLayout = {}

MissionsLayout.Design = { width = 1000, height = 640 }
MissionsLayout.MinScale = 0.72
MissionsLayout.MaxScale = 1.1
MissionsLayout.NarrowWidth = 860
MissionsLayout.NarrowHeight = 540
MissionsLayout.Margin = 16 -- px left free around the window

export type Layout = {
	scale: number, -- the UIScale
	width: number, -- the window at scale 1 (its UIScale makes it fit)
	height: number,
	narrow: boolean, -- the clients on top (a strip), the chapter under them
	header: number, -- the window's chrome (Ui.window header / footer heights)
	footer: number,
	tabs: number, -- the page tabs' row
	listW: number, -- wide: the clients' column
	stripH: number, -- narrow: the clients' strip
	cardW: number, -- a client card (wide: the column's width)
	cardH: number,
	cardPortrait: number, -- the card's portrait (square)
	heroW: number, -- the chosen client's big portrait
	heroH: number,
	text: number, -- the body text
	small: number, -- the smallest text (caps, chips)
	title: number, -- the client's name
	step: number, -- a story path row
	start: number, -- the START button's height
}

function MissionsLayout.fit(x: number, y: number): Layout
	local design = MissionsLayout.Design
	local margin = MissionsLayout.Margin
	local scale = math.clamp(math.min(x / (design.width + 40), y / (design.height + 40)), MissionsLayout.MinScale, MissionsLayout.MaxScale)
	local width = math.floor(math.min(design.width, math.max(320, (x - margin) / scale)))
	local height = math.floor(math.min(design.height, math.max(240, (y - margin) / scale)))
	local narrow = width < MissionsLayout.NarrowWidth or height < MissionsLayout.NarrowHeight
	if narrow then
		return {
			scale = scale,
			width = width,
			height = height,
			narrow = true,
			header = 52,
			footer = 30,
			tabs = 40,
			listW = 0,
			stripH = 100,
			cardW = 196,
			cardH = 86,
			cardPortrait = 60,
			heroW = 104,
			heroH = 118,
			text = 16,
			small = 13,
			title = 26,
			step = 66,
			start = 52,
		}
	end
	return {
		scale = scale,
		width = width,
		height = height,
		narrow = false,
		header = 78,
		footer = 40,
		tabs = 46,
		listW = 300,
		stripH = 0,
		cardW = 300,
		cardH = 84,
		cardPortrait = 64,
		heroW = 168,
		heroH = 188,
		text = 15,
		small = 12,
		title = 32,
		step = 64,
		start = 52,
	}
end

-- The room the page has under the chrome and the tabs (wide: the column's and the chapter's height; narrow: the
-- strip's and the chapter's).
function MissionsLayout.pageHeight(layout: Layout): number
	return layout.height - layout.header - layout.footer - layout.tabs
end

return MissionsLayout
