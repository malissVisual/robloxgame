--!strict
-- A clipped, discovered-only route preview using the real Map and Roads; no new navigation authority.
-- Redraw only on resize, discovery or meaningful movement. Parent destruction disconnects every listener.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)
local Roads = require(Shared.Roads)
local Discovery = require(script.Parent.Discovery)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local K = Theme.Contract
local Route = {}
local cached: any = nil -- at most one route; frequent Job payloads reuse the same graph search

function Route.create(parent: Instance, destination: Vector3?, order: number, enabled: (() -> boolean)?): any
	local holder = Ui.make("Frame", { Name = "RoutePreview", Size = UDim2.new(1,0,0,160), BackgroundColor3 = Color3.fromRGB(17,20,25), BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = order }, parent)
	Ui.make("UIStroke", { Color = K.line, Thickness = 1, Transparency = .6 }, holder)
	local drawing = Ui.make("Frame", { Name = "Chart", Size = UDim2.fromScale(1,1), BackgroundTransparency = 1 }, holder)
	local previous: Vector3? = nil
	local alive = true
	local function draw(force: boolean?)
		if enabled and not enabled() then return end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = if root and root:IsA("BasePart") then root.Position else nil
		if not alive or not destination or not position or holder.AbsoluteSize.X < 1 then
			return
		end
		if not force and previous and (position - previous).Magnitude < 48 then
			return
		end
		previous = position
		local points
		if cached and (cached.from - position).Magnitude < 48 and cached.to == destination then
			points = cached.points
		else
			points = Roads.route(position.X,position.Z,destination.X,destination.Z)
			cached = { from = position, to = destination, points = points }
		end
		local x0,x1,z0,z1 = position.X,position.X,position.Z,position.Z
		for _, point in points do
			x0,x1 = math.min(x0,point.x),math.max(x1,point.x)
			z0,z1 = math.min(z0,point.z),math.max(z1,point.z)
		end
		local w,h = holder.AbsoluteSize.X,holder.AbsoluteSize.Y
		local scale = math.min((w-32)/math.max(240,x1-x0),(h-32)/math.max(180,z1-z0))
		local cx,cz = (x0+x1)/2,(z0+z1)/2
		local function project(x: number,z: number): (number,number)
			return w/2+(x-cx)*scale,h/2+(z-cz)*scale
		end
		Ui.clear(drawing)
		local function rect(ax: number,az: number,bx: number,bz: number,color: Color3,layer: number)
			local a,b = project(ax,az)
			local c,d = project(bx,bz)
			if c < 0 or a > w or d < 0 or b > h then return end
			Ui.make("Frame", { Size = UDim2.fromOffset(c-a,d-b), Position = UDim2.fromOffset(a,b), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = layer }, drawing)
		end
		for _, district in Map.Districts do
			for i = district.i0,district.i1 do
				for j = district.j0,district.j1 do
					local x,z = district.ox+i*Map.Cell,district.oz+j*Map.Cell
					local half = Map.BlockSize/2
					rect(x-half,z-half,x+half,z+half,Color3.fromRGB(34,38,44),1)
				end
			end
		end
		local function line(ax: number,az: number,bx: number,bz: number,color: Color3,thickness: number,layer: number)
			local a,b = project(ax,az)
			local c,d = project(bx,bz)
			if math.max(a,c) < 0 or math.min(a,c) > w or math.max(b,d) < 0 or math.min(b,d) > h then return end
			local dx,dy = c-a,d-b
			Ui.make("Frame", { Size = UDim2.fromOffset(math.sqrt(dx*dx+dy*dy),thickness), Position = UDim2.fromOffset((a+c)/2,(b+d)/2), AnchorPoint = Vector2.new(.5,.5), Rotation = math.deg(math.atan2(dy,dx)), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = layer }, drawing)
		end
		for _, segment in Map.Segments do
			line(segment.ax,segment.az,segment.bx,segment.bz,Color3.fromRGB(64,69,76),math.max(2,segment.width*scale),2)
		end
		-- Compress each unknown grid row into spans; terrain stays hidden, job route remains visible as on MapView.
		local grid = Discovery.grid
		local lowX,highX = math.max(0,math.floor((cx-w/2/scale-grid.X0)/grid.Size)),math.min(grid.Cols-1,math.floor((cx+w/2/scale-grid.X0)/grid.Size))
		local lowZ,highZ = math.max(0,math.floor((cz-h/2/scale-grid.Z0)/grid.Size)),math.min(grid.Rows-1,math.floor((cz+h/2/scale-grid.Z0)/grid.Size))
		for z = lowZ,highZ do
			local start: number? = nil
			for x = lowX,highX+1 do
				local unknown = x <= highX and not Discovery.uncoveredCell(x,z)
				if unknown and not start then start = x end
				if not unknown and start then
					rect(grid.X0+start*grid.Size,grid.Z0+z*grid.Size,grid.X0+x*grid.Size,grid.Z0+(z+1)*grid.Size,Color3.fromRGB(17,20,25),3)
					start = nil
				end
			end
		end
		for index = 2,#points do
			local a,b = points[index-1],points[index]
			line(a.x,a.z,b.x,b.z,K.red,3,4)
		end
		for index,at in {position,destination} do
			local x,y = project(at.X,at.Z)
			local marker = Ui.make("Frame", { Name = if index == 1 then "You" else "Destination", Size = UDim2.fromOffset(8,8), Position = UDim2.fromOffset(x,y), AnchorPoint = Vector2.new(.5,.5), BackgroundColor3 = if index == 1 then K.text else K.red, BorderSizePixel = 0, ZIndex = 5 }, drawing)
			if index == 1 then Ui.corner(marker,4) end
		end
	end
	local resized = holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() draw(true) end)
	local known = Discovery.changed:Connect(function() draw(true) end)
	holder.Destroying:Connect(function()
		alive = false
		resized:Disconnect()
		known:Disconnect()
	end)
	if not destination then
		Ui.label(holder,"Route unavailable — check the current objective",UDim2.fromScale(1,1),{TextColor3=K.secondary,TextSize=13,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center})
	end
	task.defer(function() draw(true) end)
	return { holder = holder, destination = destination, update = function() draw(false) end }
end

return Route
