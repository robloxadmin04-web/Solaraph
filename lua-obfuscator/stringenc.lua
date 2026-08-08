-- stringenc.lua
-- Obfuscation pass: string encryption (XOR + decoder prelude).
-- Updated para sa bagong AST: tables, methods, multiple values.
-- Luau/Roblox-safe: bit32.bxor sa halip na "~" (Lua 5.1 base, walang "~" operator).

local StringEnc = {}

local XOR_KEY = 0x5A

local function unquote(raw)
  local first = raw:sub(1, 1)
  if first == '"' or first == "'" then
    return raw:sub(2, #raw - 1)
  end
  local level = raw:match("^%[(=*)%[")
  if level then
    local open = #("[" .. level .. "[")
    return raw:sub(open + 1, #raw - open)
  end
  return raw
end

-- Luau/Lua5.1-safe XOR: gamitin ang bit32.bxor sa halip na "~"
local function bxor(a, b)
  if bit32 and bit32.bxor then
    return bit32.bxor(a, b)
  end
  -- fallback para sa plain Lua 5.1 (walang bit32) o kung saan naka-off
  local result, bitval = 0, 1
  while a > 0 or b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then result = result + bitval end
    a = (a - abit) / 2
    b = (b - bbit) / 2
    bitval = bitval * 2
  end
  return result
end

local function encode(str)
  local bytes = {}
  for i = 1, #str do
    local b = string.byte(str, i)
    table.insert(bytes, tostring(bxor(b, XOR_KEY)))
  end
  return table.concat(bytes, ",")
end

local transformBlock, transformStatement

local function transformExpr(node)
  if node == nil then return end
  local k = node.kind

  if k == "String" then
    local raw = unquote(node.value)
    local encoded = encode(raw)
    node.kind = "Call"
    node.callee = { kind = "Variable", name = "__dec" }
    node.args = { { kind = "Raw", text = "{" .. encoded .. "}" } }
    node.value = nil

  elseif k == "UnaryOp" then
    transformExpr(node.operand)
  elseif k == "BinaryOp" then
    transformExpr(node.left); transformExpr(node.right)
  elseif k == "Call" then
    transformExpr(node.callee)
    for _, a in ipairs(node.args) do transformExpr(a) end
  elseif k == "MethodCall" then
    transformExpr(node.object)
    for _, a in ipairs(node.args) do transformExpr(a) end
  elseif k == "Index" then
    transformExpr(node.object)
    if node.index then transformExpr(node.index) end
  elseif k == "Table" then
    for _, f in ipairs(node.fields) do
      if f.kind == "keyed" then transformExpr(f.key) end
      transformExpr(f.value)
    end
  elseif k == "Function" then
    transformBlock(node.body)
  end
end

transformStatement = function(node)
  local k = node.kind
  if k == "LocalAssignment" then
    if node.values then for _, v in ipairs(node.values) do transformExpr(v) end end
  elseif k == "Assignment" then
    for _, v in ipairs(node.values) do transformExpr(v) end
    for _, t in ipairs(node.targets) do transformExpr(t) end
  elseif k == "LocalFunction" then transformBlock(node.func.body)
  elseif k == "FunctionDeclaration" then transformBlock(node.func.body)
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do
      transformExpr(cl.cond); transformBlock(cl.body)
    end
    if node.elseBody then transformBlock(node.elseBody) end
  elseif k == "While" then transformExpr(node.cond); transformBlock(node.body)
  elseif k == "Repeat" then transformBlock(node.body); transformExpr(node.cond)
  elseif k == "Do" then transformBlock(node.body)
  elseif k == "NumericFor" then
    transformExpr(node.startExpr); transformExpr(node.stopExpr)
    if node.stepExpr then transformExpr(node.stepExpr) end
    transformBlock(node.body)
  elseif k == "GenericFor" then
    for _, it in ipairs(node.iters) do transformExpr(it) end
    transformBlock(node.body)
  elseif k == "Return" then
    for _, v in ipairs(node.values) do transformExpr(v) end
  elseif k == "CallStatement" then transformExpr(node.call)
  end
end

transformBlock = function(statements)
  for _, stmt in ipairs(statements) do transformStatement(stmt) end
end

function StringEnc.prelude()
  return
    "local __bxor = (bit32 and bit32.bxor) or (bit and bit.bxor) or function(a,b)\n" ..
    "  local r,c=0,1\n" ..
    "  while a>0 or b>0 do\n" ..
    "    local x,y=a%2,b%2\n" ..
    "    if x~=y then r=r+c end\n" ..
    "    a=(a-x)/2; b=(b-y)/2; c=c*2\n" ..
    "  end\n" ..
    "  return r\n" ..
    "end\n" ..
    "local function __dec(t)\n" ..
    "  local s = {}\n" ..
    "  for i = 1, #t do s[i] = string.char(__bxor(t[i], " .. XOR_KEY .. ")) end\n" ..
    "  return table.concat(s)\n" ..
    "end\n"
end

function StringEnc.encrypt(ast)
  transformBlock(ast.body)
  return ast
end

return StringEnc
