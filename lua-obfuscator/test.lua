-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")
local Renamer = require("renamer")
local NumEnc = require("numenc")
local StringEnc = require("stringenc")
local Generator = require("generator")

math.randomseed(os.time())

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

-- BUONG PIPELINE
local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)

ast = Renamer.rename(ast)          -- 1. variable renaming
ast = NumEnc.obfuscate(ast)        -- 2. number obfuscation
ast = StringEnc.encrypt(ast)       -- 3. string encryption

-- 4. minify (true = compact)
local body = Generator.generate(ast, true)
local output = StringEnc.prelude() .. body

print("===== ORIHINAL =====")
print(code)
print("===== OBFUSCATED =====")
print(output)

print("===== PATAKBUHIN ANG OBFUSCATED =====")
local fn = load(output)
if fn then
  fn()
  print("(gumana ang obfuscated code!)")
else
  print("MALI: hindi valid ang obfuscated code")
end
