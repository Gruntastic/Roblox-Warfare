#!/usr/bin/env python3
"""Generate a small Luau script that patches already-synced Studio scripts in place.

Pasting whole files through MCP is expensive, so this sends only changed hunks: each hunk is an
(old, new) pair whose old text is unique in the base source; the Luau side applies it with a plain
find/replace and verifies a checksum of the result.
Usage: studio_patch.py <repo_root> <base_dir> <out.luau> <file> [file...]
  base_dir mirrors repo paths and holds the sources as last synced to Studio; it is updated after
  generation, so run the emitted script before generating the next patch.
"""
import difflib, json, os, shutil, sys

root, base, out, files = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
project = json.load(open(os.path.join(root, "default.project.json")))

def mounts(node, inst):
    for k, v in node.items():
        if k.startswith("$"):
            continue
        if "$path" in v:
            yield v["$path"].rstrip("/"), inst + [k]
        yield from mounts(v, inst + [k])

def inst_path(rel):
    for fs, inst in mounts(project["tree"], []):
        if rel == fs or rel.startswith(fs + "/"):
            parts = rel[len(fs):].strip("/").split("/") if rel != fs else []
            name = parts[-1] if parts else os.path.basename(fs)
            for suffix in (".server.luau", ".client.luau", ".luau"):
                if name.endswith(suffix):
                    name = name[: -len(suffix)]
                    break
            if name == "init":
                return inst + parts[:-1]
            return inst + parts[:-1] + [name] if parts else inst
    raise SystemExit("not under a Rojo mount: " + rel)

def checksum(s):
    h = 0
    for b in s.encode():
        h = (h * 31 + b) % 2147483647
    return h

def lstr(s):
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    return "[" + "=" * level + "[\n" + s + "]" + "=" * level + "]"

def hunks(a, b):
    """(old, new) pairs in bottom-up order. Each old text is unique in `a`; hunks whose expanded
    context would overlap are merged, so applying them bottom-up never touches edited text."""
    al, bl = a.splitlines(keepends=True), b.splitlines(keepends=True)
    spans = []  # [lo, hi, j_lo, j_hi] in line indices
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, al, bl, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        lo, hi = i1, i2
        while True:
            old = "".join(al[lo:hi])
            if old and a.count(old) == 1:
                break
            if lo == 0 and hi == len(al):
                break
            lo, hi = max(lo - 1, 0), min(hi + 1, len(al))
        # the context lines map 1:1 onto b around the changed region
        jlo, jhi = j1 - (i1 - lo), j2 + (hi - i2)
        if spans and lo <= spans[-1][1]:
            spans[-1][1], spans[-1][3] = max(spans[-1][1], hi), max(spans[-1][3], jhi)
        else:
            spans.append([lo, hi, jlo, jhi])
    res = []
    for lo, hi, jlo, jhi in reversed(spans):
        res.append(("".join(al[lo:hi]), "".join(bl[jlo:jhi])))
    return res

def simulate(a, pairs):
    for o, n in pairs:
        i = a.find(o)
        if i < 0:
            return None
        a = a[:i] + n + a[i + len(o):]
    return a

lua = ["local results = {}"]
for rel in files:
    new = open(os.path.join(root, rel)).read()
    old = open(os.path.join(base, rel)).read()
    path = inst_path(rel)
    lua.append("do")
    lua.append("local inst = game:GetService(%s)" % json.dumps(path[0]))
    for p in path[1:]:
        lua.append("inst = inst:FindFirstChild(%s) or error(%s)" % (json.dumps(p), json.dumps("missing " + ".".join(path))))
    lua.append("local src = inst.Source")
    pairs = hunks(old, new)
    if simulate(old, pairs) != new or sum(len(o) + len(n) for o, n in pairs) > len(new):
        lua.append("src = %s" % lstr(new))  # patching would not reproduce the file, or costs more
        print("full source:", rel)
    else:
        for o, n in pairs:
            lua.append("do local o, n = %s, %s" % (lstr(o), lstr(n)))
            lua.append("local i = string.find(src, o, 1, true) or error(%s)" % json.dumps("hunk not found in " + rel))
            lua.append("src = string.sub(src, 1, i - 1) .. n .. string.sub(src, i + #o) end")
    lua.append("local h = 0 for k = 1, #src do h = (h * 31 + string.byte(src, k)) % 2147483647 end")
    lua.append("if h ~= %d then error(%s) end" % (checksum(new), json.dumps("checksum mismatch for " + rel)))
    lua.append("inst.Source = src table.insert(results, %s) end" % json.dumps(rel))
    os.makedirs(os.path.dirname(os.path.join(base, rel)), exist_ok=True)
    shutil.copyfile(os.path.join(root, rel), os.path.join(base, rel))
lua.append('return "patched: " .. table.concat(results, ", ")')
open(out, "w").write("\n".join(lua) + "\n")
print("wrote", out, os.path.getsize(out), "bytes")
