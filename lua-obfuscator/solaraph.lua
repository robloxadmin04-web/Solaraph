-- solaraph.lua
-- CLI: lua solaraph.lua <input.lua> [output.lua] [--no-minify]
--
-- Halimbawa:
--   lua solaraph.lua script.lua
--   lua solaraph.lua script.lua out.lua
--   lua solaraph.lua script.lua out.lua --no-minify

local Lexer     = require("lexer")
local Parser    = require("parser")
local Renamer   = require("renamer")
local Generator = require("generator")

-- ===== Basahin ang mga argumento =====
local inputPath  = arg[1]
local outputPath = arg[2]
local minify     = true

-- suriin ang mga flag
for i = 2, #arg do
  if arg[i] == "--no-minify" then minify = false end
end
-- kung ang arg[2] ay isang flag, walang output path na binigay
if outputPath == "--no-minify" then outputPath = nil end

-- ===== Tulong kung walang input =====
if not inputPath then
  print("Solaraph — Lua obfuscator")
  print("Gamit: lua solaraph.lua <input.lua> [output.lua] [--no-minify]")
  os.exit(1)
end

-- default na output path: <input>.obf.lua
if not outputPath then
  outputPath = inputPath:gsub("%.lua$", "") .. ".obf.lua"
end

-- ===== Basahin ang input =====
local f = io.open(inputPath, "r")
if not f then
  print("MALI: hindi mabuksan ang file: " .. inputPath)
  os.exit(1)
end
local source = f:read("*a")
f:close()

-- ===== Obfuscate (may error handling) =====
local ok, result = pcall(function()
  local tokens = Lexer.tokenize(source)
  local ast    = Parser.parse(tokens)
  ast = Renamer.rename(ast)
  return Generator.generate(ast, minify)
end)

if not ok then
  print("MALI habang nag-o-obfuscate:")
  print("  " .. tostring(result))
  print("(Baka may syntax na hindi pa suportado ng parser.)")
  os.exit(1)
end

-- ===== Isulat ang output =====
local out = io.open(outputPath, "w")
if not out then
  print("MALI: hindi maisulat ang output: " .. outputPath)
  os.exit(1)
end
out:write(result)
out:close()

-- ===== Ulat =====
local origSize = #source
local newSize  = #result
print("Solaraph — tapos!")
print("  Input:  " .. inputPath  .. " (" .. origSize .. " bytes)")
print("  Output: " .. outputPath .. " (" .. newSize  .. " bytes)")
print("  Minify: " .. tostring(minify))