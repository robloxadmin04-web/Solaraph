-- renamer.lua
-- Obfuscation pass 1: scope-aware variable renaming.
-- Updated para sa bagong AST: tables, methods, multiple assignment.

local Renamer = {}
Renamer.__index = Renamer

function Renamer.new()
  local self = setmetatable({}, Renamer)
  self.counter = 0
  self.scopes = { {} }   -- global scope
  return self
end

function Renamer:freshName()
  self.counter = self.counter + 1
  return "_v" .. self.counter
end

function Renamer:pushScope() table.insert(self.scopes, {}) end
function Renamer:popScope()  table.remove(self.scopes) end

function Renamer:declare(name)
  local newName = self:freshName()
  self.scopes[#self.scopes][name] = newName
  return newName
end

function Renamer:resolve(name)
  for i = #self.scopes, 1, -1 do
    local mapped = self.scopes[i][name]
    if mapped then return mapped end
  end
  return nil
end

-- ============ EXPRESSIONS ============

function Renamer:transformExpr(node)
  if node == nil then return end
  local k = node.kind

  if k == "Variable" then
    local mapped = self:resolve(node.name)
    if mapped then node.name = mapped end

  elseif k == "UnaryOp" then
    self:transformExpr(node.operand)

  elseif k == "BinaryOp" then
    self:transformExpr(node.left)
    self:transformExpr(node.right)

  elseif k == "Call" then
    self:transformExpr(node.callee)
    for _, a in ipairs(node.args) do self:transformExpr(a) end

  elseif k == "MethodCall" then
    self:transformExpr(node.object)   -- ang method name mismo ay hindi variable
    for _, a in ipairs(node.args) do self:transformExpr(a) end

  elseif k == "Index" then
    self:transformExpr(node.object)
    if node.index then self:transformExpr(node.index) end
    -- node.field (.name) ay hindi variable

  elseif k == "Table" then
    for _, f in ipairs(node.fields) do
      if f.kind == "keyed" then self:transformExpr(f.key) end
      self:transformExpr(f.value)
      -- f.name (named field) ay key sa table, HINDI variable — huwag galawin
    end

  elseif k == "Function" then
    self:pushScope()
    for i, p in ipairs(node.params) do
      if p ~= "..." then node.params[i] = self:declare(p) end
    end
    self:transformBlock(node.body)
    self:popScope()
  end
  -- Number, String, Literal, Vararg, Raw: walang gagawin
end

-- ============ STATEMENTS ============

function Renamer:transformStatement(node)
  local k = node.kind

  if k == "LocalAssignment" then
    -- i-transform muna ang values BAGO i-declare (ang kanan ay lumang scope)
    if node.values then
      for _, v in ipairs(node.values) do self:transformExpr(v) end
    end
    for i, name in ipairs(node.names) do
      node.names[i] = self:declare(name)
    end

  elseif k == "Assignment" then
    for _, v in ipairs(node.values) do self:transformExpr(v) end
    for _, t in ipairs(node.targets) do self:transformExpr(t) end

  elseif k == "LocalFunction" then
    node.name = self:declare(node.name)
    node.func.name = node.name
    self:pushScope()
    for i, p in ipairs(node.func.params) do
      if p ~= "..." then node.func.params[i] = self:declare(p) end
    end
    self:transformBlock(node.func.body)
    self:popScope()

  elseif k == "FunctionDeclaration" then
    -- ang target (a.b.c o obj) ay pwedeng may local base — i-resolve
    self:transformExpr(node.target)
    self:pushScope()
    for i, p in ipairs(node.func.params) do
      if p ~= "..." then node.func.params[i] = self:declare(p) end
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

  elseif k == "Repeat" then
    -- IMPORTANTE: sa repeat, ang until-cond ay nakikita ang locals ng body,
    -- kaya iisang scope lang ang body at cond.
    self:pushScope()
    self:transformBlock(node.body)
    self:transformExpr(node.cond)
    self:popScope()

  elseif k == "Do" then
    self:pushScope()
    self:transformBlock(node.body)
    self:popScope()

  elseif k == "NumericFor" then
    self:transformExpr(node.startExpr)
    self:transformExpr(node.stopExpr)
    if node.stepExpr then self:transformExpr(node.stepExpr) end
    self:pushScope()
    node.var = self:declare(node.var)
    self:transformBlock(node.body)
    self:popScope()

  elseif k == "GenericFor" then
    for _, it in ipairs(node.iters) do self:transformExpr(it) end
    self:pushScope()
    for i, n in ipairs(node.names) do node.names[i] = self:declare(n) end
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

function Renamer.rename(ast)
  local self = Renamer.new()
  self:transformBlock(ast.body)
  return ast
end

return Renamer