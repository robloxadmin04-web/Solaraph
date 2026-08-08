-- renamer.lua
-- Obfuscation pass 1: variable renaming (scope-aware)
-- Pinapalitan ang lahat ng LOCAL variable ng walang-kwentang pangalan.
-- Hindi ginagalaw ang globals/built-ins (print, pairs, atbp).

local Renamer = {}
Renamer.__index = Renamer

function Renamer.new()
  local self = setmetatable({}, Renamer)
  self.counter = 0          -- pambilang para sa bagong pangalan
  -- scopes: stack ng mapa. Bawat scope may sariling { orihinal = bago }
  self.scopes = { {} }      -- global scope muna
  return self
end

-- Gumawa ng bagong walang-kwentang pangalan: _v1, _v2, ...
function Renamer:freshName()
  self.counter = self.counter + 1
  return "_v" .. self.counter
end

-- Pumasok sa bagong scope (hal. loob ng function/loop)
function Renamer:pushScope()
  table.insert(self.scopes, {})
end

-- Umalis sa scope
function Renamer:popScope()
  table.remove(self.scopes)
end

-- Itala ang bagong local: orihinal -> bagong pangalan (sa kasalukuyang scope)
function Renamer:declare(name)
  local newName = self:freshName()
  self.scopes[#self.scopes][name] = newName
  return newName
end

-- Hanapin ang bagong pangalan ng isang variable.
-- Titingnan mula sa pinakaloob na scope palabas.
-- Kung wala sa kahit anong scope -> global/built-in, ibalik nil.
function Renamer:resolve(name)
  for i = #self.scopes, 1, -1 do
    local mapped = self.scopes[i][name]
    if mapped then return mapped end
  end
  return nil  -- global, huwag galawin
end

-- ============ TREE WALKING ============

-- Baguhin ang isang expression node (in-place)
function Renamer:transformExpr(node)
  if node == nil then return end
  local k = node.kind

  if k == "Variable" then
    local mapped = self:resolve(node.name)
    if mapped then
      node.name = mapped   -- local, palitan
    end
    -- kung nil (global), iwanan lang

  elseif k == "UnaryOp" then
    self:transformExpr(node.operand)

  elseif k == "BinaryOp" then
    self:transformExpr(node.left)
    self:transformExpr(node.right)

  elseif k == "Call" then
    self:transformExpr(node.callee)
    for _, a in ipairs(node.args) do self:transformExpr(a) end

  elseif k == "Index" then
    self:transformExpr(node.object)
    if node.index then self:transformExpr(node.index) end
    -- node.field (.name) ay hindi variable, huwag galawin

  elseif k == "Function" then
    -- anonymous function: bagong scope para sa params
    self:pushScope()
    for i, p in ipairs(node.params) do
      if p ~= "..." then
        node.params[i] = self:declare(p)
      end
    end
    self:transformBlock(node.body)
    self:popScope()
  end
  -- Number, String, Literal: walang gagawin
end

-- Baguhin ang isang statement node
function Renamer:transformStatement(node)
  local k = node.kind

  if k == "LocalAssignment" then
    -- IMPORTANTE: i-transform muna ang value BAGO i-declare ang bagong pangalan.
    -- Kasi sa `local x = x + 1`, ang `x` sa kanan ay ang LUMANG x (o global).
    self:transformExpr(node.value)
    node.name = self:declare(node.name)

  elseif k == "Assignment" then
    self:transformExpr(node.value)
    self:transformExpr(node.target)

  elseif k == "LocalFunction" then
    -- Ang pangalan ng function ay declared sa KASALUKUYANG scope (para ma-recursion).
    node.name = self:declare(node.name)
    node.func.name = node.name
    -- bagong scope para sa params + body
    self:pushScope()
    for i, p in ipairs(node.func.params) do
      if p ~= "..." then
        node.func.params[i] = self:declare(p)
      end
    end
    self:transformBlock(node.func.body)
    self:popScope()

  elseif k == "FunctionDeclaration" then
    -- global function name: huwag palitan (pwedeng tinatawag mula labas)
    self:pushScope()
    for i, p in ipairs(node.func.params) do
      if p ~= "..." then
        node.func.params[i] = self:declare(p)
      end
    end
    self:transformBlock(node.func.body)
    self:popScope()

  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do
      self:transformExpr(cl.cond)
      self:pushScope()
      self:transformBlock(cl.body)
      self:popScope()
    end
    if node.elseBody then
      self:pushScope()
      self:transformBlock(node.elseBody)
      self:popScope()
    end

  elseif k == "While" then
    self:transformExpr(node.cond)
    self:pushScope()
    self:transformBlock(node.body)
    self:popScope()

  elseif k == "NumericFor" then
    -- ang start/stop/step ay sa LABAS na scope
    self:transformExpr(node.startExpr)
    self:transformExpr(node.stopExpr)
    if node.stepExpr then self:transformExpr(node.stepExpr) end
    -- bagong scope: ang loop variable ay local sa loob
    self:pushScope()
    node.var = self:declare(node.var)
    self:transformBlock(node.body)
    self:popScope()

  elseif k == "GenericFor" then
    self:transformExpr(node.iter)
    self:pushScope()
    for i, n in ipairs(node.names) do
      node.names[i] = self:declare(n)
    end
    self:transformBlock(node.body)
    self:popScope()

  elseif k == "Return" then
    for _, v in ipairs(node.values) do self:transformExpr(v) end

  elseif k == "CallStatement" then
    self:transformExpr(node.call)

  elseif k == "Break" then
    -- walang gagawin
  end
end

function Renamer:transformBlock(statements)
  for _, stmt in ipairs(statements) do
    self:transformStatement(stmt)
  end
end

-- Pangunahing entry point
function Renamer.rename(ast)
  local self = Renamer.new()
  self:transformBlock(ast.body)
  return ast
end

return Renamer