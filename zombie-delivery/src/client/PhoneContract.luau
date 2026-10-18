--!strict
-- The white line glyphs before a window's title (client/Ui.luau Ui.glyph draws them through this module, found by
-- name): straight segments in a 32 × 32 box, drawn with native Frames (no uploaded picture). The big map's ("map") and
-- the admin panel's ("settings"). 10.6: the city phone's app glyphs, its brand header and its contract card are gone.
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local K = Theme.Contract
local Contract = {}

-- Straight line segments in a 32 × 32 glyph box.
local GLYPHS: { [string]: { { number } } } = {
	map = {{16,2,7,5},{7,5,4,13},{4,13,16,30},{16,30,28,13},{28,13,25,5},{25,5,16,2},{12,10,20,10},{20,10,20,16},{20,16,12,16},{12,16,12,10}},
	settings = {{12,2,20,2},{20,2,22,8},{22,8,29,11},{29,11,29,21},{29,21,22,24},{22,24,20,30},{20,30,12,30},{12,30,10,24},{10,24,3,21},{3,21,3,11},{3,11,10,8},{10,8,12,2},{12,12,20,12},{20,12,20,20},{20,20,12,20},{12,20,12,12}},
}

-- Draws the glyph `id` centred in `parent`, `size` px (an unknown id: nothing).
function Contract.glyph(parent: Instance, id: string, size: number)
	local segments = GLYPHS[id]
	if not segments then
		return
	end
	local box = Ui.make("Frame", { Name = "NativeGlyph", Size = UDim2.fromOffset(size,size), Position = UDim2.fromScale(.5,.5), AnchorPoint = Vector2.new(.5,.5), BackgroundTransparency = 1 }, parent)
	for _, s in segments do
		local dx, dy = s[3]-s[1], s[4]-s[2]
		Ui.make("Frame", { Size = UDim2.fromOffset(math.sqrt(dx*dx+dy*dy)*size/32, 1.5), Position = UDim2.fromOffset((s[1]+s[3])*size/64,(s[2]+s[4])*size/64), AnchorPoint = Vector2.new(.5,.5), Rotation = math.deg(math.atan2(dy,dx)), BackgroundColor3 = K.text, BorderSizePixel = 0 }, box)
	end
end

return Contract
