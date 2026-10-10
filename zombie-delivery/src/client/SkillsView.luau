--!strict
-- 6.20, CAREER's SKILLS tab (Config.Skills, shared/Skills.luau; design/skills/PROPOSAL.md) in the UI kit
-- (client/CardKit.luau; design/ui-kit/README.md). The phone's CAREER app (client/PhoneMore.luau) and the CAREER window
-- (client/CareerUi.luau) draw it under their ROAD / SKILLS tabs:
--   * the hero "SkillsHero": the free points big (gold while there are some), the level and the points spent on one
--     line, RESET · FREE the one button (grey while nothing is spent; the server refuses it during a job or a mission);
--   * a branch a section ("📦 COURIER · 4"), three columns side by side on a wide screen, stacked on a narrow one; a
--     skill a row ("Skill_<id>"): its icon, its name (an apex ★), the ranks as ■■□ big, its one line, and › or the
--     apex's lock "🔒 6" until its branch has Config.Skills.ApexNeeds points;
--   * a tap opens its details ("‹ SKILLS" back): what it gives now and with the next rank (the game's real numbers,
--     Skills.describe), its cost, and [+1 POINT] ("SkillBuy"; grey with the reason when it can't).
-- Presentation only: the Skills remote asks ("buy", id) / ("reset"); the server decides and sends the state again
-- (its `skills`), and the caller draws again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Skills)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local K = Theme.Contract
local KIT = Config.UiKit
local C = CardKit.Color
local SkillsView = {}

export type Ctx = {
	wide: boolean, -- three branch columns side by side
	level: number,
	skills: Rules.Ranks,
	heroHeight: number?,
	redraw: () -> (), -- the tab again (a sub-view opened or closed)
}

-- The skill whose details show (nil: the tree).
SkillsView.open = nil :: string?

-- The free points of these ranks at this level (the phone's dot, the tab's count).
function SkillsView.free(skills: Rules.Ranks?, level: number): number
	return Rules.free(skills, level)
end

-- "■■□": the ranks held of all.
local function squares(rank: number, ranks: number): string
	return string.rep("■", rank) .. string.rep("□", math.max(0, ranks - rank))
end

local function title(def: Config.SkillDef): string
	return (if def.apex then "★ " else "") .. string.upper(def.name)
end

local function ask(...: any)
	Net.get("Skills"):FireServer(...)
end

-- The hero: the free points, RESET · FREE.
local function hero(list: Instance, ctx: Ctx, order: number)
	local points = Rules.points(ctx.level)
	local spent = Rules.spent(ctx.skills)
	local free = Rules.free(ctx.skills, ctx.level)
	CardKit.hero(list, {
		name = "SkillsHero",
		order = order,
		height = ctx.heroHeight or 168,
		picture = { emoji = "⭐" },
		title = "SKILL POINTS",
		value = if free == 1 then "1 FREE POINT" else `{free} FREE POINTS`,
		valueColor = if free > 0 then C.gold else C.dim,
		facts = `Level {ctx.level} · {spent}/{points} spent · a point every level`,
		ribbon = { text = `LV {ctx.level} · {points} POINTS`, face = K.raised, ink = K.text },
		action = {
			name = "SkillsReset",
			text = "RESET · FREE",
			kind = if spent > 0 then "primary" else "shut",
			onClick = function()
				if spent > 0 then
					ask("reset")
				end
			end,
		},
		onOpen = function() end,
		silent = true,
	})
end

-- One skill's row.
local function skillRow(parent: Instance, def: Config.SkillDef, branch: Config.SkillBranch, ctx: Ctx, order: number)
	local rank = Rules.rank(ctx.skills, def.id)
	local lockedApex = def.apex == true and rank == 0 and Rules.spentIn(ctx.skills, branch.id) < Config.Skills.ApexNeeds
	local can = Rules.canBuy(ctx.skills, ctx.level, def.id)
	CardKit.row(parent, {
		name = `Skill_{def.id}`,
		order = order,
		accent = if rank >= def.ranks then K.good elseif rank > 0 then C.gold elseif can then K.warn else K.line,
		picture = { emoji = def.icon },
		thumb = KIT.Icon,
		emojiSize = 22,
		shut = lockedApex,
		title = title(def),
		titleColor = if rank > 0 then K.text else nil,
		facts = def.text,
		value = squares(rank, def.ranks),
		valueColor = if rank > 0 then C.gold else C.dim,
		action = if lockedApex then nil else "›",
		lock = if lockedApex then `🔒 {Config.Skills.ApexNeeds}` else nil,
		silent = true,
		onOpen = function()
			CardKit.click()
			SkillsView.open = def.id
			ctx.redraw()
		end,
	})
