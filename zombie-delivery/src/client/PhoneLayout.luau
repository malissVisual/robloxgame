--!strict
-- Pure phone sizing and server-payload presentation. No invented orders, money or route destinations.
local PhoneLayout = {}

export type Fit = { sideways: boolean, scale: number, width: number, height: number }

-- Short displays get a shorter scrollable device, rather than shrinking the text until it cannot be read.
function PhoneLayout.fit(width: number, height: number, touch: boolean, cap: number): Fit
	width, height = math.max(100, width), math.max(100, height)
	local sideways = width >= 600 and height < 520
	local w = if sideways then 680 else 340
	local scale = math.min(cap, (width - 32) / w)
	local h = math.min(if sideways then 340 else 680, (height - 32) / scale)
	-- Prefer readable physical targets; both home and app content scroll when height is constrained.
	if touch then
		scale = math.min(1, (width - 32) / w)
		h = math.min(if sideways then 340 else 680, (height - 32) / scale)
	end
	return { sideways = sideways, scale = scale, width = w, height = h }
end

-- 5.5: a big app (BOARD, CAREER, SHOP, BAG) turns the phone sideways even where it would stand upright: the landscape
-- body at the largest scale that fits (a narrow touch screen gets a smaller one; the app scrolls).
function PhoneLayout.sideways(width: number, height: number, touch: boolean, cap: number): Fit
	width, height = math.max(100, width), math.max(100, height)
	local scale = math.min(if touch then 1 else cap, (width - 32) / 680, (height - 32) / 220)
	return { sideways = true, scale = scale, width = 680, height = math.min(340, (height - 32) / scale) }
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
