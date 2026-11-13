local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

assert(#process.args == 2, "Usage: lune run scripts/build_rojo.luau INPUT.rbxm OUTPUT.rbxm")
local roots = roblox.deserializeModel(fs.readFile(process.args[1]))
assert(#roots == 1 and roots[1].Name == "Rojo", "Unexpected Rojo model")
assert(roots[1].Version.Value == "7.7.0", "Expected Rojo 7.7.0")

local nodes, modules, converted = 0, 0, 0
local function rebuild(original)
    nodes += 1
    local className = original.ClassName
    if className == "Script" or className == "LocalScript" then
        className = "Folder"
        converted += 1
    end
    assert(className == "Folder" or className == "ModuleScript" or className == "StringValue",
        "Unexpected model class: " .. className)
    local copy = roblox.Instance.new(className)
    copy.Name = original.Name
    if className == "ModuleScript" then
        copy.Source = original.Source
        modules += 1
    elseif className == "StringValue" then
        copy.Value = original.Value
    end
    for _, child in original:GetChildren() do
        rebuild(child).Parent = copy
    end
    return copy
end

local root = rebuild(roots[1])
assert(nodes == 241 and modules == 232 and converted == 1, "Unexpected Rojo model structure")
assert(root.Plugin:IsA("Folder"), "Plugin entrypoint must be inert")
fs.writeFile(process.args[2], roblox.serializeModel({ root }))
print("Built inert Rojo 7.7.0: 241 nodes, 232 unchanged modules, 1 disabled entrypoint")
