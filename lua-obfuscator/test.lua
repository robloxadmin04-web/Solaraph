-- test.lua
local Lexer = require("lexer")

local code = [[
if x == 2 then
  y = a .. b
  z = ...
end
]]

local tokens = Lexer.tokenize(code)

for _, tok in ipairs(tokens) do
  print(string.format("%-12s %s", tok.type, tok.value))
end
