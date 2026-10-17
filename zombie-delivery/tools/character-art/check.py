#!/usr/bin/env python3
"""Audit the real native rig factory (server/CharacterArt: the infected's block bodies and every look of
shared/ZombieStyle.luau, the courier's fallback body) and export its exact parts (design/character-models/geometry.json).
The recorder does not simulate Roblox joints.

    python3 tools/character-art/check.py <luau> design/character-models/geometry.json [--looks looks.json]

10.6: the city's checks went (the worn bags of server/KitWear.luau, the STYLE cosmetics of server/StyleWear.luau and
the 6.9 avatar template's lifecycle); the avatar is checked by tests/characterlooks_test.luau and
tests/saveslots_runtime_test.luau now."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent

def export(luau, output, looks_output=None):
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
        # 6.16: the infected's looks (pure; check.luau builds every one)
        (tmp / "ZombieStyle.luau").write_text((ROOT / "src/shared/ZombieStyle.luau").read_text().replace(
            "require(script.Parent.Config)", 'require("./Config")'))
        rig = (ROOT / "src/server/CharacterArt/Rig.luau").read_text().replace(
            "require(script.Parent.Geometry)", 'require("./Geometry")')
        (tmp / "Rig.luau").write_text(
            'local M=require("./mock")\nlocal Instance,Vector3,Color3,CFrame,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.Enum\n' + rig)
        (tmp / "check.luau").write_text((HERE / "check.luau").read_text())
        result = subprocess.run([str(Path(luau).resolve()), "check.luau"], cwd=tmp, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
    records = [json.loads(line) for line in result.stdout.splitlines()]
    models = [m for m in records if "look" not in m]
    looks = [m for m in records if "look" in m]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(models, separators=(",", ":")) + "\n")
    print("Native character factory PASS:", {m["id"]: len(m["parts"]) for m in models})
    # 6.16: the infected's looks (shared/ZombieStyle.luau), not in geometry.json; --looks writes them for a preview.
    kinds = {}
    for m in looks:
        kinds.setdefault(m["id"].rsplit("-", 1)[0], []).append(len(m["parts"]))
    print("Infected looks PASS:", {k: f"{len(v)} looks, {min(v)}-{max(v)} parts" for k, v in kinds.items()})
    if looks_output:
        looks_output.write_text(json.dumps(looks, separators=(",", ":")) + "\n")
    print("PASS: attachment bind positions, real builder flags/welds, clones, clearance and native-only budgets.")
    print("BuildRigFromAttachments/Animator physics and replication require Studio; the recorder does not simulate them.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("output", type=Path)
    parser.add_argument("--looks", type=Path, help="6.16: also write every infected look's parts here (a preview)")
    args = parser.parse_args()
    export(args.luau, args.output, args.looks)
