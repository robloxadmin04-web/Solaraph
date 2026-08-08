-- constfold.lua
-- Obfuscation pass: constant folding.
-- Pre-computes constant sub-expressions sa AST bago i-emit.
-- Halimbawa: (2 + 3) * 4  ->  20 ;  "a" .. "b"  ->  "ab" ;  not true  ->  false
-- Tugma sa AST ng parser.lua (Number.value/String.value ay STRING na raw text).
--
-- IMPORTANTE: tumatakbo ito BAGO ang numenc/stringenc. Pagkatapos i-fold,
-- ang numenc pa rin ang mag-o-obfuscate ng mga resulting number, kaya
-- walang mawawalang seguridad — nadadagdagan lang ang resistensya sa pag-decompile.

local ConstFold = {}

-- ---------- helpers para sa literal detection ----------

-- Balik: totoong Lua number kung ang node ay integer/float Number literal, else nil.
local function numValue(node)
  if node.kind ~= "Number" then return nil end
  local n = tonumber(node.value)
  return n
end

-- Balik: totoong string content (unquoted) kung simpleng quoted String literal, else nil.
-- Iniiwasan ang long-bracket [[...]] at anumang may escape para 'di masira ang semantics.
local function strValue(node)
  if node.kind ~= "String" then return nil end
  local raw = node.value
  local first = raw:sub(1, 1)
  if first ~= '"' and first ~= "'" then return nil end        -- long bracket: laktawan
  local inner = raw:sub(2, #raw - 1)
  if inner:find("\\", 1, true) then return nil end            -- may escape: laktawan (safe)
  return inner
end

-- Gawing Number node ang isang resultang number (nag-e-emit ng valid Lua literal text).
local function makeNumber(node, n)
  node.kind = "Number"
  -- integer -> walang decimal; float -> gamitin ang %.17g para eksakto
  if n == math.floor(n) and math.abs(n) < 1e15 then
    node.value = string.format("%d", n)
  else
    node.value = string.format("%.17g", n)
  end
  -- linisin ang ibang field
  node.op, node.left, node.right, node.operand = nil, nil, nil, nil
end

local function makeString(node, s)
  node.kind = "String"
  node.value = string.format("%q", s)   -- ligtas na quoting + escape
  node.op, node.left, node.right, node.operand = nil, nil, nil, nil
end

local function makeLiteral(node, boolValue)
  node.kind = "Literal"
  node.value = boolValue and "true" or "false"
  node.op, node.left, node.right, node.operand = nil, nil, nil, nil
end

local function litBool(node)
  if node.kind ~= "Literal" then return nil end
  if node.value == "true" then return true end
  if node.value == "false" then return false end
  return nil   -- nil literal: 'di boolean
end

-- ---------- folding ng expressions ----------

local foldBlock, foldStatement

local function foldExpr(node)
  if node == nil then return end
  local k = node.kind

  if k == "UnaryOp" then
    foldExpr(node.operand)
    local op = node.op
    if op == "-" then
      local n = numValue(node.operand)
      if n ~= nil then makeNumber(node, -n) end
    elseif op == "not" then
      local b = litBool(node.operand)
      if b ~= nil then makeLiteral(node, not b)
      elseif node.operand.kind == "Number" or node.operand.kind == "String" then
        makeLiteral(node, false)   -- number/string ay truthy -> not = false
      end
    end
    -- '#' (length): 'di ligtas i-fold nang statically, iwan

  elseif k == "BinaryOp" then
    foldExpr(node.left)
    foldExpr(node.right)
    local op = node.op
    local ln, rn = numValue(node.left), numValue(node.right)
    local ls, rs = strValue(node.left), strValue(node.right)

    -- arithmetic (integer/float)
    if ln ~= nil and rn ~= nil then
      if     op == "+" then makeNumber(node, ln + rn)
      elseif op == "-" then makeNumber(node, ln - rn)
      elseif op == "*" then makeNumber(node, ln * rn)
      elseif op == "/" then if rn ~= 0 then makeNumber(node, ln / rn) end
      elseif op == "%" then if rn ~= 0 then makeNumber(node, ln % rn) end
      elseif op == "==" then makeLiteral(node, ln == rn)
      elseif op == "~=" then makeLiteral(node, ln ~= rn)
      elseif op == "<"  then makeLiteral(node, ln <  rn)
      elseif op == ">"  then makeLiteral(node, ln >  rn)
      elseif op == "<=" then makeLiteral(node, ln <= rn)
      elseif op == ">=" then makeLiteral(node, ln >= rn)
      end

    -- string concat
    elseif ls ~= nil and rs ~= nil and op == ".." then
      makeString(node, ls .. rs)

    -- string comparison
    elseif ls ~= nil and rs ~= nil then
      if     op == "==" then makeLiteral(node, ls == rs)
      elseif op == "~=" then makeLiteral(node, ls ~= rs)
      end
    end

  elseif k == "Call" then
    foldExpr(node.callee)
    for _, a in ipairs(node.args) do foldExpr(a) end
  elseif k == "MethodCall" then
    foldExpr(node.object)
    for _, a in ipairs(node.args) do foldExpr(a) end
  elseif k == "Index" then
    foldExpr(node.object)
    if node.index then foldExpr(node.index) end
  elseif k == "Table" then
    for _, f in ipairs(node.fields) do
      if f.kind == "keyed" then foldExpr(f.key) end
      foldExpr(f.value)
    end
  elseif k == "Function" then
    foldBlock(node.body)
  end
  -- Number, String, Literal, Variable, Vararg, Raw: walang gagawin
end

foldStatement = function(node)
  local k = node.kind
  if k == "LocalAssignment" then
    if node.values then for _, v in ipairs(node.values) do foldExpr(v) end end
  elseif k == "Assignment" then
    for _, v in ipairs(node.values) do foldExpr(v) end
    for _, t in ipairs(node.targets) do foldExpr(t) end
  elseif k == "LocalFunction" then foldBlock(node.func.body)
  elseif k == "FunctionDeclaration" then foldBlock(node.func.body)
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do foldExpr(cl.cond); foldBlock(cl.body) end
    if node.elseBody then foldBlock(node.elseBody) end
  elseif k == "While" then foldExpr(node.cond); foldBlock(node.body)
  elseif k == "Repeat" then foldBlock(node.body); foldExpr(node.cond)
  elseif k == "Do" then foldBlock(node.body)
  elseif k == "NumericFor" then
    foldExpr(node.startExpr); foldExpr(node.stopExpr)
    if node.stepExpr then foldExpr(node.stepExpr) end
    foldBlock(node.body)
  elseif k == "GenericFor" then
    for _, it in ipairs(node.iters) do foldExpr(it) end
    foldBlock(node.body)
  elseif k == "Return" then for _, v in ipairs(node.values) do foldExpr(v) end
  elseif k == "CallStatement" then foldExpr(node.call)
  end
end

foldBlock = function(statements)
  for _, stmt in ipairs(statements) do foldStatement(stmt) end
end

function ConstFold.fold(ast)
  foldBlock(ast.body)
  return ast
end

return ConstFold
