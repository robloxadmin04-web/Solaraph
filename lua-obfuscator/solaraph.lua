-- solaraph.lua
-- CLI: lua solaraph.lua <input.lua> [output.lua] [flags]
-- Flags: --no-minify --no-strings --no-numbers --no-rename --no-fold --no-dead --no-flatten

local Lexer     = require("lexer")
local Parser    = require("parser")
local ConstFold = require("constfold")
local DeadCode  = require("deadcode")
local CFlatten  = require("cflatten")
local Renamer   = require("renamer")
local NumEnc    = require("numenc")
local StringEnc = require("stringenc")
local Generator = require("generator")

math.randomseed(os.time())

-- ===== Argumento at flags =====
local inputPath  = arg[1]
local outputPath = nil
local opts = { minify = true, rename = true, strings = true,
               numbers = true, fold = true, dead = true, flatten = true }

for i = 2, #arg do
  local a = arg[i]
  if a == "--no-minify"  then opts.minify  = false
  elseif a == "--no-rename"  then opts.rename  = false
  elseif a == "--no-strings" then opts.strings = false
  elseif a == "--no-numbers" then opts.numbers = false
  elseif a == "--no-fold"    then opts.fold    = false
  elseif a == "--no-dead"    then opts.dead    = false
  elseif a == "--no-flatten" then opts.flatten = false
  elseif a:sub(1, 2) ~= "--" then outputPath = a
  end
end

if not inputPath then
  print("Solaraph - Lua obfuscator")
  print("Gamit: lua solaraph.lua <input.lua> [output.lua] [flags]")
  print("Flags: --no-minify --no-strings --no-numbers --no-rename --no-fold --no-dead --no-flatten")
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

  if opts.fold    then ast = ConstFold.fold(ast) end      -- 1. fold muna (constant expr)
  if opts.flatten then ast = CFlatten.flatten(ast) end    -- 2. control-flow flattening
  if opts.rename  then ast = Renamer.rename(ast) end      -- 3. rename locals
  if opts.numbers then ast = NumEnc.obfuscate(ast) end    -- 4. obfuscate numbers
  if opts.strings then ast = StringEnc.encrypt(ast) end   -- 5. encrypt strings
  if opts.dead    then ast = DeadCode.inject(ast) end     -- 6. dead code (HULI)

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
print("  Passes: fold=" .. tostring(opts.fold)
      .. " flatten=" .. tostring(opts.flatten)
      .. " rename=" .. tostring(opts.rename)
      .. " numbers=" .. tostring(opts.numbers)
      .. " strings=" .. tostring(opts.strings)
      .. " dead=" .. tostring(opts.dead)
      .. " minify=" .. tostring(opts.minify))
