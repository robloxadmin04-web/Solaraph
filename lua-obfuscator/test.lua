-- test.lua
local Lexer = require("lexer")

local code = [[
local x = 1 + 2   -- ito ay comment, dapat mawala
local name = "Solaraph"
local msg = 'hello world'
print(x)
]]

local tokens = Lexer.tokenize(code)

for _, tok in ipairs(tokens) do
  print(string.format("%-12s %s", tok.type, tok.value))
end