end

-- A branch: its header ("📦 COURIER · 4") and its rows, in `parent` (a vertical list).
local function branchColumn(parent: Instance, branch: Config.SkillBranch, ctx: Ctx)
	CardKit.sectionHeader(parent, { name = `Branch_{branch.id}`, text = `{branch.icon} {string.upper(branch.name)} · {Rules.spentIn(ctx.skills, branch.id)}`, order = 0 })
	for index, def in branch.skills do
		skillRow(parent, def, branch, ctx, index)
	end
end

-- The details of one skill: now, next, its cost and [+1 POINT].
local function details(list: Instance, def: Config.SkillDef, branch: Config.SkillBranch, ctx: Ctx, order: number): number
	local back = CardKit.chip(list, { name = "SkillsBack", text = "‹ SKILLS", order = order, onClick = function()
		SkillsView.open = nil
		ctx.redraw()
	end })
	back.Size = UDim2.fromOffset(back.Size.X.Offset + 8, KIT.Chip + 4)
	local rank = Rules.rank(ctx.skills, def.id)
	local ok, why = Rules.canBuy(ctx.skills, ctx.level, def.id)
	local full = rank >= def.ranks
	local nextLine = if full then "MAX RANK" else `NEXT: {Rules.describe(def, rank + 1)}`
	local button = if ok then `+1 POINT{if def.cost > 1 then ` · {def.cost} POINTS` else ""}`
		elseif why == `🔒 {Config.Skills.ApexNeeds}` then `🔒 {Config.Skills.ApexNeeds} POINTS IN {string.upper(branch.name)}`
		else string.upper(why or "")
	CardKit.hero(list, {
		name = "SkillDetails",
		order = order + 1,
		height = ctx.heroHeight or 196,
		picture = { emoji = def.icon },
		title = title(def),
		value = squares(rank, def.ranks),
		valueColor = if rank > 0 then C.gold else C.dim,
		facts = `Now: {Rules.describe(def, rank)} · {nextLine}`,
		ribbon = { text = `{branch.icon} {string.upper(branch.name)} · {rank}/{def.ranks}`, face = K.raised, ink = K.text },
		corner = { text = if def.cost == 1 then "1 POINT" else `{def.cost} POINTS`, ink = C.gold, width = 84 },
		action = {
			name = "SkillBuy",
			text = button,
			kind = if ok then (if def.apex then "gold" else "primary") else "shut",
			onClick = function()
				if ok then
					ask("buy", def.id)
				end
			end,
		},
		onOpen = function() end,
		silent = true,
	})
	Ui.label(list, `{def.text}. {Rules.free(ctx.skills, ctx.level)} free {if Rules.free(ctx.skills, ctx.level) == 1 then "point" else "points"} · RESET in SKILLS gives every point back, free.`, UDim2.new(1, 0, 0, 34), {
		Name = "SkillNote",
		LayoutOrder = order + 2,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return order + 3
end

-- Draws the tab into `list` (a vertical list) from `order`; returns the next order.
function SkillsView.draw(list: Instance, ctx: Ctx, order: number): number
	local open = SkillsView.open
	if open then
		local def, branch = Rules.find(open)
		if def and branch then
			return details(list, def, branch, ctx, order)
		end
		SkillsView.open = nil
	end
	hero(list, ctx, order)
	local holder = Ui.make("Frame", { Name = "SkillTree", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order + 1 }, list)
	Ui.make("UIListLayout", {
		FillDirection = if ctx.wide then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	local share = if ctx.wide then 1 / #Config.Skills.Branches else 1
	for index, branch in Config.Skills.Branches do
		local column = Ui.make("Frame", {
			Name = `Column_{branch.id}`,
			Size = UDim2.new(share, if ctx.wide then -6 else 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, holder)
		Ui.list(column, true, KIT.Gap)
		branchColumn(column, branch, ctx)
	end
	return order + 2
end

return SkillsView
