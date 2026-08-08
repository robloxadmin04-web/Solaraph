-- generator.lua
-- Code generator: AST -> Lua source. Normal at minify mode.
-- FIX: nag-wrap ng parentheses ang BinaryOp/UnaryOp para hindi masira ang
-- precedence kapag sinusundan ng index/method/call, hal. (a - b).Magnitude

local Generator = {}
Generator.__index = Generator

function Generator.new(minify)
  local self = setmetatable({}, Generator)
  self.indentLevel = 0
  self.minify = minify or false
  return self
end

function Generator:indent()
  if self.minify then return "" end
  return string.rep("  ", self.indentLevel)
end

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
    return node.value
  elseif k == "Variable" then
    return node.name
  elseif k == "Vararg" then
    return "..."
  elseif k == "Raw" then
    return node.text

  elseif k == "UnaryOp" then
    -- i-paren para ligtas sa precedence:  (-x).foo ,  (not a) and b
    if node.op == "not" then
      return "(not " .. self:genExpr(node.operand) .. ")"
    else
      return "(" .. node.op .. self:genExpr(node.operand) .. ")"
    end

  elseif k == "BinaryOp" then
    -- i-paren para ligtas sa precedence:  (a - b).Magnitude ,  (a + b) * c
    return "(" .. self:genExpr(node.left) .. " " .. node.op .. " " .. self:genExpr(node.right) .. ")"

  elseif k == "Call" then
    local args = {}
    for _, a in ipairs(node.args) do table.insert(args, self:genExpr(a)) end
    return self:genExpr(node.callee) .. "(" .. table.concat(args, ", ") .. ")"

  elseif k == "MethodCall" then
    local args = {}
    for _, a in ipairs(node.args) do table.insert(args, self:genExpr(a)) end
    return self:genExpr(node.object) .. ":" .. node.method
      .. "(" .. table.concat(args, ", ") .. ")"

  elseif k == "Index" then
    if node.field then
      return self:genExpr(node.object) .. "." .. node.field
    else
      return self:genExpr(node.object) .. "[" .. self:genExpr(node.index) .. "]"
    end

  elseif k == "Table" then
    local parts = {}
    for _, f in ipairs(node.fields) do
      if f.kind == "array" then
        table.insert(parts, self:genExpr(f.value))
      elseif f.kind == "named" then
        table.insert(parts, f.name .. " = " .. self:genExpr(f.value))
      elseif f.kind == "keyed" then
        table.insert(parts, "[" .. self:genExpr(f.key) .. "] = " .. self:genExpr(f.value))
      end
    end
    return "{" .. table.concat(parts, ", ") .. "}"

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
    local names = table.concat(node.names, ", ")
    if node.values and #node.values > 0 then
      local vals = {}
      for _, v in ipairs(node.values) do table.insert(vals, self:genExpr(v)) end
      return pad .. "local " .. names .. " = " .. table.concat(vals, ", ")
    else
      return pad .. "local " .. names
    end

  elseif k == "Assignment" then
    local targets = {}
    for _, t in ipairs(node.targets) do table.insert(targets, self:genExpr(t)) end
    local vals = {}
    for _, v in ipairs(node.values) do table.insert(vals, self:genExpr(v)) end
    return pad .. table.concat(targets, ", ") .. " = " .. table.concat(vals, ", ")

  elseif k == "LocalFunction" then
    local params = table.concat(node.func.params, ", ")
    local out = pad .. "local function " .. node.name .. "(" .. params .. ")" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.func.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "FunctionDeclaration" then
    -- ang target ay Index/Variable; kung method, tanggalin ang implicit self sa display
    local params = node.func.params
    if node.isMethod then
      -- ang unang param ay "self" (implicit sa : syntax) â€” tanggalin sa output
      local shown = {}
      for i = 2, #params do table.insert(shown, params[i]) end
      -- gamitin ang : syntax: function obj:method(...)
      local obj = self:genExpr(node.target.object)
      local out = pad .. "function " .. obj .. ":" .. node.target.field
        .. "(" .. table.concat(shown, ", ") .. ")" .. self:sep()
      self.indentLevel = self.indentLevel + 1
      out = out .. self:genBlock(node.func.body)
      self.indentLevel = self.indentLevel - 1
      out = out .. pad .. "end"
      return out
    else
      local out = pad .. "function " .. self:genExpr(node.target)
        .. "(" .. table.concat(params, ", ") .. ")" .. self:sep()
      self.indentLevel = self.indentLevel + 1
      out = out .. self:genBlock(node.func.body)
      self.indentLevel = self.indentLevel - 1
      out = out .. pad .. "end"
      return out
    end

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

  elseif k == "Repeat" then
    local out = pad .. "repeat" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "until " .. self:genExpr(node.cond)
    return out

  elseif k == "Do" then
    local out = pad .. "do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "NumericFor" then
    local header = pad .. "for " .. node.var .. " = "
      .. self:genExpr(node.startExpr) .. ", " .. self:genExpr(node.stopExpr)
    if node.stepExpr then header = header .. ", " .. self:genExpr(node.stepExpr) end
    local out = header .. " do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "GenericFor" then
    local iters = {}
    for _, it in ipairs(node.iters) do table.insert(iters, self:genExpr(it)) end
    local out = pad .. "for " .. table.concat(node.names, ", ")
      .. " in " .. table.concat(iters, ", ") .. " do" .. self:sep()
    self.indentLevel = self.indentLevel + 1
    out = out .. self:genBlock(node.body)
    self.indentLevel = self.indentLevel - 1
    out = out .. pad .. "end"
    return out

  elseif k == "Return" then
    if #node.values == 0 then return pad .. "return" end
    local vals = {}
    for _, v in ipairs(node.values) do table.insert(vals, self:genExpr(v)) end
    return pad .. "return " .. table.concat(vals, ", ")

  elseif k == "Break" then
    return pad .. "break"

  elseif k == "CallStatement" then
    return pad .. self:genExpr(node.call)
  end

  error("Hindi ma-generate ang statement: " .. tostring(k))
end

function Generator:genBlock(statements)
  local lines = {}
  for _, stmt in ipairs(statements) do
    table.insert(lines, self:genStatement(stmt))
  end
  return table.concat(lines, self:sep()) .. self:sep()
end

function Generator.generate(ast, minify)
  local self = Generator.new(minify)
  return self:genBlock(ast.body)
end

return Generator
