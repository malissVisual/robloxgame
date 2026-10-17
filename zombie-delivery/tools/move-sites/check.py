#!/usr/bin/env python3
"""The ZDC dispatch kiosk: builds it with the real server/MoveSites.luau on the recorder (export.luau, as
server/LobbyWorld.luau calls MoveSites.kiosk) and checks what comes out, in the world's own coordinates.

  * every piece of shared/MoveSiteLooks.luau's board built, nothing else, within Config.MoveSites.Budget parts; finite
    numbers
  * every part anchored, CanTouch off, CanQuery only with CanCollide (decoration neither); the PointLights within
    Config.MoveSites.Lights, shadowless and given to DayNight (the lamps' day look), every glowing part given too
  * the text: drawn within MoveSiteLooks.textRange (Config.MoveSites.TextRange at least), 25-100 pixels a stud, scaled
  * the model as the runs need it: Persistent, its corkboard "Board" its PrimaryPart (the prompt's part, solid), within
    a stud of SandboxMap.Lobby.dispatch's spot sideways
(10.5: the city's moving world, the depot's kiosk, the Wall's checkpoint, the houses' dress, Walt's farm, the banner
and the evacuation spots, went with the city; so did their render.)

    python3 zombie-delivery/tools/move-sites/check.py <luau>
"""
from pathlib import Path
import argparse
import json
import math
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
SHARED = ROOT / "src" / "shared"
HEAD = ('local M = require("./ItemMock")\n'
        'local Instance, Vector3, Color3, CFrame, Enum, UDim2 = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum, M.UDim2\n'
        'local UDim = { new = function(a, b) return { a, b } end }\n'
        'local game = M.game\n')
# DayNight on the recorder: marks what registers (the lit colour of a glowing part).
NIGHT = ('{ nightLight = function(obj, lit, dim, material) obj:SetAttribute("NightLight", true); '
         'if lit then obj:SetAttribute("LitColor", lit) end end }')


def export(luau: str) -> list:
    """Every JSON line export.luau prints (the parts, the summary last)."""
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        for source in SHARED.glob("*.luau"):
            text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
            (tmp / source.name).write_text(text)
        shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
        shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
        server = (ROOT / "src/server/MoveSites.luau").read_text()
        server = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', server)
        server = server.replace("require(script.Parent.DayNight)", NIGHT)
        assert "script.Parent" not in server, "MoveSites requires a server module the check does not stand in for"
        (tmp / "MoveSitesServer.luau").write_text(HEAD + server)
        shutil.copy(HERE / "export.luau", tmp / "export.luau")
        result = subprocess.run([str(Path(luau).resolve()), "export.luau"], cwd=tmp, capture_output=True, text=True)
        if result.returncode != 0 or not result.stdout.strip():
            raise SystemExit("export failed:\n" + result.stdout[-3000:] + result.stderr[-3000:])
        return [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]


def check(records: list) -> list:
    """The failures (empty: all good)."""
    summary = records[-1]
    assert summary["kind"] == "summary"
    parts = [r for r in records if r["kind"] == "part"]
    bad = []

    def need(ok, what):
        if not ok:
            bad.append(what)

    # Every piece, nothing else, within the budget; finite.
    need(len(parts) == summary["pieces"], f"{len(parts)} parts built for {summary['pieces']} pieces")
    need(len(parts) <= summary["budget"], f"{len(parts)} parts over the budget {summary['budget']}")
    for p in parts:
        numbers = p["position"] + p["size"] + p["rotation"]
        need(all(isinstance(n, (int, float)) and math.isfinite(n) for n in numbers), f"{p['name']}: numbers")
        need(all(n >= 0.04 for n in p["size"]), f"{p['name']}: size")

    # The flags.
    lights = 0
    for p in parts:
        where = p["name"]
        need(p["anchored"], where + " not anchored")
        need(not p["touch"], where + " CanTouch")
        need(p["query"] == p["collide"], where + " CanQuery without CanCollide (or the other way)")
        for light in p["lights"]:
            lights += 1
            need(light["night"] and not light["shadows"], where + ": its light not DayNight's or with shadows")
        if p.get("lit") is not None:
            need(p["night"], where + ": glows but DayNight does not know it")
        for w in p["words"]:
            need(w["range"] >= summary["textRange"] and 25 <= w["pps"] <= 100, f"{where}: text range {w['range']} / {w['pps']} px")
            need(len(w["lines"]) > 0 and all(line["text"] and line["scaled"] for line in w["lines"]), where + ": empty or unscaled text")
    need(0 < lights <= summary["lights"], f"{lights} lights (at most {summary['lights']})")

    # The model as the runs need it.
    need(summary["mode"].endswith("Persistent"), f"streaming {summary['mode']}")
    need(summary["primary"] == "Board" and summary["corkboard"] == "Board", f"primary part {summary['primary']}, corkboard {summary['corkboard']}")
    sx, sz = summary["spot"]
    for p in parts:
        if p["name"] == "Board":
            need(p["collide"], "the corkboard not solid")
            need(math.hypot(p["position"][0] - sx, p["position"][2] - sz) < 1.5, "the corkboard off the dispatch spot")
            need(3.5 < p["position"][1] - summary["groundTop"] < 6.5, "the corkboard not at a hand's height")
    return bad


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    args = parser.parse_args()
    records = export(args.luau)
    bad = check(records)
    summary = records[-1]
    if bad:
        print("Move sites FAIL:")
        for line in bad:
            print("  " + line)
        raise SystemExit(1)
    print(f"Move sites PASS: the dispatch kiosk, {int(summary['parts'])} parts (budget {int(summary['budget'])}); flags, lights, text, streaming and the prompt's part checked")


if __name__ == "__main__":
    main()
