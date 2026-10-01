-- Minimal Roblox stubs so RiftKing.luau can run in the standalone Luau CLI (a logic test, no rendering).
local S = {}

-- Vector3
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2) end
	if k == "Unit" then local m = math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2); return vec(t.X / m, t.Y / m, t.Z / m) end
	return V[k]
end
function V.Lerp(a, b, t) return a + (b - a) * t end
S.Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end, one = vec(1, 1, 1), zero = vec(0, 0, 0) }

-- CFrame: only a position (rotations are ignored)
local CF = {}
local function cf(p) return setmetatable({ Position = p }, CF) end
CF.__index = CF
CF.__mul = function(a, b) return cf(a.Position + b.Position) end
CF.__sub = function(a, v) return cf(a.Position - v) end
S.CFrame = {
	new = function(a, b, c) if type(a) == "number" then return cf(vec(a, b, c)) elseif a then return cf(a) else return cf(vec(0, 0, 0)) end end,
	Angles = function() return cf(vec(0, 0, 0)) end,
	lookAt = function(a) return cf(a) end,
	identity = cf(vec(0, 0, 0)),
}

-- Enum (any member access returns a unique token)
local function enumType(name)
	return setmetatable({}, { __index = function(t, k) local v = { Name = k, EnumType = name }; rawset(t, k, v); return v end })
end
S.Enum = setmetatable({}, { __index = function(t, k) local e = enumType(k); rawset(t, k, e); return e end })

S.Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255, Lerp = function(a, b2, t) return a end } end, new = function(r, g, b) return { R = r, G = g, B = b, Lerp = function(a) return a end } end }
S.ColorSequence = { new = function(c) return { c } end }
S.NumberSequence = { new = function(a, b) return { a, b } end }
S.TweenInfo = { new = function(...) return { ... } end }

-- Instances
S.created = {} -- every Instance.new, for counting
local Inst = {}
Inst.__index = Inst
local BASEPARTS = { Part = true, WedgePart = true, MeshPart = true }
function Inst.Destroy(self) self.Parent = nil; self.destroyed = true end
function Inst.IsA(self, class) return self.ClassName == class or (class == "BasePart" and BASEPARTS[self.ClassName] == true) end
function Inst.SetAttribute(self, k, v) self.attributes[k] = v end
function Inst.GetAttribute(self, k) return self.attributes[k] end
function Inst.GetDescendants(self) return self.descendants or {} end
function Inst.FindFirstChild(self, name)
	for _, d in self.descendants or {} do if d.Name == name then return d end end
	return nil
end
function Inst.FindFirstChildOfClass(self, class)
	for _, d in self.descendants or {} do if d.ClassName == class then return d end end
	return nil
end
function Inst.GetPivot(self) return self.pivot or cf(vec(0, 0, 0)) end
function Inst.PivotTo(self, c) self.pivot = c end
function S.newInstance(class)
	local o = setmetatable({ ClassName = class, Name = class, attributes = {}, descendants = {}, Size = vec(1, 1, 1), Transparency = 0 }, Inst)
	table.insert(S.created, o)
	return o
end
S.Instance = { new = S.newInstance }

-- Services
S.tweens = 0
S.TweenService = { Create = function(_, obj, _info, goals) return { Play = function() S.tweens += 1; for k, v in goals do obj[k] = v end end } end }
S.Debris = { AddItem = function(_, obj) obj.Parent = nil; obj.destroyed = true end } -- (removed at once: the test counts live parts)
S.players = {}
S.Players = { GetPlayers = function() return S.players end }
S.sent = {} -- Net messages
S.Net = { get = function(name) return { FireClient = function(_, player, ...) table.insert(S.sent, { name = name, ... }) end } end }
S.casts = {}
S.Rig = { cast = function(_, name) table.insert(S.casts, name) end }
S.Plots = { isInArena = function(plot, pos) return plot.inArena(pos) end }

-- A fake player standing in the arena.
function S.newPlayer(name, position)
	local root = S.newInstance("Part"); root.Name = "HumanoidRootPart"; root.Position = position; root.Size = vec(2, 2, 1)
	local humanoid = S.newInstance("Humanoid"); humanoid.Health = 100; humanoid.taken = 0; humanoid.state = S.Enum.HumanoidStateType.Running
	humanoid.TakeDamage = function(self, amount) self.Health -= amount; self.taken += amount end
	humanoid.GetState = function(self) return self.state end
	local character = S.newInstance("Model"); character.descendants = { root, humanoid }
	return { Name = name, Parent = true, Character = character, root = root, humanoid = humanoid }
end

return S
