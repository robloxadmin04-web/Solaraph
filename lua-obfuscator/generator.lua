-- generator.lua
-- Code generator: AST -> Lua source. May normal at minify mode.

local Generator = {}
Generator.__index = Generator

function Generator.new(minify)
  local self = setmetatable({}, Generator)
  self.indentLevel = 0
  self.minify = minify or false
  return self
end

-- Sa minify: walang indent. Sa normal: 2 spaces bawat level.
function Generator:indent()
  if self.minify then return "" end
  return string.rep("  ", self.indentLevel)
end

-- Separator ng statements: newline (normal) o space (minify)
function Generator:sep()
  if self.minify then return " " end
  return "\n"
end

-- ============ EXPRESSIONS ============

function Generator:genExpr(node)
  local k = node.kind

  if k == "Number" or k == "String" then
    return node.value

  elseif k == "Literal" then
    return node.value   -- true, false, nil

  elseif k == "Variable" then
    return node.name

  elseif k == "Raw" then
    -- pre-generated na text (galing sa string/number encryption)
    return node.text

  elseif k == "UnaryOp" then
    if node.op == "not" then
      return "not " .. self:genExpr(node.operand)
    else
      return node.op .. self:genExpr(node.operand)
    end

  elseif k == "BinaryOp" then
    return self:genExpr(node.left) .. " " .. node.op .. " " .. self:genExpr(node.right)

  elseif k == "Call" then
    local args = {}
    for _, a in ipairs(node.args) do
      table.insert(args, self:genExpr(a))
    end
    return self:genExpr(node.callee) .. "(" .. table.concat(args, ", ") .. ")"

  elseif k == "Index" then
    if node.field then
      return self:genExpr(node.object) .. "." .. node.field
    else
      return self:genExpr(node.object) .. "[" .. self:genExpr(node.index) .. "]"
    end

  elseif k == "Function" then
    local params = table.concat(node.params, ", ")
    local out = "function(" .. params .. ")" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. self:indent() .. "end"
    return out
  end

  error("Hindi ma-generate ang expression: " .. tostring(k))
end

-- ============ STATEMENTS ============

function Generator:genStatement(node)
  local k = node.kind
  local pad = self:indent()

  if k == "LocalAssignment" then
    if node.value then
      return pad .. "local " .. node.name .. " = " .. self:genExpr(node.value)
    else
      return pad .. "local " .. node.name
    end

  elseif k == "Assignment" then
    return pad .. self:genExpr(node.target) .. " = " .. self:genExpr(node.value)

  elseif k == "LocalFunction" then
    local params = table.concat(node.func.params, ", ")
    local out = pad .. "local function " .. node.name .. "(" .. params .. ")" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.func.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "FunctionDeclaration" then
    local params = table.concat(node.func.params, ", ")
    local out = pad .. "function " .. node.name .. "(" .. params .. ")" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.func.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "If" then
    local out = ""
    for i, cl in ipairs(node.clauses) do
      local kw = (i == 1) and "if" or "elseif"
      out = out .. pad .. kw .. " " .. self:genExpr(cl.cond) .. " then" .. self:sep()
      self.indentLevel = self.indentLevel + 1
      out = out .. self:genBlock(cl.body)
      self.indentLevel = self.indentLevel - 1
    end
    if node.elseBody then
      out = out .. pad .. "else" .. self:sep()
      self.indentLevel = self.indentLevel + 1
      out = out .. self:genBlock(node.elseBody)
      self.indentLevel = self.indentLevel - 1
    end
    out = out .. pad .. "end"
    return out

  elseif k == "While" then
    local out = pad .. "while " .. self:genExpr(node.cond) .. " do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "NumericFor" then
    local header = pad .. "for " .. node.var .. " = "
      .. self:genExpr(node.startExpr) .. ", " .. self:genExpr(node.stopExpr)
    if node.stepExpr then
      header = header .. ", " .. self:genExpr(node.stepExpr)
    end
    local out = header .. " do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "GenericFor" then
    local out = pad .. "for " .. table.concat(node.names, ", ")
      .. " in " .. self:genExpr(node.iter) .. " do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "Return" then
    if #node.values == 0 then
      return pad .. "return"
    end
    local vals = {}
    for _, v in ipairs(node.values) do
      table.insert(vals, self:genExpr(v))
    end
    return pad .. "return " .. table.concat(vals, ", ")

  elseif k == "Break" then
    return pad .. "break"

  elseif k == "CallStatement" then
    return pad .. self:genExpr(node.call)
  end

  error("Hindi ma-generate ang statement: " .. tostring(k))
end

-- Gawing string ang listahan ng statements
function Generator:genBlock(statements)
  local lines = {}
  for _, stmt in ipairs(statements) do
    table.insert(lines, self:genStatement(stmt))
  end
  return table.concat(lines, self:sep()) .. self:sep()
end

-- entry point: generate(ast) o generate(ast, true) para sa minify
function Generator.generate(ast, minify)
  local self = Generator.new(minify)
  return self:genBlock(ast.body)
end

return Generator
