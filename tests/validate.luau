local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local bootstrapDir = process.args[1] or "bootstrap"
local manifest = serde.decode("json", fs.readFile(bootstrapDir .. "/manifest.json"))
for _, name in manifest.steps do
    luau.compile(fs.readFile(bootstrapDir .. "/" .. name))
end
luau.compile(fs.readFile("scripts/Controller.luau"))
local finish = fs.readFile(bootstrapDir .. "/" .. manifest.steps[#manifest.steps])
local controllerLiteral = assert(string.match(finish, "module.Source = ([^\n]+)"), "Controller source missing")
assert(luau.load("return " .. controllerLiteral)() == fs.readFile("scripts/Controller.luau"),
    "Transport changed the Controller source")
local roots = roblox.deserializeModel(fs.readFile("assets/RojoHeadless-7.7.0.rbxm"))
assert(#roots == 1 and roots[1].Name == "Rojo" and roots[1].Version.Value == "7.7.0")
assert(roots[1].Plugin:IsA("Folder"), "Executable plugin entrypoint remains")
local count = 0
for _, item in roots[1]:GetDescendants() do
    assert(not item:IsA("BaseScript"), "Executable script remains")
    if item:IsA("ModuleScript") then count += 1 end
end
assert(count == 232, "Expected all 232 original modules")
assert(#roots[1]:GetDescendants() == 240, "Unexpected hierarchy")

-- Optional original-model comparison proves every retained module is unchanged.
if process.args[2] then
    local original = roblox.deserializeModel(fs.readFile(process.args[2]))[1]
    local function compare(source, built)
        assert(source.Name == built.Name, "Name changed")
        if source:IsA("ModuleScript") then assert(source.Source == built.Source, "Module source changed") end
        if source:IsA("StringValue") then assert(source.Value == built.Value, "Value changed") end
        local expectedClass = if source:IsA("BaseScript") then "Folder" else source.ClassName
        assert(built.ClassName == expectedClass, "Unexpected class transformation")
        local sourceChildren, builtChildren = source:GetChildren(), built:GetChildren()
        assert(#sourceChildren == #builtChildren, "Hierarchy changed")
        for index, child in sourceChildren do compare(child, builtChildren[index]) end
    end
    compare(original, roots[1])
end
print("PASS: controller and " .. #manifest.steps .. " bootstrap steps compile; inert Rojo structure verified")
