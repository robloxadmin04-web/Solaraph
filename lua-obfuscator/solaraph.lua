-- solaraph.lua
-- CLI: lua solaraph.lua <input.lua> [output.lua] [flags]
-- Flags: --no-minify  --no-strings  --no-numbers  --no-rename

local Lexer     = require("lexer")
local Parser    = require("parser")
local Renamer   = require("renamer")
local NumEnc    = require("numenc")
local StringEnc = require("stringenc")
local Generator = require("generator")

math.randomseed(os.time())

-- ===== Argumento at flags =====
local inputPath  = arg[1]
local outputPath = nil
local opts = { minify = true, rename = true, strings = true, numbers = true }

for i = 2, #arg do
  local a = arg[i]
  if a == "--no-minify"  then opts.minify  = false
  elseif a == "--no-rename"  then opts.rename  = false
  elseif a == "--no-strings" then opts.strings = false
  elseif a == "--no-numbers" then opts.numbers = false
  elseif a:sub(1, 2) ~= "--" then outputPath = a
  end
end

if not inputPath then
  print("Solaraph - Lua obfuscator")
  print("Gamit: lua solaraph.lua <input.lua> [output.lua] [flags]")
  print("Flags: --no-minify  --no-strings  --no-numbers  --no-rename")
  os.exit(1)
end

if not outputPath then
  outputPath = inputPath:gsub("%.lua$", "") .. ".obf.lua"
end

-- ===== Basahin =====
local f = io.open(inputPath, "r")
if not f then
  print("MALI: hindi mabuksan ang file: " .. inputPath)
  os.exit(1)
end
local source = f:read("*a")
f:close()

-- ===== Obfuscate =====
local ok, result = pcall(function()
  local tokens = Lexer.tokenize(source)
  local ast    = Parser.parse(tokens)

  if opts.rename  then ast = Renamer.rename(ast) end
  if opts.numbers then ast = NumEnc.obfuscate(ast) end
  if opts.strings then ast = StringEnc.encrypt(ast) end

  local body = Generator.generate(ast, opts.minify)
  if opts.strings then
    return StringEnc.prelude() .. body
  end
  return body
end)

if not ok then
  print("MALI habang nag-o-obfuscate:")
  print("  " .. tostring(result))
  print("(Baka may syntax na hindi pa suportado ng parser.)")
  os.exit(1)
end

-- ===== Isulat =====
local out = io.open(outputPath, "w")
if not out then
  print("MALI: hindi maisulat ang output: " .. outputPath)
  os.exit(1)
end
out:write(result)
out:close()

-- ===== Ulat =====
print("Solaraph - tapos!")
print("  Input:  " .. inputPath  .. " (" .. #source .. " bytes)")
print("  Output: " .. outputPath .. " (" .. #result .. " bytes)")
print("  Passes: rename=" .. tostring(opts.rename)
      .. " numbers=" .. tostring(opts.numbers)
      .. " strings=" .. tostring(opts.strings)
      .. " minify=" .. tostring(opts.minify))