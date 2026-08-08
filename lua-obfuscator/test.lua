-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")
local Renamer = require("renamer")
local Generator = require("generator")

local code = [[
local function add(a, b)
  return a + b
end

local total = 0
for i = 1, 10 do
  total = total + i
end

if total > 5 then
  print("malaki: " .. total)
else
  print("maliit")
end
]]

-- Buong pipeline: source -> tokens -> tree -> RENAME -> source
local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)
ast = Renamer.rename(ast)           -- <-- ANG OBFUSCATION
local output = Generator.generate(ast)

print("===== ORIHINAL =====")
print(code)
print("===== OBFUSCATED =====")
print(output)

-- Test: tumatakbo pa ba nang tama?
print("===== PATAKBUHIN ANG OBFUSCATED =====")
local fn = load(output)
if fn then
  fn()
  print("(gumana ang obfuscated code!)")
else
  print("MALI: hindi valid ang obfuscated code")
end
