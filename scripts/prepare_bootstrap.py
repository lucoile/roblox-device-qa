#!/usr/bin/env python3
"""Generate bounded Studio MCP bootstrap calls; never changes Studio itself."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

PINNED_BUNDLE_SHA256 = "6b6986bec809f6ef6461df1731d49fc1aaa9242c78c2685751c7b1f17f45b9c7"


def luau_string(text):
    # Long-bracket strings drop a leading newline and normalize CRLF.
    escapes = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r"}
    encoded = []
    for char in text:
        if char in escapes:
            encoded.append(escapes[char])
        elif ord(char) < 32 or ord(char) == 127:
            encoded.append(f"\\{ord(char):03d}")
        else:
            encoded.append(char)
    return '"' + "".join(encoded) + '"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--controller", type=Path, required=True)
    args = parser.parse_args()
    payload = args.bundle.read_bytes()
    if hashlib.sha256(payload).hexdigest() != PINNED_BUNDLE_SHA256:
        raise SystemExit("Bundle checksum differs from the tested Rojo 7.7.0 bundle")
    encoded = base64.b64encode(payload).decode("ascii")
    parts = [encoded[i:i + 180000] for i in range(0, len(encoded), 180000)]
    args.output.mkdir(parents=True, exist_ok=True)
    scripts = []
    scripts.append(("00_begin.luau", '''assert(not game:GetService("RunService"):IsRunning(), "Edit mode required")
assert(not game.CoreGui:FindFirstChild("__CodexRojoBridge"), "A bridge already exists; inspect it before replacing")
local root = Instance.new("Folder")
root.Name = "__CodexRojoBridge"
root.Archivable = false
root:SetAttribute("Owner", "roblox-device-qa-headless-v1")
root.Parent = game.CoreGui
return {created=root:GetFullName(), archivable=root.Archivable}
'''))
    for index, part in enumerate(parts):
        scripts.append((f"{index + 1:02d}_chunk.luau", f'''local root = game.CoreGui.__CodexRojoBridge
assert(root:GetAttribute("Owner") == "roblox-device-qa-headless-v1", "Unexpected bridge owner")
local part = Instance.new("StringValue")
part.Name = "Part{index}"
part.Value = {json.dumps(part)}
part.Parent = root
return #part.Value
'''))
    controller = luau_string(args.controller.read_text())
    scripts.append(("99_finish.luau", f'''local root = game.CoreGui.__CodexRojoBridge
assert(root:GetAttribute("Owner") == "roblox-device-qa-headless-v1", "Unexpected bridge owner")
local parts = {{}}
for i = 0, {len(parts) - 1} do table.insert(parts, root["Part" .. i].Value) end
local bytes = game:GetService("EncodingService"):Base64Decode(buffer.fromstring(table.concat(parts)))
local models = game:GetService("SerializationService"):DeserializeInstancesAsync(bytes)
assert(#models == 1 and models[1].Name == "Rojo", "Unexpected Rojo bundle")
local rojo = models[1]
assert(rojo.Version.Value == "7.7.0", "Unsupported Rojo version")
assert(rojo.Plugin:IsA("Folder"), "Plugin entrypoint must be inert")
for _, item in rojo:GetDescendants() do assert(not item:IsA("BaseScript"), "Unexpected executable script") end
rojo.Archivable = false
rojo.Parent = root
for i = 0, {len(parts) - 1} do root["Part" .. i]:Destroy() end
local module = Instance.new("ModuleScript")
module.Name = "Controller"
module.Source = {controller}
module.Parent = root
local controller = require(module)
for name, method in {{Prepare="prepare", Status="status", Accept="accept", Abort="abort", Disconnect="disconnect"}} do
    local callable = Instance.new("BindableFunction")
    callable.Name = name
    callable.OnInvoke = controller[method]
    callable.Parent = root
end
return controller.status()
'''))
    for name, source in scripts:
        (args.output / name).write_text(source)
    manifest = {"rojoVersion": "7.7.0", "bundleSha256": hashlib.sha256(payload).hexdigest(),
                "steps": [name for name, _ in scripts]}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"steps": len(scripts), "output": str(args.output), "bundleSha256": manifest["bundleSha256"]}))


if __name__ == "__main__":
    main()
