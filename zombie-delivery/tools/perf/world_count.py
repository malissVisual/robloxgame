#!/usr/bin/env python3
"""The shared preparation of the offline world builds: prepare(game, out) copies tools/perf/world-mock.luau (as
mock.luau) and every server and shared module of the game (their requires rewritten for the Luau CLI, each on the
stand-in's environment) into `out`; the caller then writes its own main.luau and runs it there. Used by
tools/perf/sandbox_count.py (the sandbox's census) and tools/sandbox-map/render.py (the map's export, which
tools/countryside/views.py and tools/lobby/views.py use too).

10.6: its own count of the old city's server/World.luau (world-count.luau, the 6.13.1 performance report) went with
the city; this file keeps its name for the importers above.
"""
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))


def rel(from_dir, target):
    path = os.path.relpath(target, from_dir).replace(os.sep, "/")
    return path if path.startswith(".") else "./" + path


def prepare(game, out, people=False):
    """Copies the stand-in and every server and shared module (their requires rewritten) into `out`.
    8.2: `people` keeps the real server/Npcs.luau (tools/perf/sandbox_count.py counts Danny's body); else a stub."""
    shutil.copy(os.path.join(HERE, "world-mock.luau"), os.path.join(out, "mock.luau"))
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
                # 8.2: the other spellings (server/FurnitureMesh.luau, server/Npcs.luau)
                text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', shared, text)
                text = re.sub(r'require\(game:GetService\("ReplicatedStorage"\):WaitForChild\("Shared"\):WaitForChild\("(\w+)"\)\)', shared, text)

                def parent(m):
                    base = here
                    for _ in range(m.group(1).count(".Parent") - 1):
                        base = os.path.dirname(base)
                    return f'require("{rel(here, os.path.join(base, *m.group(2).strip(".").split(".")))}")'

                text = re.sub(r'require\(script((?:\.Parent)+)((?:\.\w+)+)\)', parent, text)
                # (no new local in the module: its globals come from the stand-in's environment)
                header = f'setfenv(1, require("{rel(here, os.path.join(out, "mock"))}").env)\n'
                open(dst, "w", encoding="utf-8").write(header + text)
    # people=False: stubs for the people and the animals (a count without their bodies).
    if people:
        return
    open(os.path.join(out, "server", "Npcs.luau"), "w").write(
        "local N = {}\nfunction N.look(...) return {} end\nfunction N.spawn(...) return nil end\n"
        "function N.say() end\nfunction N.glance() end\nfunction N.start() end\nreturn N\n")
    open(os.path.join(out, "server", "Animals.luau"), "w").write(
        "local A = {}\nsetmetatable(A, { __index = function() return function() return nil end end })\nreturn A\n")

