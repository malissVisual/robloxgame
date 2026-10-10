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
--   MissionsLayout.parts(layout) -> Parts
--       6.8 review: where the page's parts sit, top to bottom, in the window's content area (under its header, above
--       its footer): the chapter's scrolling list, and under it the action bar (the pay line and START) that never
--       scrolls away (START sat under the fold at 1280 × 720 and two screens down on a phone).
--   6.12.13, the chapter's picture banner (client/MissionArtUi.luau, shared/MissionArt.luau): ArtRatio (width :
--       height) of the chapter's width, never taller than the layout's `art`, so it always fits the chapter's view
--       above the action bar. Wide, it opens the chapter (`artOnTop`); narrow (a phone), the chapter's view is about
--       150 px tall, so the hero and the action card stay first and the banner, a wider crop, sits above the story
--       path. A chapter without a picture has no banner at all.
--   6.18 (the UI kit, client/CardKit.luau; design/ui-kit/README.md): the chapter is the kit's hero (the next mission:
--       the chapter's picture, the name, the zombies, the reward big, START / GET READY) beside the missions' rows (a
--       chapter CardLayout.side wide; else the hero on top), so START lives in the hero and the action bar is gone:
--       `bar` is 0 and the chapter fills the room down to the window's footer (MissionsLayout.parts; barTop is where
--       it ends). The client cards are the kit's compact rows (cardH 64, the strip's 62 on a phone), and the picture
--       banner opens the chapter's details (ⓘ). MissionsLayout.heroRoom(layout): the room the hero has in the
--       chapter's view (its height less the list's padding), so START is in view without scrolling.

local MissionsLayout = {}

MissionsLayout.Design = { width = 1000, height = 640 }
MissionsLayout.MinScale = 0.72
MissionsLayout.MaxScale = 1.1
MissionsLayout.NarrowWidth = 860
MissionsLayout.NarrowHeight = 540
MissionsLayout.Margin = 16 -- px left free around the window
MissionsLayout.Gap = 6 -- 6.8 review: between the clients' strip and the chapter
MissionsLayout.ListPad = 13 -- 6.18: the chapter list's padding (5 on top, 8 under): the hero's room is the rest
MissionsLayout.Bottom = 4 -- 6.8 review: under the chapter, above the window's footer
MissionsLayout.ArtRatio = 2.6 -- 6.12.13: the chapter's picture banner, width : height (capped by Layout.art)

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
	bar: number, -- 6.8 review: the action bar under the chapter (6.18: 0, START is the hero's)
	art: number, -- 6.12.13: the chapter's picture banner at its tallest (px; else ArtRatio of the chapter's width)
	artOnTop: boolean, -- 6.12.13: the banner opens the chapter (wide), else it sits above the story path (narrow)
}

export type Parts = {
	contentH: number, -- the window's content area (between its header and its footer)
	chapterTop: number, -- the chapter's scrolling list
	chapterH: number,
	barTop: number, -- where the chapter ends (6.18: no action bar under it)
	barH: number,
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
			stripH = 66, -- (6.18: the kit's compact client cards)
			cardW = 188,
			cardH = 62,
			cardPortrait = 50,
			heroW = 72, -- (6.8 review: 104 × 118 before; the chapter's room is short on a phone)
			heroH = 80,
			text = 16,
			small = 13,
			title = 26,
			step = 66,
			start = 52,
			bar = 0, -- (6.18: START is the hero's)
			art = 132, -- (the chapter's view is ~150 px: a wider crop that fits it)
			artOnTop = false,
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
		cardH = 64,
		cardPortrait = 52,
		heroW = 168,
		heroH = 188,
		text = 15,
		small = 12,
		title = 32,
		step = 64,
		start = 52,
		bar = 0,
		art = 260, -- (the chapter's 661 px at 2.6 : 1 is 254)
		artOnTop = true,
	}
end

-- The room the page has under the chrome and the tabs (wide: the column's and the chapter's height; narrow: the
-- strip's and the chapter's).
function MissionsLayout.pageHeight(layout: Layout): number
	return layout.height - layout.header - layout.footer - layout.tabs
end

-- 6.8 review: the chapter (and 6.8's action bar under it, 0 tall since 6.18; see the header). Wide, the chapter starts
-- under the tabs; narrow, under the clients' strip. It fills the room down to the content's bottom.
function MissionsLayout.parts(layout: Layout): Parts
	local gap = MissionsLayout.Gap
	local contentH = layout.height - layout.header - layout.footer
	local chapterTop = layout.tabs + (if layout.narrow then layout.stripH + gap else 0)
	local barTop = contentH - MissionsLayout.Bottom - layout.bar
	return {
		contentH = contentH,
		chapterTop = chapterTop,
		chapterH = barTop - gap - chapterTop,
		barTop = barTop,
		barH = layout.bar,
	}
end

-- 6.18: the room the chapter's hero has in the chapter's view (without scrolling): its height less the list's padding.
function MissionsLayout.heroRoom(layout: Layout): number
	return MissionsLayout.parts(layout).chapterH - MissionsLayout.ListPad
end

return MissionsLayout
