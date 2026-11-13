local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

for index, case in serde.decode("json", fs.readFile(process.args[1])) do
    local observed = luau.load("return " .. case.literal)()
    assert(observed == case.value, "Luau string roundtrip mismatch in case " .. tostring(index))
end
print("Luau string content preserved")
