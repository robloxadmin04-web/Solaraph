-- test.lua
local Lexer = require("lexer")

local code = [[
local x = 1 + 2
print(x)
]]

local tokens = Lexer.tokenize(code)

for _, tok in ipairs(tokens) do
  print(string.format("%-12s %s", tok.type, tok.value))
end
