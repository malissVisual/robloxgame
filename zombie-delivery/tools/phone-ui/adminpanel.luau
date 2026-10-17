-- 8.0 SANDBOX: the admin panel (client/AdminPanel.luau with the real shared data and shared/SandboxAdmin.luau) run for
-- real on tools/phone-ui/missions_mock.luau's recorder, twice (two copies of the module: AdminPanelOn, AdminPanelGuest;
-- client/SandboxZones.luau recorded as M.MZones):
--   * an admin: two tabs, SANDBOX first and the one that opens; its groups and every button of SandboxAdmin.Actions
--     are there, each sends ("sandbox", its id, the TARGET's UserId) on the Admin remote; 🔍 SHOW ZONES toggles
--     SandboxZones (no command) and shows ON; the heading follows the target's Plot; 10.6: OP, its FLY and NOCLIP
--     (("fly" | "noclip", on, the TARGET)) and the PERFORMANCE overlay (AdminPanel.onPerformance, no command); on a
--     phone held sideways (844 × 390) the window fits the screen and every SANDBOX button fits its cell;
--   * a player who is not an admin: P does not open it, the ADMIN button stays hidden.
local M = require("./missions_mock")
local SandboxAdmin = require("./SandboxAdmin")

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	print("ok    " .. name)
end
local function all(root, predicate)
	local out = {}
	local function visit(object)
		if predicate(object) then
			table.insert(out, object)
		end
		for _, child in object:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return out
end
local function named(root, name)
	return all(root, function(object)
		return object.Name == name
	end)[1]
end
local function buttons(root)
	return all(root, function(object)
		return object.ClassName == "TextButton"
	end)
end
local function withText(root, text)
	for _, button in buttons(root) do
		if button.Text == text then
			return button
		end
	end
	return nil
end

-- ── The stand-ins (on top of the MISSIONS window's) ─────────────────────────
local players = M.make("Players")
players.LocalPlayer = M.player
players.PlayerAdded = M.signal()
players.PlayerRemoving = M.signal()
players.GetPlayers = function()
	return { M.player }
end
players.GetPlayerByUserId = function(_, id)
	return if id == M.player.UserId then M.player else nil
end
M.player.Parent = players
M.player.AttributeChanged = M.signal()
M.services.Players = players
M.services.RunService.IsStudio = function()
	return false
end
M.MZones = { on = false, toggles = 0 }
function M.MZones.isOn()
	return M.MZones.on
end
function M.MZones.toggle()
	M.MZones.on = not M.MZones.on
	M.MZones.toggles += 1
	return M.MZones.on
end
local camera = M.workspace.CurrentCamera
local function pressP()
	M.actions.ZombieDeliveryAdmin.fn("ZombieDeliveryAdmin", M.Enum.UserInputState.Begin, {})
end
local function newestPanel()
	local found = nil
	for _, child in M.gui:GetChildren() do
		if child.Name == "ZombieDeliveryAdmin" then
			found = child
		end
	end
	return found
end
-- The sidebar's tabs in their order
local function tabsOf(gui)
	local list = buttons(named(gui, "Sidebar"))
	table.sort(list, function(a, b)
		return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
	end)
	return list
end
-- The panel's scrolling content (beside the sidebar)
local function contentOf(gui)
	return all(gui, function(object)
		return object.ClassName == "ScrollingFrame" and object.ScrollingDirection == M.Enum.ScrollingDirection.Y
	end)[1]
end
local function headings(content)
	local list = {}
	for _, child in content:GetChildren() do
		if child.ClassName == "TextLabel" and child.TextSize == 18 then
			table.insert(list, child.Text)
		end
	end
	return list
end

-- ── An admin ────────────────────────────────────────────────────────────────
M.player:SetAttribute("Admin", true)
local Panel = require("./AdminPanelOn")
local flips = 0
Panel.onPerformance = function()
	flips += 1
end
Panel.performanceOn = function()
	return flips % 2 == 1
end
Panel.start()
local gui = newestPanel()
local tabs = tabsOf(gui)
check("two tabs: SANDBOX first, then OP", #tabs == 2 and tabs[1].Text == "SANDBOX" and tabs[2].Text == "OP", tabs[1] and tabs[1].Text)
pressP()
check("P opens the panel for an admin", Panel.isOpen())
local content = contentOf(gui)
local titles = headings(content)
check("…on the SANDBOX tab: the target (you), no plot yet", titles[1] == "Sandbox · you · no plot", titles[1])
local names = {}
for _, group in SandboxAdmin.Groups do
	names[group.name] = true
end
local seen = 0
for _, title in titles do
	if names[title] then
		seen += 1
	end
end
check("its groups: Money, Moves, Collection, Travel and the van, Debug", seen == #SandboxAdmin.Groups, seen)

local missing, wrong = {}, {}
for _, action in SandboxAdmin.Actions do
	local button = withText(content, action.label)
	if not button then
		table.insert(missing, action.label)
	else
		button.Activated:Fire()
		local last = M.lastSent("Admin")
		if not last or last.args[1] ~= "sandbox" or last.args[2] ~= action.id or last.args[3] ~= M.player.UserId then
			table.insert(wrong, action.id)
		end
	end
end
check("every SANDBOX button is there", #missing == 0, table.concat(missing, ", "))
check("each sends (\"sandbox\", its id, the TARGET) on the Admin remote", #wrong == 0, table.concat(wrong, ", "))
local sent = #M.sent
local zones = withText(content, "🔍 SHOW ZONES  ·  OFF")
check("🔍 SHOW ZONES is there, OFF", zones ~= nil)
zones.Activated:Fire()
content = contentOf(gui)
check("SHOW ZONES toggles the debug marks on this screen only (no command)", M.MZones.toggles == 1 and M.MZones.on and #M.sent == sent)
check("…and shows ON", withText(content, "🔍 SHOW ZONES  ·  ON") ~= nil)
withText(content, "🔍 SHOW ZONES  ·  ON").Activated:Fire()
check("…and OFF again", M.MZones.toggles == 2 and not M.MZones.on and withText(contentOf(gui), "🔍 SHOW ZONES  ·  OFF") ~= nil)

M.player:SetAttribute("Plot", 2)
M.player.AttributeChanged:Fire("Plot")
M.flush()
check("the heading follows the target's plot", headings(contentOf(gui))[1] == "Sandbox · you · plot 2", headings(contentOf(gui))[1])

-- A phone held sideways: the window (its UIScale) inside the screen, every SANDBOX button inside its cell.
M.width, M.height = 844, 390
camera.ViewportSize = M.Vector2.new(844, 390)
camera:GetPropertyChangedSignal("ViewportSize"):Fire()
local window = named(gui, "Window")
local scale = window:FindFirstChildOfClass("UIScale").Scale
local wide, tall = window.Size.X.Offset * scale, window.Size.Y.Offset * scale
check("844 × 390: the window fits the screen", wide <= 844 and tall <= 390, `{wide} × {tall}`)
-- The content's width: the window's (Ui.window's inner is as wide), less the sidebar's room, its padding (8) and the
-- scroll bar (6); a grid is 10 narrower (grid(): UDim2.new(1, -10, 0, 0)).
content = contentOf(gui)
local inner = window.Size.X.Offset + content.Size.X.Offset - 8 - content.ScrollBarThickness
local tight = {}
local cells = 0
for _, frame in content:GetChildren() do
	local layout = frame:FindFirstChildOfClass("UIGridLayout")
	if layout then
		local cell = layout.CellSize.X.Offset
		local width = inner + frame.Size.X.Offset
		if cell > width then
			table.insert(tight, `a {cell} cell in {width}`)
		end
		for _, button in buttons(frame) do
			cells += 1
			-- (an emoji is about one letter wide; TextSize × 0.6 a letter of the bold font, 16 of padding)
			local length = utf8.len(button.Text) or #button.Text
			if length * button.TextSize * 0.6 + 16 > cell then
				table.insert(tight, button.Text)
			end
		end
	end
end
check("844 × 390: every SANDBOX button fits its cell, every cell the content", #tight == 0 and cells == #SandboxAdmin.Actions + 1, table.concat(tight, ", "))
check("844 × 390: the two tabs fit the sidebar", #tabs * (40 + 6) <= window.Size.Y.Offset - 51 - 20)

-- 10.6 OP: FLY and NOCLIP for the TARGET, the performance overlay (yours, no command)
tabs[2].Activated:Fire()
content = contentOf(gui)
check("OP: its heading names the target", string.sub(headings(content)[1] or "", 1, 8) == "OP tools", headings(content)[1])
for _, flag in { { "FLY", "fly", "AdminFly" }, { "NOCLIP", "noclip", "AdminNoclip" } } do
	local button = withText(content, `{flag[1]}  ·  OFF`)
	check(`OP: {flag[1]} is there, OFF`, button ~= nil)
	button.Activated:Fire()
	local last = M.lastSent("Admin")
	check(`… it sends ("{flag[2]}", true, the TARGET)`, last ~= nil and last.args[1] == flag[2] and last.args[2] == true and last.args[3] == M.player.UserId)
	M.player:SetAttribute(flag[3], true)
	M.player.AttributeChanged:Fire(flag[3])
	M.flush()
	content = contentOf(gui)
	check(`… and shows ON once the server set {flag[3]}`, withText(content, `{flag[1]}  ·  ON`) ~= nil)
end
sent = #M.sent
withText(content, "PERFORMANCE  ·  OFF").Activated:Fire()
content = contentOf(gui)
check("OP: PERFORMANCE turns the overlay on (AdminPanel.onPerformance, no command) and shows ON", flips == 1 and #M.sent == sent and withText(content, "PERFORMANCE  ·  ON") ~= nil)
check("no city tab or button anywhere (PLAYER, WORLD, GOD MODE, GIVE ALL)", withText(named(gui, "Sidebar"), "PLAYER") == nil and withText(named(gui, "Sidebar"), "WORLD") == nil
	and withText(content, "GOD MODE  ·  OFF") == nil and withText(content, "GIVE ALL (+ $1M)") == nil)
gui:Destroy()

-- ── Not an admin ────────────────────────────────────────────────────────────
M.player:SetAttribute("Admin", nil)
local Guest = require("./AdminPanelGuest")
Guest.start()
gui = newestPanel()
local before = #M.warnings
pressP()
check("a player who is not an admin: P does not open the panel", not Guest.isOpen() and #M.warnings == before + 1)
check("…and the ADMIN button stays hidden", withText(gui, "🛠  ADMIN").Visible == false)
print("ALL ADMIN PANEL CHECKS PASSED")
