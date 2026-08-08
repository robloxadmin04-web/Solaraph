-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")
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

-- Buong pipeline: source -> tokens -> tree -> source ulit
local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)
local output = Generator.generate(ast)

print("===== ORIHINAL =====")
print(code)
print("===== GENERATED =====")
print(output)

-- ANG TOTOONG TEST: tumatakbo pa ba ang generated code?
print("===== SUBUKANG PATAKBUHIN ANG GENERATED =====")
local fn = load(output)
if fn then
  fn()
  print("(gumana ang generated code!)")
else
  print("MALI: hindi valid ang generated code")
end
