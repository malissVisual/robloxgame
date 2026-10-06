--!strict
-- Pure six-part handset on RightHand. Claude controls the on-foot phone pose and UI lifecycle.
local Geometry = {}
Geometry.ids = { "phone" }
function Geometry.pieces(id: string): any
	assert(id == "phone", "Unknown phone model")
	return {
		{ name = "Case", size = { .68, 1.18, .11 }, at = { 0, -.12, -.3 }, attach = "RightHand", finish = "charcoal", shadow = true },
		{ name = "Screen", size = { .57, .9, .025 }, at = { 0, -.11, -.37 }, attach = "RightHand", finish = "screen", text = "ZDC", textSlot = "PhoneScreen" },
		{ name = "Speaker", size = { .19, .025, .025 }, at = { 0, .41, -.37 }, attach = "RightHand", finish = "sole" },
		{ name = "CameraLens", size = { .035, .12, .12 }, at = { -.22, .34, -.225 }, attach = "RightHand", finish = "glass", shape = "Cylinder", turn = { 0, 90, 0 } },
		{ name = "SideKey", size = { .035, .18, .07 }, at = { .35, .16, -.3 }, attach = "RightHand", finish = "red" },
		{ name = "CompanyTab", size = { .16, .035, .02 }, at = { 0, -.64, -.37 }, attach = "RightHand", finish = "red" },
	}
end
function Geometry.spec(id: string): any
	return { id = id, pieces = Geometry.pieces(id), origins = { RightHand = { 0, 1, 0 } }, newRoots = 0,
		attachments = {
			{ name = "PhoneGrip", attach = "RightHand", at = { 0, -.22, -.3 } },
			{ name = "PhoneScreenCenter", attach = "RightHand", at = { 0, -.11, -.388 } },
		},
	}
end
return Geometry
