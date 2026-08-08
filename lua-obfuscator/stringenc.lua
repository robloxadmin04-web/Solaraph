-- stringenc.lua
-- Obfuscation pass: string encryption.
-- Ang bawat "text" ay ginagawang tawag sa decoder function.

local StringEnc = {}

local XOR_KEY = 0x5A   -- simpleng key (pwedeng gawing random mamaya)

-- Kunin ang tunay na laman ng string mula sa raw token value.
-- Ang node.value ay may kasamang quotes pa (hal. '"hello"'), tanggalin.
local function unquote(raw)
  local first = raw:sub(1, 1)
  if first == '"' or first == "'" then
    return raw:sub(2, #raw - 1)
  end
  -- long string [[ ... ]] — hanapin ang unang [ ... [ at ] ... ]
  local level = raw:match("^%[(=*)%[")
  if level then
    local open = #("[" .. level .. "[")
    return raw:sub(open + 1, #raw - open)
  end
  return raw
end

-- I-encode ang isang string sa listahan ng XOR-ed bytes
local function encode(str)
  local bytes = {}
  for i = 1, #str do
    local b = string.byte(str, i)
    table.insert(bytes, tostring(b ~ XOR_KEY))  -- XOR sa Lua 5.3+
  end
  return table.concat(bytes, ",")
end

-- Baguhin ang tree: palitan ang bawat String node ng Call sa decoder
local function transformExpr(node)
  if node == nil then return end
  local k = node.kind

  if k == "String" then
    local raw = unquote(node.value)
    local encoded = encode(raw)
    -- gawing: __dec({b1,b2,...})
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
  elseif k == "Index" then
    transformExpr(node.object)
    if node.index then transformExpr(node.index) end
  elseif k == "Function" then
    transformBlock(node.body)
  end
end

function transformBlock(statements)
  for _, stmt in ipairs(statements) do
    transformStatement(stmt)
  end
end

function transformStatement(node)
  local k = node.kind
  if k == "LocalAssignment" then transformExpr(node.value)
  elseif k == "Assignment" then transformExpr(node.value); transformExpr(node.target)
  elseif k == "LocalFunction" then transformBlock(node.func.body)
  elseif k == "FunctionDeclaration" then transformBlock(node.func.body)
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do
      transformExpr(cl.cond); transformBlock(cl.body)
    end
    if node.elseBody then transformBlock(node.elseBody) end
  elseif k == "While" then transformExpr(node.cond); transformBlock(node.body)
  elseif k == "NumericFor" then
    transformExpr(node.startExpr); transformExpr(node.stopExpr)
    if node.stepExpr then transformExpr(node.stepExpr) end
    transformBlock(node.body)
  elseif k == "GenericFor" then transformExpr(node.iter); transformBlock(node.body)
  elseif k == "Return" then
    for _, v in ipairs(node.values) do transformExpr(v) end
  elseif k == "CallStatement" then transformExpr(node.call)
  end
end

-- Ang decoder function na idadagdag sa itaas ng output
function StringEnc.prelude()
  return
    "local function __dec(t)\n" ..
    "  local s = {}\n" ..
    "  for i = 1, #t do s[i] = string.char(t[i] ~ " .. XOR_KEY .. ") end\n" ..
    "  return table.concat(s)\n" ..
    "end\n"
end

function StringEnc.encrypt(ast)
  transformBlock(ast.body)
  return ast
end

return StringEnc
