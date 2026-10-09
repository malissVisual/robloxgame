--!strict
-- 6.11, the shops' rooftop set pieces (server/ShopArt/Geometry.luau has the art: a giant pizza slice over Luigi's,
-- GUN STORE and a cartridge over Lead & Co., the bike, the car on its pylon, the wrench and the tyre, the ZDC parcel,
-- the gold coin, the red cross; 6.12.6: the hi-vis vest and a ZDC bag over the gear stall's two counters). World's shop
-- builders call ShopProps.place once each (server/GearStall.luau twice, "gearvest" and "zdcbag"):
--     require(script.Parent.ShopProps).place(shop, "guns", frame * require(script.Parent.ShopProps).mount("guns"))
-- (ShopProps.mount: the default spot on that building's roof, in the building's own frame; any roof frame works).
-- One Model "ShopProp_<id>" per prop, decoration only: anchored, CanCollide/CanQuery/CanTouch off, only big pieces
-- cast shadows, native parts only (PolishArt.Builder). It streams as a whole (Atomic). Its letters, the cross and a few
-- accents glow at night in their own colours (DayNight.nightLight, the clients restyle them: client/WorldFx.luau), a
-- prop's floodlight shines at night. A prop with a motion (Art.Motion: the bank's coin spins, the pizza slice bobs)
-- gets its moving parts in a child Model "Moving", tagged "ShopPropMotion", its rest pose in the "Rest" attribute:
-- only the clients move it (client/ShopPropMotion.luau); the server never does.

local CollectionService = game:GetService("CollectionService")

local ShopArt = require(script.Parent.ShopArt.Geometry)
local Builder = require(script.Parent.PolishArt.Builder)
local DayNight = require(script.Parent.DayNight)

local ShopProps = {}

ShopProps.Tag = "ShopPropMotion" -- (client/ShopPropMotion.luau)

-- Where the prop `id` stands on its building, in the frame World builds that building in (its roof's top, -Z out).
function ShopProps.mount(id: string): CFrame
	local mount = assert(ShopArt.Mounts[id], "Unknown shop prop")
	return CFrame.new(mount.at[1], mount.at[2], mount.at[3])
end

-- Builds the prop `id` on a roof: `roof` is the middle of the roof's top, -Z (LookVector) toward the street. Returns its
-- Model (in `parent`). If the art fails, an empty Model stands there and a warning says why (the shop still works).
function ShopProps.place(parent: Instance, id: string, roof: CFrame): Model
	local holder = Instance.new("Folder") -- (built off the world, parented once finished)
	local ok, result = pcall(function(): Model
		local pieces = ShopArt.pieces(id)
		local lit: { [string]: Color3 } = {}
		local moving: { [string]: boolean } = {}
		for _, piece in pieces do
			local color = piece.lit
			if color then
				lit[piece.name] = Color3.fromRGB(color[1], color[2], color[3])
			end
			if piece.moves then
				moving[piece.name] = true
			end
		end
		-- Each glowing piece in its own night colour (Builder hands every one the same warm white).
		local function night(item: Instance, litColor: Color3?, dim: Color3?, material: string?)
			DayNight.nightLight(item, lit[item.Name] or litColor, dim, material)
		end
		local model = Builder.build(holder, roof, { id = "ShopProp_" .. id, pieces = pieces :: any }, { nightLight = night })
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model.WorldPivot = roof
		model:SetAttribute("ShopProp", id)
		local motion = ShopArt.Motion[id]
		if motion then
			local group = Instance.new("Model")
			group.Name = "Moving"
			local first: BasePart? = nil
			for _, item in model:GetChildren() do
				if item:IsA("BasePart") and moving[item.Name] then
					item.Parent = group
					first = first or item
				end
			end
			local rest = roof * CFrame.new(motion.pivot[1], motion.pivot[2], motion.pivot[3])
			-- (6.11 review: with a PrimaryPart the model's pivot is that part's own frame times its PivotOffset, and
			-- WorldPivot is ignored: the offset puts the pivot on the rest frame, else PivotTo moved the slice ~2.8 studs
			-- and turned it sideways)
			group.PrimaryPart = first
			if first then
				first.PivotOffset = first.CFrame:ToObjectSpace(rest)
			end
			group.WorldPivot = rest
			group:SetAttribute("Rest", rest)
			group:SetAttribute("Motion", motion.kind)
			group:SetAttribute("Rate", motion.rate or 0)
			group:SetAttribute("Amplitude", motion.amplitude or 0)
			group:SetAttribute("Period", motion.period or 0)
			group:SetAttribute("Sway", motion.sway or 0)
			group.Parent = model
			CollectionService:AddTag(group, ShopProps.Tag)
		end
		return model
	end)
	local model: Model
	if ok then
		model = result
	else
		warn(`[ShopProps] the {id} prop failed: {result}`)
		model = Instance.new("Model")
		model.Name = "ShopProp_" .. id
	end
	model.Parent = parent
	holder:Destroy()
	return model
end

return ShopProps
