#!/usr/bin/env python3
"""
6.24: every require in src points at a module that exists where Rojo puts it.

Builds the place's script tree the way tools/rojo-sync.js (and Rojo) build it from default.project.json (src/shared →
ReplicatedStorage.Shared, src/server → ServerScriptService.Server, src/client →
StarterPlayer.StarterPlayerScripts.Client; X.luau a ModuleScript "X", X.server.luau a Script, X.client.luau a
LocalScript, a folder a Folder, init.luau makes the folder the module), then reads every require(...) in src and
resolves its path statically: script / script.Parent / .Name / :WaitForChild("Name") / :FindFirstChild("Name") /
["Name"], game:GetService("Service"), and the locals bound to such a path above it (Shared, Server, Client,
ReplicatedStorage …). A require whose path is not a ModuleScript in the tree fails the check (a module that moved,
e.g. 6.22's KitArt from the server to Shared, or a typo), with where a module of that name does live. A require of a
value it cannot follow (a variable holding a module found at run time) is counted, not checked. Modules that require
each other while they load (not inside a function: by the indentation) fail too: Roblox stops with "Requested module
was required recursively". So does a client's or a shared module's require of a server module (the clients never
get ServerScriptService).

Also checks that the repository root's default.project.json maps the same folders (the owner syncs either).

    python3 zombie-delivery/tools/check-requires.py [a project file]      (tests/run_tests.py runs it too)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)  # zombie-delivery/
REPO = os.path.dirname(GAME)

CLASS_BY_SUFFIX = ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".server.lua", "Script"),
                   (".client.lua", "LocalScript"), (".luau", "ModuleScript"), (".lua", "ModuleScript"))


class Node:
    def __init__(self, name, cls, parent=None, file=None):
        self.name, self.cls, self.parent, self.file = name, cls, parent, file
        self.children = {}

    def path(self):
        parts, node = [], self
        while node.parent is not None:
            parts.append(node.name)
            node = node.parent
        return ".".join(reversed(parts))

    def add(self, child):
        child.parent = self
        self.children[child.name] = child
        return child


def from_disk(disk, name, files):
    """A file or folder on disk as a Node (Rojo's rules); files: disk path → its Node."""
    if os.path.isfile(disk):
        for suffix, cls in CLASS_BY_SUFFIX:
            if disk.endswith(suffix):
                node = Node(name, cls, file=disk)
                files[disk] = node
                return node
        return None
    entries = sorted(e for e in os.listdir(disk) if not e.startswith("."))
    init = next((e for e in entries if re.fullmatch(r"init(\.server|\.client)?\.luau?", e)), None)
    cls = "Folder"
    if init:
        cls = next(c for s, c in CLASS_BY_SUFFIX if ("x" + init[4:]).endswith(s))
    node = Node(name, cls, file=os.path.join(disk, init) if init else None)
    if init:
        files[os.path.join(disk, init)] = node
    for entry in entries:
        if entry == init:
            continue
        child_disk = os.path.join(disk, entry)
        child_name = entry
        if os.path.isfile(child_disk):
            suffix = next((s for s, _ in CLASS_BY_SUFFIX if entry.endswith(s)), None)
            if suffix is None:
                continue
            child_name = entry[: -len(suffix)]
        child = from_disk(child_disk, child_name, files)
        if child is not None:
            node.add(child)
    return node


def from_project(project_file):
    """The DataModel of a project file; returns (root, files: disk path → Node, mapped: instance path → disk path)."""
    project = json.load(open(project_file, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(project_file))
    files, mapped = {}, {}

    def build(spec, name, at):
        node = Node(name, spec.get("$className", name))
        if "$path" in spec:
            disk = os.path.normpath(os.path.join(base, spec["$path"]))
            built = from_disk(disk, name, files)
            if built is not None:
                node.cls, node.file, node.children = built.cls, built.file, built.children
                for child in node.children.values():
                    child.parent = node
            mapped[".".join(at)] = disk
        for key, child in spec.items():
            if not key.startswith("$") and isinstance(child, dict):
                node.add(build(child, key, at + [key]))
        return node

    root = build(project["tree"], "game", [])
    return root, files, mapped


# ── resolving an expression to a node ─────────────────────────────────────────
STEP = re.compile(r"""\s*(?:
      \.\s*(?P<dot>[A-Za-z_]\w*)
    | :\s*(?:WaitForChild|FindFirstChild)\s*\(\s*(?P<q>["'])(?P<call>[^"']+)(?P=q)\s*(?:,[^)]*)?\)
    | \[\s*(?P<q2>["'])(?P<idx>[^"']+)(?P=q2)\s*\]
)""", re.X)
BASE = re.compile(r"""\s*(?:
      game\s*:\s*GetService\s*\(\s*["'](?P<svc>\w+)["']\s*\)
    | (?P<name>[A-Za-z_]\w*)
)""", re.X)


def resolve(expr, script, root, scope):
    """The node an instance expression names, "dynamic" when it starts from something we cannot follow, or
    (None, where) when a step leads nowhere."""
    m = BASE.match(expr)
    if not m:
        return "dynamic"
    pos = m.end()
    if m.group("svc"):
        node = root.children.get(m.group("svc"))
        if node is None:
            node = Node(m.group("svc"), m.group("svc"), root)  # a service we do not sync (Players …)
            node.foreign = True
    else:
        name = m.group("name")
        if name == "script":
            node = script
        elif name == "game":
            node = root
        elif name in scope:
            node = scope[name]
            if node == "dynamic":
                return "dynamic"
        else:
            return "dynamic"
    while True:
        step = STEP.match(expr, pos)
        if not step:
            break
        pos = step.end()
        key = step.group("dot") or step.group("call") or step.group("idx")
        if step.group("dot") == "Parent":
            node = node.parent
        elif getattr(node, "foreign", False):
            return "dynamic"
        elif step.group("dot") in ("Name", "ClassName"):
            return "dynamic"
        elif key in node.children:
            node = node.children[key]
        else:
            return (None, f"{node.path() or 'game'} has no child {key!r}")
        if node is None:
            return (None, "past the top of the place")
    if expr[pos:].strip():
        return "dynamic"  # something we do not model follows (a method call, an index by variable)
    return node


def expression_after(text, start):
    """The balanced argument text from `start` (just after "require(") up to its closing parenthesis."""
    depth, i = 1, start
    while i < len(text) and depth:
        c = text[i]
        if c in "\"'":
            j = text.index(c, i + 1)
            i = j + 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    return text[start:i - 1]


def strip_comments(text):
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


BIND = re.compile(r"\blocal\s+([A-Za-z_]\w*)\s*(?::\s*[A-Za-z_][\w.]*\??\s*)?=\s*([^\n;]+)")


def eager(lines, index):
    """Does the require on line `index` run when its module loads (not inside a function)? By the indentation: the
    lines it is nested in (each less indented than the one inside) up to the top level; inside a function if one of
    them opens one. (A top-level do / if / for block runs at load.)"""
    def indent(line):
        return len(line) - len(line.lstrip("\t "))
    level = indent(lines[index])
    for j in range(index - 1, -1, -1):
        if level == 0:
            break
        line = lines[j]
        if not line.strip() or indent(line) >= level:
            continue
        level = indent(line)
        if re.search(r"\bfunction\b", line):
            return False
    return True


def cycles(graph):
    """The loops of modules that require each other while they load (Roblox stops with "Requested module was
    required recursively")."""
    found, state, stack = [], {}, []

    def visit(node):
        state[node] = 1
        stack.append(node)
        for nxt in sorted(graph.get(node, ()), key=lambda n: n.path()):
            if state.get(nxt) == 1:
                found.append(stack[stack.index(nxt):] + [nxt])
            elif nxt not in state:
                visit(nxt)
        stack.pop()
        state[node] = 2

    for node in sorted(graph, key=lambda n: n.path()):
        if node not in state:
            visit(node)
    return found


def check(project_file):
    root, files, mapped = from_project(project_file)
    bad, checked, dynamic = [], 0, 0
    graph = {}  # module → the modules it requires while it loads
    for disk, script in sorted(files.items()):
        text = strip_comments(open(disk, encoding="utf-8").read())
        lines = text.split("\n")
        scope_points = []  # (offset, name, value)
        for m in BIND.finditer(text):
            value = m.group(2).strip()
            if value.startswith("require"):
                continue
            target = resolve(value, script, root, dict((n, v) for _, n, v in scope_points))
            if isinstance(target, Node):
                scope_points.append((m.start(), m.group(1), target))
            elif target == "dynamic" and re.match(r"(script|game|[A-Za-z_]\w*)\b", value) and re.search(r"WaitForChild|GetService|\.Parent|script", value):
                scope_points.append((m.start(), m.group(1), "dynamic"))
        for m in re.finditer(r"\brequire\s*\(", text):
            arg = expression_after(text, m.end()).strip()
            arg = re.sub(r"\s*::.*$", "", arg)
            scope = {}
            for offset, name, value in scope_points:
                if offset < m.start():
                    scope[name] = value
            target = resolve(arg, script, root, scope)
            line = text.count("\n", 0, m.start()) + 1
            where = f"{os.path.relpath(disk, REPO)}:{line}"
            if target == "dynamic":
                dynamic += 1
                continue
            checked += 1
            if isinstance(target, tuple):
                name = re.findall(r"[\"']?(\w+)[\"']?\)?\s*$", arg)
                hint = ""
                if name:
                    homes = [n.path() for n in files.values() if n.name == name[-1] and n.cls == "ModuleScript"]
                    if homes:
                        hint = f"; a module {name[-1]!r} is at {', '.join(sorted(homes))}"
                bad.append(f"{where}: require({arg}): {target[1]}{hint}")
            elif target.cls != "ModuleScript":
                bad.append(f"{where}: require({arg}) is a {target.cls} ({target.path()}), not a ModuleScript")
            elif target.path().startswith(("ServerScriptService.", "ServerStorage.")) and script.path().startswith(("ReplicatedStorage.", "StarterPlayer.", "StarterGui.", "ReplicatedFirst.")):
                bad.append(f"{where}: require({arg}): {target.path()} is the server's, a client never sees it")
            elif eager(lines, line - 1):
                graph.setdefault(script, set()).add(target)
    for loop in cycles(graph):
        bad.append("modules require each other while they load: " + " → ".join(n.path() for n in loop))
    return bad, checked, dynamic, len(files), mapped


def main():
    ok = True
    game_project = sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, "default.project.json")
    bad, checked, dynamic, scripts, mapped = check(game_project)
    for line in bad:
        print("FAIL  " + line)
    print(f"== requires: {checked} requires in {scripts} scripts resolve to a ModuleScript in the Rojo tree, no loop"
          + (f" ({dynamic} found at run time, not checked)" if dynamic else "") if not bad else f"== requires: {len(bad)} problem(s) in {checked} requires")
    ok = ok and not bad
    root_project = os.path.join(REPO, "default.project.json")
    if len(sys.argv) <= 1 and os.path.exists(root_project):
        _, _, _, _, root_mapped = check(root_project)
        same = {k: os.path.normpath(v) for k, v in mapped.items()} == {k: os.path.normpath(v) for k, v in root_mapped.items()}
        print("== projects: " + ("the root default.project.json maps the same folders" if same else
              f"FAIL the root default.project.json maps {root_mapped}, zombie-delivery's {mapped}"))
        ok = ok and same
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
