--!strict
-- The admin panel (F7 or the ADMIN button; only for players with the "Admin" attribute, see server/Admin.luau).
-- [STUB: stream E "admin" fills this in.]

local AdminPanel = {}

-- Set by Main: Hud's screen gui to put the panel in.
function AdminPanel.start() end

function AdminPanel.isOpen(): boolean
	return false
end

return AdminPanel
