--!strict
-- Native fireescape facade; callers provide cardinal street walls and protected bays.
local Facade = require(script.Parent.Parent.TowerArt.Facade)
return function(w: number, d: number, h: number, walls: { Facade.Wall })
 return Facade.build("fireescape", w, d, h, walls)
end
