-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")
local Generator = require("generator")

local code = [[
local t = { 1, 2, name = "Solaraph", [10] = "ten" }

function t:greet(prefix)
  return prefix .. self.name
end

local obj = {}
obj.count = 0
local a, b = 1, 2
a, b = b, a

for k, v in pairs(t) do
  print(k, v)
end

print(t:greet("Hi, "))
]]

local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)
local output = Generator.generate(ast)

print("===== GENERATED =====")
print(output)

print("===== PATAKBUHIN =====")
local fn = load(output)
if fn then
  fn()
  print("(gumana!)")
else
  print("MALI: hindi valid ang generated code")
end
