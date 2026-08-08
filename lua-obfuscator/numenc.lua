-- numenc.lua
-- Obfuscation pass: number obfuscation (integer -> (a + b)).
-- Updated para sa bagong AST: tables, methods, multiple values.

local NumEnc = {}

local function obfuscateNumber(node)
  local n = tonumber(node.value)
  if n == nil or n ~= math.floor(n) or node.value:match("[%.xXeEpP]") then
    return  -- iwanan ang float/hex/scientific
  end
  local a = math.random(0, math.max(n, 1))
  local b = n - a
  node.kind = "Raw"
  node.text = "(" .. a .. " + " .. b .. ")"
  node.value = nil
end

local transformBlock, transformStatement

local function transformExpr(node)
  if node == nil then return end
  local k = node.kind
  if k == "Number" then obfuscateNumber(node)
  elseif k == "UnaryOp" then transformExpr(node.operand)
  elseif k == "BinaryOp" then transformExpr(node.left); transformExpr(node.right)
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
  elseif k == "Function" then transformBlock(node.body)
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
    for _, cl in ipairs(node.clauses) do transformExpr(cl.cond); transformBlock(cl.body) end
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
  elseif k == "Return" then for _, v in ipairs(node.values) do transformExpr(v) end
  elseif k == "CallStatement" then transformExpr(node.call)
  end
end

transformBlock = function(statements)
  for _, stmt in ipairs(statements) do transformStatement(stmt) end
end

function NumEnc.obfuscate(ast)
  transformBlock(ast.body)
  return ast
end

return NumEnc