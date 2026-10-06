--!strict
-- 5.3, your bag (the inventory of a run): every piece you carry and where it is (shared/Bag.luau groups them): in your
-- hands, in your backpack, on your bike's rack / basket / box, in your vehicle. Each piece shows its picture
-- (shared/Icons.luau, an emoji without one), its name, its order and who it is for and where (the job payload's
-- `carried`, server/Jobs.luau), and over them the room you have: the hands, the backpack (or a round's satchel), the
-- rack. It is the BAG tab of the I window (client/Hud.luau draws it with BagUi.render); the phone's ORDERS app
-- (🎒 BAG) and the contract ticket's chip ("🎒 2 newspapers · 1 pizza stack", Bag.line) open it (BagUi.open: Hud sets
-- BagUi.onOpen). Presentation only: the server decides what you carry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Bag = require(Shared.Bag)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local BagUi = {}

-- Set by client/Hud.luau: opens the I window on its BAG tab.
BagUi.onOpen = nil :: (() -> ())?

function BagUi.open()
	local cb = BagUi.onOpen
	if cb then
		cb()
	end
end

-- The chip's words for a job payload ("🎒 2 newspapers · 1 pizza stack"), nil when you carry nothing.
function BagUi.line(job: any): string?
	if type(job) ~= "table" or type(job.carried) ~= "table" then
		return nil
	end
	return Bag.line(job.carried)
end

local EMOJI: { [string]: string } = {
	pizza = "🍕",
	burger = "🍔",
	noodles = "🍜",
	pastry = "🥐",
	bread = "🥖",
	newspaper = "📰",
	mail = "✉",
	parcel = "📦",
	medicine = "💊",
	bouquet = "💐",
	cake = "🎂",
	groceries = "🛒",
	icecream = "🍦",
	gadget = "📻",
	documents = "💼",
}

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- Draws the bag into a window's scrolling list (a UIListLayout) from layout order `order` on; returns the next one.
function BagUi.render(parent: Instance, job: any, order: number): number
	local n = order
	local carried = if type(job) == "table" and type(job.carried) == "table" then job.carried else {}
	local mode = if type(job) == "table" and type(job.mode) == "string" then job.mode else "car"
	-- The room: the hands, the backpack (or the satchel), the bike's rack.
	local head = P.row(parent, 66, n, true)
	n += 1
	P.caps(head, "Your bag", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(16, 8), TextColor3 = P.ink2, TextSize = 12 })
	local packRoom = tonumber(type(job) == "table" and job.packRoom) or 0
	local rack = tonumber(type(job) == "table" and job.rack) or 0
	local parts: { string } = {}
	if mode == "foot" or mode == "bike" then
		local inHands, inPack, onRack = 0, 0, 0
		for _, piece in carried do
			if type(piece) == "table" then
				if piece.where == "hands" then
					inHands += 1
				elseif piece.where == "rack" then
					onRack += 1
				elseif piece.where == "pack" then
					inPack += 1
				end
			end
		end
		table.insert(parts, `✋ Hands {inHands}/{Config.Cargo.HandsMax}`)
		if packRoom - rack > 0 then
			table.insert(parts, `🎒 Backpack {inPack}/{packRoom - rack}`)
		end
		if rack > 0 then
			table.insert(parts, `🚲 Rack {onRack}/{rack}`)
		end
	else
		table.insert(parts, "🚚 In your vehicle and your hands")
	end
	Ui.label(head, table.concat(parts, "   ·   "), UDim2.new(1, -24, 0, 22), { Position = UDim2.fromOffset(16, 30), TextSize = 16, TextColor3 = P.ink, Font = Theme.HeadingFont, TextWrapped = false })
	local groups = Bag.groups(carried, mode)
	if #groups == 0 then
		local empty = P.row(parent, 52, n)
		n += 1
		Ui.label(empty, "Nothing in your bag. Pick up an order at a shop: the cook or the clerk hands it over at the door.", UDim2.new(1, -24, 1, 0), { Position = UDim2.fromOffset(16, 0), TextSize = 14, TextColor3 = P.ink2, Font = Theme.Font })
		return n
	end
	for _, group in groups do
		P.caps(parent, `{group.icon}  {group.title} · {#group.pieces}`, UDim2.new(1, -12, 0, 22), { LayoutOrder = n, TextColor3 = P.ink2, TextSize = 12 })
		n += 1
		for _, piece in group.pieces do
			local row = P.row(parent, 56, n)
			n += 1
			local look = if type(piece.look) == "string" then piece.look else ""
			Ui.icon(row, Icons.cargo(look), EMOJI[look] or "📦", UDim2.fromOffset(38, 38), { Position = UDim2.fromOffset(10, 9), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
			Ui.label(row, capital(tostring(piece.name or "piece")), UDim2.new(1, -70, 0, 22), { Position = UDim2.fromOffset(58, 6), TextSize = 16, Font = Theme.HeadingFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			local who = if type(piece.dest) == "string" then `for {piece.dest}` else "for the customer"
			local place = if type(piece.place) == "string" and piece.place ~= piece.dest then ` · {piece.place}` else ""
			local fits = if Bag.fits(look) then "" else " · hands / rack only"
			Ui.label(row, `Order {tonumber(piece.order) or 1} · {who}{place}{fits}`, UDim2.new(1, -70, 0, 20), { Position = UDim2.fromOffset(58, 30), TextSize = 13, Font = Theme.Font, TextColor3 = P.ink2, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
	end
	return n
end

return BagUi
