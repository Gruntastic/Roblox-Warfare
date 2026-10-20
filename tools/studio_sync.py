#!/usr/bin/env python3
"""Generate Luau chunks that mirror the Rojo source tree into a live Studio session.

Used when Rojo's live-sync plugin is unavailable (e.g. driving Studio through MCP).
Follows Rojo's file conventions: init.server/init.client/init.luau directories, *.server.luau,
*.client.luau and *.luau files. Output: one .luau file per chunk in the given out dir.
Usage: studio_sync.py <repo_root> <out_dir> [max_chunk_bytes]
"""
import json, os, sys

root, out = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 90000
project = json.load(open(os.path.join(root, "default.project.json")))

entries = []  # (instance_path list, class, source or None)

def classify(name):
    if name.endswith(".server.luau"): return name[:-12], "Script"
    if name.endswith(".client.luau"): return name[:-12], "LocalScript"
    if name.endswith(".luau"): return name[:-5], "ModuleScript"
    return None, None

def walk_dir(fs_path, inst_path):
    names = sorted(os.listdir(fs_path))
    cls, src = "Folder", None
    for init, c in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
        if init in names:
            cls, src = c, open(os.path.join(fs_path, init)).read()
    entries.append((inst_path, cls, src))
    for n in names:
        p = os.path.join(fs_path, n)
        if n.startswith("init."):
            continue
        if os.path.isdir(p):
            walk_dir(p, inst_path + [n])
        else:
            base, c = classify(n)
            if c:
                entries.append((inst_path + [base], c, open(p).read()))

def walk_node(node, inst_path):
    for key, child in node.items():
        if key.startswith("$"):
            continue
        path = inst_path + [key]
        if "$path" in child:
            fs = os.path.join(root, child["$path"])
            if os.path.isdir(fs):
                walk_dir(fs, path)
            else:
                base, c = classify(os.path.basename(fs))
                entries.append((path, c, open(fs).read()))
        walk_node(child, path)

walk_node(project["tree"], [])

def lstr(s):
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + s + "]" + eq + "]"

HEADER = '''local function ensure(path, className)
	local parent = game:GetService(path[1])
	for i = 2, #path do
		local name = path[i]
		local child = parent:FindFirstChild(name)
		local want = if i == #path then className else "Folder"
		if child and i == #path and child.ClassName ~= className then
			child:Destroy()
			child = nil
		end
		if not child then
			child = Instance.new(want)
			child.Name = name
			child.Parent = parent
		end
		parent = child
	end
	return parent
end
local n = 0
'''

os.makedirs(out, exist_ok=True)
chunks, cur = [], HEADER
for path, cls, src in entries:
    if len(path) < 2:
        continue
    stmt = "do local inst = ensure(%s, %s)\n" % ("{" + ",".join(json.dumps(p) for p in path) + "}", json.dumps(cls))
    if src is not None:
        stmt += "inst.Source = " + lstr(src) + "\n"
    stmt += "n += 1 end\n"
    if len(cur) + len(stmt) > limit and cur != HEADER:
        chunks.append(cur + "return n\n")
        cur = HEADER
    cur += stmt
chunks.append(cur + "return n\n")
for i, c in enumerate(chunks):
    open(os.path.join(out, "chunk_%02d.luau" % i), "w").write(c)
print("%d instances, %d chunks, sizes: %s" % (len(entries), len(chunks), [len(c) for c in chunks]))
