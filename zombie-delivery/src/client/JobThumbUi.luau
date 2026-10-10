--!strict
-- 6.12.11: the job pictures on the job lists (the owner: show Codex's business pictures in the job list). The
-- picture of a job is shared/JobThumbs.luau's (the business it is for, the special's workplace, the round's, the
-- tutorial's); this draws it, only in the rows a list draws (the phone's BOARD, client/PhoneApps.luau; J's board,
-- client/DispatchUi.luau):
--   JobThumbUi.strip(parent, info, order, height?)   the picture strip across the top of a job card: the business's
--       picture (ScaleType Crop: the 16 : 9 picture cropped to about RATIO : 1, its sign kept) with the business's name
--       on a dark label over its bottom-left corner. `height` nil: the card's width / RATIO (kept as the card resizes,
--       whatever UIScale the window has), else that many px. While the picture's id is empty (not uploaded yet) a slim
--       banner instead (BANNER px): the cargo emoji and the business's name on a dark tile. Nil, nothing drawn, for a
--       job without a picture (a mission, an older server's row).
--   JobThumbUi.square(parent, info, size, props?)     a small square of the picture (cropped) for a NEXT UP row; nil
--       while its id is empty or for a job without one (the row stays as it was).
--   JobThumbUi.keepRatio(frame, ratio, most?)          keeps a picture frame's height at its width / ratio (6.12.13:
--       never over `most` px; the MISSIONS window's chapter banner, client/MissionArtUi.luau, uses it too).
--   JobThumbUi.preload()                               6.16.1 (the owner: "the pictures in JOBS load slowly"): Roblox
--       fetches an image the first time it is drawn, so the job list waited on 25 downloads; every uploaded job and
--       chapter picture is fetched in the background PRELOAD_AFTER s after joining (ContentProvider), and a picture
--       still on its way fades in when it is there instead of popping.
-- Presentation only: a picture grants nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JobThumbs = require(Shared.JobThumbs)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local K = Theme.Contract
local JobThumbUi = {}

JobThumbUi.RATIO = 2.4 -- the strip's width : height
JobThumbUi.BANNER = 26 -- the fallback banner's height (px)
JobThumbUi.GUESS = 128 -- the strip's height until its card's width is known (a phone card ~300 px wide)
JobThumbUi.PRELOAD_AFTER = 4 -- 6.16.1: seconds after joining before the pictures are fetched (the world first)
JobThumbUi.FADE = 0.25 -- 6.16.1: seconds a picture that was still loading fades in

-- 6.16.1: a picture still on its way is drawn invisible and fades in once Roblox has it (one already fetched at once).
local function fadeIn(label: ImageLabel)
	if label.IsLoaded then
		return
	end
	label.ImageTransparency = 1
	local watch: RBXScriptConnection? = nil
	watch = label:GetPropertyChangedSignal("IsLoaded"):Connect(function()
		if label.IsLoaded then
			if watch then
				watch:Disconnect()
			end
			TweenService:Create(label, TweenInfo.new(JobThumbUi.FADE), { ImageTransparency = 0 }):Play()
		end
	end)
end

-- 6.16.1: fetches every uploaded job picture and mission chapter picture in the background (see the header).
function JobThumbUi.preload()
	task.delay(JobThumbUi.PRELOAD_AFTER, function()
		local ids: { any } = {}
		for _, id in JobThumbs.Images do
			if id ~= "" then
				table.insert(ids, id)
			end
		end
		local ok, MissionArt = pcall(require, Shared:FindFirstChild("MissionArt") :: ModuleScript)
		if ok and type(MissionArt) == "table" and type(MissionArt.Images) == "table" then
			for _, id in MissionArt.Images do
				if type(id) == "string" and id ~= "" then
					table.insert(ids, id)
				end
			end
		end
		if #ids > 0 then
			local fetched, err = pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(ids) -- (asked here: the phone recorder's mock has no ContentProvider)
			end)
			if not fetched then
				warn(`[JobThumbUi] preload: {err}`)
			end
		end
	end)
end

-- Keeps `frame`'s height at its width / ratio (never over `most` px when given). Its height is pure offset, so
-- AbsoluteSize.Y / Size.Y.Offset is the scale of every UIScale above it (the phone's popup, J's window, the MISSIONS
-- window): the width in the frame's own px is X / that.
function JobThumbUi.keepRatio(frame: GuiObject, ratio: number, most: number?)
	local function fit()
		local size = frame.AbsoluteSize
		local offset = frame.Size.Y.Offset
		if size.X <= 0 or size.Y <= 0 or offset <= 0 then
			return
		end
		local want = math.max(24, math.floor(size.X * offset / size.Y / ratio + 0.5))
		if most then
			want = math.min(want, math.max(24, most))
		end
		if math.abs(want - offset) >= 1 then
			frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, want)
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

-- The picture strip (or the fallback banner) at `order` in a list (its position, when the parent has no layout,
-- is the caller's). See the header.
function JobThumbUi.strip(parent: Instance, info: any, order: number, height: number?): any
	local image, name, emoji = JobThumbs.forJob(info)
	if not name then
		return nil
	end
	local title = string.upper(name)
	if not image then
		local banner = Ui.make("Frame", {
			Name = "ThumbBanner",
			Size = UDim2.new(1, 0, 0, JobThumbUi.BANNER),
			BackgroundColor3 = K.charcoal,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, parent)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.82 }, banner)
		Ui.label(banner, emoji or "📦", UDim2.new(0, 28, 1, 0), {
			Name = "Emoji",
			Font = Theme.Font,
			TextSize = 14,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.label(banner, title, UDim2.new(1, -36, 1, 0), {
			Name = "Business",
			Position = UDim2.fromOffset(28, 0),
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = K.text,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		return banner
	end
	local strip = Ui.make("Frame", {
		Name = "Thumb",
		Size = UDim2.new(1, 0, 0, height or JobThumbUi.GUESS),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = order,
	}, parent)
	fadeIn(Ui.make("ImageLabel", {
		Name = "Picture",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		ScaleType = Enum.ScaleType.Crop,
	}, strip) :: ImageLabel)
	local tag = Ui.label(strip, title, UDim2.fromOffset(0, 22), {
		Name = "Business",
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.1,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.text,
		TextWrapped = false,
		ZIndex = 2,
	})
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tag)
	if not height then
		JobThumbUi.keepRatio(strip, JobThumbUi.RATIO)
	end
	return strip
end

-- A small square of the picture (cropped), or nil (no picture uploaded / none for this job). See the header.
function JobThumbUi.square(parent: Instance, info: any, size: number, props: { [string]: any }?): any
	local image, name = JobThumbs.forJob(info)
	if not image then
		return nil
	end
	local made = Ui.make("ImageLabel", {
		Name = "ThumbSquare",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		Image = image,
		ScaleType = Enum.ScaleType.Crop,
	}, parent)
	made:SetAttribute("Business", name)
	fadeIn(made :: ImageLabel)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.8 }, made)
	if props then
		for key, value in props do
			made[key] = value
		end
	end
	return made
end

return JobThumbUi
