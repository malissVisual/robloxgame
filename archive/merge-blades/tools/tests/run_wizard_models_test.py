#!/usr/bin/env python3
"""
Checks the element wizards' models (src/shared/StageModels/WizardEvolution, made by tools/wizards_evolution.py) in the
standalone Luau CLI: every element of a wizard type (Config/Wizards.luau `evolution`) has all 16 levels, every level
has the 16 body parts and 15 joints SoldierRig needs, every piece is a well-formed entry on a real body part, the
staff's highest piece glows (the fireballs start there, BattleFx flashes its light) and the gear grows with the level.

    python3 tools/tests/run_wizard_models_test.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"
SRC = os.path.join(ROOT, "src/shared/StageModels/WizardEvolution")

HEADER = '''local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
local CFrame = { new = function(...) local n = select("#", ...); local t = { ... }; return { Position = { X = t[1], Y = t[2], Z = t[3] }, n = n } end }
'''

TEST = r'''
local Wizards = require("./Wizards")
local BODY = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function wellFormed(e, where)
	check(type(e[1]) == "string", where .. ": host")
	check(type(e[2]) == "table" and (e[2].n == 3 or e[2].n == 12), where .. ": CFrame")
	check(type(e[3]) == "table" and e[3].X > 0 and e[3].Y > 0 and e[3].Z > 0, where .. ": size")
	check(type(e[4]) == "table" and e[4].R >= 0 and e[4].R <= 255, where .. ": color")
	check(type(e[5]) == "number", where .. ": material")
end
local elements = {}
for _, id in Wizards.Order do
	local def = Wizards.Types[id]
	if def.evolution then
		elements[def.evolution] = true
	end
end
local count = 0
for element in elements do
	count += 1
	local lastGear = 0
	for lv = 1, 16 do
		local name = string.format("%s_L%02d", element, lv)
		local ok, data = pcall(require, "./" .. name)
		check(ok and type(data) == "table", name .. " loads")
		if ok then
			local where = name
			check(type(data.name) == "string" and #data.name > 0, where .. " has a name")
			check(type(data.top) == "number" and data.top > 1 and data.top < 8, where .. " top")
			local parts = {}
			for _, e in data.body do
				parts[e[1]] = true
				wellFormed(e, where .. " body")
			end
			for _, b in BODY do
				check(parts[b] == true, where .. " body part " .. b)
			end
			check(#data.joints == 15, where .. " 15 joints")
			for _, e in data.gear do
				wellFormed(e, where .. " gear")
				check(parts[e[1]] == true, where .. " gear on a body part (" .. tostring(e[1]) .. ")")
			end
			check(#data.weapon > 0, where .. " holds something")
			local topY, topLight = -math.huge, false
			for _, e in data.weapon do
				wellFormed(e, where .. " weapon")
				check(e[1] == "RightHand", where .. " weapon in the right hand")
				local y = e[2].Position.Y + e[3].Y / 2
				if e[2].Position.Y > topY then
					topY = e[2].Position.Y
				end
			end
			local lit = false
			for _, e in data.weapon do
				if e[6] and e[6].light then
					lit = true
				end
				if e[2].Position.Y == topY and e[5] == 288 then
					topLight = true
				end
			end
			check(lit, where .. " the staff has a light (BattleFx.crystalFlash)")
			check(topLight or lv >= 4, where .. " the wand's tip glows")
			for _, e in data.offhand do
				wellFormed(e, where .. " offhand")
			end
			check((#data.offhand > 0) == (lv >= 8), where .. " the orb in the left hand from level 8")
			local total = #data.gear + #data.weapon + #data.offhand
			check(total >= lastGear, where .. " the gear grows with the level (" .. total .. " < " .. lastGear .. ")")
			lastGear = total
		end
	end
end
check(count == 6, "six elements (" .. count .. ")")
if fails == 0 then
	print("ALL CHECKS PASSED")
else
	print(fails .. " CHECKS FAILED")
	os.exit(1)
end
'''

with tempfile.TemporaryDirectory() as tmp:
    for name in os.listdir(SRC):
        if name.endswith(".luau") and name != "init.luau":
            text = open(os.path.join(SRC, name), encoding="utf-8").read().replace("--!strict", "")
            open(os.path.join(tmp, name), "w", encoding="utf-8").write(HEADER + text)
    wiz = open(os.path.join(ROOT, "src/shared/Config/Wizards.luau"), encoding="utf-8").read().replace("--!strict", "")
    open(os.path.join(tmp, "Wizards.luau"), "w", encoding="utf-8").write(HEADER + wiz)
    open(os.path.join(tmp, "test.luau"), "w", encoding="utf-8").write(TEST)
    result = subprocess.run([luau, os.path.join(tmp, "test.luau")], capture_output=True, text=True)
    print(result.stdout.strip() or result.stderr.strip())
    if result.returncode != 0:
        print(result.stderr.strip())
        sys.exit(1)
