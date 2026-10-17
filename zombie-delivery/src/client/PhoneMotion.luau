--!strict
-- PhoneMotion.reducedMotion(): the player's Reduced Motion setting (Roblox's GuiService.ReducedMotionEnabled), asked
-- by the modules that move things for show (client/Juice.luau, client/GaitPose.luau, client/ItemModel.luau,
-- client/RideUi.luau). (The name is the old courier phone's, whose motion this was.)

local GuiService = game:GetService("GuiService")

local PhoneMotion = {}

function PhoneMotion.reducedMotion(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

return PhoneMotion
