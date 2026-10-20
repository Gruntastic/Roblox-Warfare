#!/usr/bin/env python3
"""Check that the scripts in a live Studio session match the repo.

Usage:
  studio_verify.py <repo_root> lua            -> prints a Luau snippet; run it in the Edit datamodel
  studio_verify.py <repo_root> check <json>   -> compares the snippet's JSON output with the repo
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))

root, mode = sys.argv[1], sys.argv[2]
project = json.load(open(os.path.join(root, "default.project.json")))

def checksum(s):
    h = 0
    for b in s.encode():
        h = (h * 31 + b) % 2147483647
    return h

def classify(name):
    for suffix in (".server.luau", ".client.luau", ".luau"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return None

expected = {}
def walk(fs, inst):
    if os.path.isdir(fs):
        for n in sorted(os.listdir(fs)):
            p = os.path.join(fs, n)
            if n.startswith("init.") and classify(n):
                expected[".".join(inst)] = checksum(open(p).read())
            elif os.path.isdir(p):
                walk(p, inst + [n])
            elif classify(n):
                expected[".".join(inst + [classify(n)])] = checksum(open(p).read())
    else:
        expected[".".join(inst)] = checksum(open(fs).read())

def mounts(node, inst):
    for k, v in node.items():
        if k.startswith("$"):
            continue
        if "$path" in v:
            walk(os.path.join(root, v["$path"]), inst + [k])
        mounts(v, inst + [k])
mounts(project["tree"], [])

if mode == "lua":
    roots = sorted({k.split(".")[0] + "." + k.split(".")[1] for k in expected})
    print("local out = {}")
    print("local function sum(s) local h = 0 for k = 1, #s do h = (h * 31 + string.byte(s, k)) % 2147483647 end return h end")
    for r in roots:
        svc, top = r.split(".")
        print('do local top = game:GetService("%s"):FindFirstChild("%s") if top then' % (svc, top))
        print("  for _, d in { top, table.unpack(top:GetDescendants()) } do")
        print('    if d:IsA("LuaSourceContainer") then out[d:GetFullName()] = sum((d :: any).Source) end')
        print("  end end end")
    print('return game:GetService("HttpService"):JSONEncode(out)')
else:
    actual = json.loads(open(sys.argv[3]).read())
    bad = 0
    for k, v in sorted(expected.items()):
        a = actual.get(k)
        if a != v:
            bad += 1
            print(("MISSING " if a is None else "DIFFERS ") + k)
    extra = sorted(set(actual) - set(expected))
    for k in extra:
        print("EXTRA   " + k)
    print("%d scripts checked, %d mismatched, %d extra" % (len(expected), bad, len(extra)))
