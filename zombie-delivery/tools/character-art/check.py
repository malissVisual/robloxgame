#!/usr/bin/env python3
"""Audit the real native rig factory and export its exact parts. The recorder does not simulate Roblox joints."""
import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent

def export(luau, output):
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        mock = (ROOT / "tools/vehicle-preview/roblox-mock.luau").read_text()
        # Only record the engine call. Attachment positions are audited; actual engine-generated joints need Studio.
        mock = mock.replace("return Mock", """
local originalNew = Mock.Instance.new
Mock.Instance.new = function(class)
    local obj = originalNew(class)
    if class == "Humanoid" then obj.BuildRigFromAttachments = function(self) self.built = true end end
    return obj
end
return Mock""")
        (tmp / "mock.luau").write_text(mock)
        (tmp / "Geometry.luau").write_text((ROOT / "src/server/CharacterArt/Geometry.luau").read_text())
        (tmp / "Config.luau").write_text((ROOT / "src/shared/Config.luau").read_text())
        rig = (ROOT / "src/server/CharacterArt/Rig.luau").read_text().replace(
            "require(script.Parent.Geometry)", 'require("./Geometry")')
        (tmp / "Rig.luau").write_text(
            'local M=require("./mock")\nlocal Instance,Vector3,Color3,CFrame,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.Enum\n' + rig)
        (tmp / "check.luau").write_text((HERE / "check.luau").read_text())
        (tmp / "CourierMotion.luau").write_text((ROOT / "src/shared/CourierMotion.luau").read_text())
        avatar = (ROOT / "src/server/CourierAvatar.luau").read_text()
        avatar = avatar.replace('require(ReplicatedStorage:WaitForChild("Shared").CourierMotion)', 'require("./CourierMotion")')
        avatar = avatar.replace("require(script.Parent.CharacterArt.Geometry)", 'require("./Geometry")')
        avatar = avatar.replace("require(script.Parent.CharacterArt.Rig)", 'require("./Rig")')
        (tmp / "Avatar.luau").write_text(
            'local M=require("./mock")\nlocal game,Instance,Vector3,script,task,Enum=M.game,M.Instance,M.Vector3,M.script,M.task,M.Enum\n' + avatar)
        # 5.9.2: the template's Animate LocalScript is the client's locomotion controller; run it per body.
        animate = (ROOT / "src/server/CharacterArt/Animate.client.luau").read_text()
        animate = animate.replace('require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CourierMotion"))', 'require("./CourierMotion")')
        if 'require("./CourierMotion")' not in animate:
            raise RuntimeError("Animate.client.luau: the CourierMotion require moved; update tools/character-art/check.py")
        (tmp / "Animate.luau").write_text(
            'local M=require("./mock")\nlocal Motion=require("./CourierMotion")\nreturn function(env)\n'
            'local game,Instance,Vector3,script,Enum=env.game,M.Instance,M.Vector3,env.script,M.Enum\n'
            + animate.replace('local Motion = require("./CourierMotion")', "") + "\nend\n")
        (tmp / "avatar-check.luau").write_text((HERE / "avatar-check.luau").read_text())
        result = subprocess.run([str(Path(luau).resolve()), "check.luau"], cwd=tmp, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        lifecycle = subprocess.run([str(Path(luau).resolve()), "avatar-check.luau"], cwd=tmp, capture_output=True, text=True)
        if lifecycle.returncode or "ALL CHECKS PASSED" not in lifecycle.stdout:
            raise RuntimeError(lifecycle.stdout + lifecycle.stderr)
        bags = bag_check(tmp, luau)
    models = [json.loads(line) for line in result.stdout.splitlines()]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(models, separators=(",", ":")) + "\n")
    print("Native character factory PASS:", {m["id"]: len(m["parts"]) for m in models})
    print("PASS: attachment bind positions, real builder flags/welds, clones, clearance and native-only budgets.")
    print(lifecycle.stdout.strip())
    print(bags)
    print("BuildRigFromAttachments/Animator physics and replication require Studio; the recorder does not simulate them.")

# 6.4.1: the worn bag built by the real server/KitWear.luau (its requires pointed at the pure shared modules, the real
# ModelArt Builder and KitArt, stubs for the services it only uses at runtime) on the courier's R15 body and an R6 body
# (bag-check.luau). 6.4 never built a bag ("Unknown kit id: bag@hand"); this would have said so.
SHARED = ("Config", "Economy", "Transport", "Holding", "KitFit", "BagFill")

def bag_check(tmp, luau):
    src = ROOT / "src"
    prefix = ('local M=require("./mock")\nlocal game,Instance,Vector3,Color3,CFrame,UDim2,Enum,workspace=M.game,M.Instance,'
              'M.Vector3,M.Color3,M.CFrame,M.UDim2,M.Enum,M.workspace\n')
    for name in SHARED:
        text = (src / "shared" / f"{name}.luau").read_text()
        (tmp / f"{name}.luau").write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text))
    (tmp / "Builder.luau").write_text(prefix + (src / "server/ModelArt/Builder.luau").read_text())
    (tmp / "KitGeometry.luau").write_text((src / "server/KitArt/Geometry.luau").read_text())
    (tmp / "PhoneGeometry.luau").write_text((src / "server/PhoneArt/Geometry.luau").read_text())
    (tmp / "Stub.luau").write_text("return {}\n")
    (tmp / "Net.luau").write_text("return {}\n")  # (only KitWear.start uses the remotes)
    wear = (src / "server/KitWear.luau").read_text()
    wear = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', wear)
    for module, local in (("PlayerData", "Stub"), ("ModelArt.Builder", "Builder"), ("Npcs", "Stub"),
                          ("KitArt.Geometry", "KitGeometry"), ("PhoneArt.Geometry", "PhoneGeometry"),
                          ("CharacterArt.Geometry", "Geometry")):
        call = f"require(script.Parent.{module})"
        if call not in wear:
            raise RuntimeError(f"KitWear.luau: {call} moved; update tools/character-art/check.py")
        wear = wear.replace(call, f'require("./{local}")')
    if "require(script" in wear:
        raise RuntimeError("KitWear.luau requires a module the bag check does not know; update tools/character-art/check.py")
    (tmp / "KitWear.luau").write_text(prefix + wear)
    (tmp / "bag-check.luau").write_text((HERE / "bag-check.luau").read_text())
    result = subprocess.run([str(Path(luau).resolve()), "bag-check.luau"], cwd=tmp, capture_output=True, text=True)
    if result.returncode or "ALL CHECKS PASSED" not in result.stdout:
        raise RuntimeError("Worn bag check FAILED:\n" + result.stdout + result.stderr)
    return "Worn bag PASS (real KitWear + Builder, R15 courier and R6): " + result.stdout.strip().splitlines()[-2]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    export(args.luau, args.output)
