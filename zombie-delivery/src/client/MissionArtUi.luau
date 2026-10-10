--!strict
-- 6.12.13: the mission chapters' pictures in the MISSIONS window (the owner: "make pictures for the missions too").
-- A chapter's picture is shared/MissionArt.luau's (its own once Codex's art is uploaded, design/mission-art/BRIEF.md;
-- meanwhile the job list's picture of the client's place: the City Clinic, FreshMart, the Military Base ...). This
-- draws it in the chosen chapter's scrolling list (client/MissionsUi.luau Page.render places it):
--   MissionArtUi.banner(parent, campaign, order, layout, dim?)   the picture banner: the chapter's picture across the
--       list (ScaleType Crop, MissionsLayout.ArtRatio : 1 of the list's width, never taller than layout.art: on a phone
--       a wider crop that fits the chapter's view; client/JobThumbUi.luau keepRatio keeps it as the window resizes),
--       a dark gradient rising from its bottom, and in its bottom-left corner a dark label with a rule in the chapter's
--       colour: the chapter (its icon and name) over the client (the name and the place). `dim` (a shut chapter)
--       dims the picture like the portraits. Nil, nothing drawn, for a chapter without a picture: the window then
--       looks exactly as it did before 6.12.13.
--   6.18: MissionArtUi.picture(campaign)   the chapter's picture for the UI kit's hero (client/CardKit.luau Picture: the
--       picture, else the chapter's emoji as the hero's big faint mark). The banner now opens the chapter's details.
-- Presentation only: a picture grants nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Missions = require(Shared.Missions)
local MissionArt = require(Shared.MissionArt)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local JobThumbUi = require(script.Parent.JobThumbUi)
local MissionsLayout = require(script.Parent.MissionsLayout)

local K = Theme.Contract
local MissionArtUi = {}

MissionArtUi.DIM = 0.45 -- a shut chapter's picture (the portraits' ImageTransparency over the dark face)

-- The banner (see the header), or nil for a chapter without a picture.
function MissionArtUi.banner(parent: Instance, campaign: Missions.Campaign, order: number, layout: MissionsLayout.Layout, dim: boolean?): any
	local image, source = MissionArt.forCampaign(campaign.id)
	if not image then
		return nil
	end
	local rgb = campaign.color
	local color = Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
	local banner = Ui.make("Frame", {
		Name = "ChapterArt",
		Size = UDim2.new(1, -4, 0, layout.art),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = order,
	}, parent)
	banner:SetAttribute("Art", source)
	Ui.stroke(banner, K.line, 1).Transparency = Ui.HAIRLINE
	Ui.make("ImageLabel", {
		Name = "Picture",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		ImageTransparency = if dim then MissionArtUi.DIM else 0,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 1,
	}, banner)
	-- The dark gradient: clear over the top half, dark at the bottom where the label sits.
	local shade = Ui.make("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.recessed,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, banner)
	Ui.make("UIGradient", {
		Rotation = 90, -- (0 at the top, 1 at the bottom)
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.88),
			NumberSequenceKeypoint.new(1, 0.18),
		}),
	}, shade)
	-- The label: the chapter over the client, on a dark tile with the chapter's colour as a rule on its left.
	local titleSize = if layout.narrow then 20 else 26
	local subSize = layout.small + 1
	local label = Ui.make("Frame", {
		Name = "Label",
		Size = UDim2.fromOffset(0, titleSize + subSize + 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, banner)
	Ui.make("UIPadding", { PaddingRight = UDim.new(0, 14) }, label)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4 }, label)
	local words = Ui.make("Frame", {
		Name = "Words",
		Size = UDim2.fromOffset(0, titleSize + subSize + 10),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(15, 10),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, label)
	Ui.list(words, true, 2)
	Ui.label(words, `{campaign.icon}  {string.upper(campaign.name)}`, UDim2.fromOffset(0, titleSize + 4), {
		Name = "Chapter",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.DisplayFont,
		TextSize = titleSize,
		TextColor3 = K.text,
		TextWrapped = false,
		LayoutOrder = 1,
		ZIndex = 4,
	})
	local main = Missions.clientOf(campaign.id)
	local who = Missions.clientName(campaign.id)
	Ui.label(words, if main then `{who}  ·  {main.place}` else who, UDim2.fromOffset(0, subSize + 4), {
		Name = "Client",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = subSize,
		TextColor3 = color:Lerp(K.text, 0.35),
		TextWrapped = false,
		LayoutOrder = 2,
		ZIndex = 4,
	})
	JobThumbUi.keepRatio(banner, MissionsLayout.ArtRatio, layout.art)
	return banner
end

-- 6.18: the chapter's picture for the kit's hero (see the header).
function MissionArtUi.picture(campaign: Missions.Campaign): { image: string?, emoji: string? }
	local image = MissionArt.forCampaign(campaign.id)
	return { image = image, emoji = campaign.icon }
end

return MissionArtUi
