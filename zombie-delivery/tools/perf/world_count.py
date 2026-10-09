#!/usr/bin/env python3
"""6.13.1: count what the real server/World.luau builds, without Roblox (design/performance/REPORT.md).

Runs World.build() in the Luau CLI against a permissive Roblox stand-in (world-mock.luau: values, instances, tags; the
people and the animals left out) and prints, for every piece of the city, the parts, the visible ones, the ones that
throw a shadow, the lights (night lights under client/WorldFx.luau's budget / always on), the SurfaceGuis (and how many
are drawn at any distance), then the models by streaming mode, the depot's parts, the always-on lights and the
far-drawn SurfaceGuis by name. Re-run it after adding to the world and compare with the report.

    python3 tools/perf/world_count.py <path to the luau binary> [zombie-delivery dir]
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def rel(from_dir, target):
    path = os.path.relpath(target, from_dir).replace(os.sep, "/")
    return path if path.startswith(".") else "./" + path


def prepare(game, out):
    shutil.copy(os.path.join(HERE, "world-mock.luau"), os.path.join(out, "mock.luau"))
    shutil.copy(os.path.join(HERE, "world-count.luau"), os.path.join(out, "main.luau"))
    shared_dir = os.path.join(out, "shared")
    for top in ("server", "shared"):
        for dirpath, _, files in os.walk(os.path.join(game, "src", top)):
            for name in files:
                if not name.endswith(".luau") or name.endswith(".client.luau") or name.endswith(".server.luau"):
                    continue
                src = os.path.join(dirpath, name)
                dst = os.path.join(out, os.path.relpath(src, os.path.join(game, "src")))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                here = os.path.dirname(dst)
                text = open(src, encoding="utf-8").read()

                def shared(m):
                    return f'require("{rel(here, os.path.join(shared_dir, m.group(1)))}")'

                text = re.sub(r'require\(Shared\.(\w+)\)', shared, text)
                text = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', shared, text)
                text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\):WaitForChild\("(\w+)"\)\)', shared, text)

                def parent(m):
                    base = here
                    for _ in range(m.group(1).count(".Parent") - 1):
                        base = os.path.dirname(base)
                    return f'require("{rel(here, os.path.join(base, *m.group(2).strip(".").split(".")))}")'

                text = re.sub(r'require\(script((?:\.Parent)+)((?:\.\w+)+)\)', parent, text)
                # (no new local in the module: its globals come from the stand-in's environment)
                header = f'setfenv(1, require("{rel(here, os.path.join(out, "mock"))}").env)\n'
                open(dst, "w", encoding="utf-8").write(header + text)
    # The people and the animals: World only places them; their bodies are not the city's parts.
    open(os.path.join(out, "server", "Npcs.luau"), "w").write(
        "local N = {}\nfunction N.look(...) return {} end\nfunction N.spawn(...) return nil end\n"
        "function N.say() end\nfunction N.glance() end\nfunction N.start() end\nreturn N\n")
    open(os.path.join(out, "server", "Animals.luau"), "w").write(
        "local A = {}\nsetmetatable(A, { __index = function() return function() return nil end end })\nreturn A\n")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    luau = os.path.abspath(sys.argv[1])
    game = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    with tempfile.TemporaryDirectory() as out:
        prepare(game, out)
        result = subprocess.run([luau, "main.luau"], cwd=out, capture_output=True, text=True, timeout=600)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
