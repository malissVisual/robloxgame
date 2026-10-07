--!strict
-- Pure phone sizing and server-payload presentation. No invented orders, money or route destinations.
local PhoneLayout = {}

export type Fit = { scale: number, width: number, height: number }
-- 6.0.1: an app's centred popup (client/PhonePopup.luau): its size in px at `scale`, and room for two columns.
export type Popup = { scale: number, width: number, height: number, wide: boolean }

PhoneLayout.SHORT_SCALE = 0.85 -- the smallest scale a short screen shrinks the upright phone to (then it scrolls)
PhoneLayout.POPUP_W, PhoneLayout.POPUP_H = 760, 520 -- the popup panel at the desktop scale
PhoneLayout.POPUP_WIDE = 600 -- a popup this wide (px at its scale) shows the board, career and shop in two columns

-- 6.0.1: the phone always stands upright (no app turns it, no screen lays it down). A short screen shrinks it a little
-- (to SHORT_SCALE), then gives it a shorter scrollable body, rather than shrinking the text until it cannot be read.
function PhoneLayout.fit(width: number, height: number, touch: boolean, cap: number): Fit
	width, height = math.max(100, width), math.max(100, height)
	local scale = math.min(if touch then 1 else cap, (width - 32) / 340)
	scale = math.min(scale, math.max(PhoneLayout.SHORT_SCALE, (height - 32) / 560))
	return { scale = scale, width = 340, height = math.min(680, (height - 32) / scale) }
end

-- 6.0.1: an app's popup: 760 × 520 at the desktop scale (`cap`; touch keeps 1 so its text and targets stay full
-- size), never wider than 92 % or taller than 86 % of the screen (the content scrolls).
function PhoneLayout.popup(width: number, height: number, touch: boolean, cap: number): Popup
	width, height = math.max(100, width), math.max(100, height)
	local scale = if touch then 1 else cap
	local w = math.min(PhoneLayout.POPUP_W, width * 0.92 / scale)
	local h = math.min(PhoneLayout.POPUP_H, height * 0.86 / scale)
	return { scale = scale, width = w, height = h, wide = w >= PhoneLayout.POPUP_WIDE }
end

function PhoneLayout.summary(payload: any, now: number, x: number?, z: number?): any
	if type(payload) ~= "table" then
		return { active = false, title = "READY FOR YOUR NEXT RUN", meta = "Find a delivery on the board", clock = "", share = 0 }
	end
	local count = 1
	if type(payload.orders) == "table" then
		count = 0
		for _, entry in payload.orders do
			if type(entry) == "table" and entry.state == "open" then
				count += 1
			end
		end
	end
	local title = tostring(payload.stopLabel or payload.customer or payload.address or payload.cargo or "ACTIVE DELIVERY")
	local total = math.max(0, tonumber(payload.total) or 0)
	local left = if type(payload.endsAt) == "number" then math.max(0, payload.endsAt - now) else nil
	local limit = tonumber(payload.timeLimit) or 0
	local distance: number? = nil
	local pos = payload.position
	if x and z and pos and type(pos.X) == "number" and type(pos.Z) == "number" then
		distance = math.floor(math.sqrt((pos.X - x)^2 + (pos.Z - z)^2) + 0.5)
	end
	return {
		active = true, title = string.upper(title), count = count,
		meta = `{total} {if total == 1 then "piece" else "pieces"}{if distance then ` · {distance} studs away` else ""}`,
		left = left, pay = math.max(0, tonumber(payload.pay) or 0),
		share = if left and limit > 0 then math.clamp(left / limit, 0, 1) else 0,
	}
end

return PhoneLayout
