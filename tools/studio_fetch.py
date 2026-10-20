#!/usr/bin/env python3
"""Print a Luau script that syncs Studio (Edit) from the GitHub repo at one commit.

Studio downloads each script's source from raw.githubusercontent.com, so large syncs don't have to
travel through the MCP call. Same Rojo conventions as studio_sync.py. The script turns
HttpService.HttpEnabled on only for the download and restores the previous value afterwards,
then checks every source against the checksum of the local file.
Usage: studio_fetch.py <repo_root> <owner/repo> <commit_sha> [only_path_prefix,...]
"""
import json, os, sys

root, slug, sha = sys.argv[1], sys.argv[2], sys.argv[3]
only = sys.argv[4].split(",") if len(sys.argv) > 4 else None
project = json.load(open(os.path.join(root, "default.project.json")))
entries = []  # (instance path list, class, repo-relative file or None)

def classify(name):
    if name.endswith(".server.luau"): return name[:-12], "Script"
    if name.endswith(".client.luau"): return name[:-12], "LocalScript"
    if name.endswith(".luau"): return name[:-5], "ModuleScript"
    return None, None

def rel(p):
    return os.path.relpath(p, root).replace(os.sep, "/")

def walk_dir(fs_path, inst_path):
    names = sorted(os.listdir(fs_path))
    cls, src = "Folder", None
    for init, c in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
        if init in names:
            cls, src = c, rel(os.path.join(fs_path, init))
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
                entries.append((inst_path + [base], c, rel(p)))

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
                entries.append((path, c, rel(fs)))
        walk_node(child, path)

walk_node(project["tree"], [])

def checksum(s):
    h = 0
    for b in s.encode("utf-8"):
        h = (h * 31 + b) % 2147483647
    return h

rows = []
for path, cls, f in entries:
    if only and not any(".".join(path).startswith(p) for p in only):
        continue
    if f is None:
        continue
    text = open(os.path.join(root, f), encoding="utf-8").read()
    rows.append('\t{ {%s}, "%s", "%s", %d },' % (", ".join('"%s"' % p for p in path), cls, f, checksum(text)))

print('''local HttpService = game:GetService("HttpService")
local BASE = "https://raw.githubusercontent.com/%s/%s/"
local FILES = {
%s
}
local function sum(s) local h = 0 for k = 1, #s do h = (h * 31 + string.byte(s, k)) %% 2147483647 end return h end
local function ensure(path, className)
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
local was = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local fetched, failed = {}, {}
local ok, err = pcall(function()
	for _, row in FILES do
		local body = HttpService:GetAsync(BASE .. row[3], true)
		body = string.gsub(body, "\\r\\n", "\\n")
		if sum(body) ~= row[4] then
			table.insert(failed, row[3] .. " (checksum)")
		else
			fetched[row] = body
		end
	end
end)
HttpService.HttpEnabled = was
if not ok then
	return "download failed: " .. tostring(err)
end
if #failed > 0 then
	return "NOT APPLIED, mismatches: " .. table.concat(failed, ", ")
end
local n = 0
for row, body in fetched do
	ensure(row[1], row[2]).Source = body
	n += 1
end
return ("synced %%d scripts, HttpEnabled restored to %%s"):format(n, tostring(HttpService.HttpEnabled))''' % (slug, sha, "\n".join(rows)))
