-- parser.lua
-- Parser: listahan ng tokens -> AST (tree)
-- Buo na: expressions + lahat ng pangunahing statements.

local Parser = {}
Parser.__index = Parser

local BINARY_PRECEDENCE = {
  ["or"]  = 1,
  ["and"] = 2,
  ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["=="] = 3,
  [".."] = 4,
  ["+"] = 5, ["-"] = 5,
  ["*"] = 6, ["/"] = 6, ["%"] = 6,
}

local UNARY_PRECEDENCE = 7

function Parser.new(tokens)
  local self = setmetatable({}, Parser)
  self.tokens = tokens
  self.pos = 1
  return self
end

function Parser:peek()    return self.tokens[self.pos] end
function Parser:advance()
  local tok = self.tokens[self.pos]
  self.pos = self.pos + 1
  return tok
end

-- Totoo kung ang kasalukuyang token ay tugma sa (kind, value)
function Parser:check(kind, value)
  local tok = self:peek()
  if tok.type ~= kind then return false end
  if value ~= nil and tok.value ~= value then return false end
  return true
end

-- Kung tugma ang kasalukuyang token, kainin ito at magbalik ng true
function Parser:accept(kind, value)
  if self:check(kind, value) then
    self:advance()
    return true
  end
  return false
end

-- Siguraduhing tugma ang token, tapos kainin. Error kung hindi.
function Parser:expect(kind, value)
  local tok = self:peek()
  if tok.type ~= kind or (value ~= nil and tok.value ~= value) then
    error(string.format("Inaasahan '%s' pero nakuha '%s' (linya %s)",
      value or kind, tok.value, tostring(tok.line)))
  end
  return self:advance()
end

-- ============ EXPRESSIONS ============

function Parser:parseUnary()
  local tok = self:peek()
  if (tok.type == "OPERATOR" and (tok.value == "-" or tok.value == "#"))
     or (tok.type == "KEYWORD" and tok.value == "not") then
    local op = self:advance().value
    local operand = self:parseExpression(UNARY_PRECEDENCE)
    return { kind = "UnaryOp", op = op, operand = operand }
  end
  return self:parsePrimary()
end

-- Basahin ang mga argumento ng function call: ( arg1, arg2, ... )
function Parser:parseCallArgs()
  self:expect("OPERATOR", "(")
  local args = {}
  if not self:check("OPERATOR", ")") then
    repeat
      table.insert(args, self:parseExpression(0))
    until not self:accept("OPERATOR", ",")
  end
  self:expect("OPERATOR", ")")
  return args
end

-- Basahin ang primary, tapos ang mga "suffix" nito:
--   function call:  f(...)
--   field access:   t.x
--   index access:   t[expr]
function Parser:parsePrimary()
  local node = self:parseAtom()

  while true do
    -- function call
    if self:check("OPERATOR", "(") then
      local args = self:parseCallArgs()
      node = { kind = "Call", callee = node, args = args }

    -- field access: .name
    elseif self:check("OPERATOR", ".") then
      self:advance()
      local name = self:expect("IDENTIFIER").value
      node = { kind = "Index", object = node, field = name }

    -- index access: [expr]
    elseif self:check("OPERATOR", "[") then
      self:advance()
      local index = self:parseExpression(0)
      self:expect("OPERATOR", "]")
      node = { kind = "Index", object = node, index = index }

    else
      break
    end
  end

  return node
end

-- Ang pinakasimpleng piraso (walang suffix)
function Parser:parseAtom()
  local tok = self:peek()

  if tok.type == "NUMBER" then
    self:advance()
    return { kind = "Number", value = tok.value }

  elseif tok.type == "STRING" then
    self:advance()
    return { kind = "String", value = tok.value }

  elseif tok.type == "KEYWORD" and (tok.value == "true" or tok.value == "false" or tok.value == "nil") then
    self:advance()
    return { kind = "Literal", value = tok.value }

  -- anonymous function: function(...) ... end
  elseif tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    return self:parseFunctionBody(nil)

  elseif tok.type == "IDENTIFIER" then
    self:advance()
    return { kind = "Variable", name = tok.value }

  elseif tok.type == "OPERATOR" and tok.value == "(" then
    self:advance()
    local expr = self:parseExpression(0)
    self:expect("OPERATOR", ")")
    return expr
  end

  error(string.format("Hindi inaasahang token: %s '%s' (linya %s)",
    tok.type, tok.value, tostring(tok.line)))
end

function Parser:parseExpression(minPrec)
  local left = self:parseUnary()

  while true do
    local tok = self:peek()
    local isBinaryOp = (tok.type == "OPERATOR")
                    or (tok.type == "KEYWORD" and (tok.value == "and" or tok.value == "or"))
    if not isBinaryOp then break end

    local prec = BINARY_PRECEDENCE[tok.value]
    if prec == nil or prec < minPrec then break end

    local op = self:advance().value
    local right = self:parseExpression(prec + 1)
    left = { kind = "BinaryOp", op = op, left = left, right = right }
  end

  return left
end

-- ============ STATEMENTS ============

-- Basahin ang listahan ng parameters: ( a, b, ... )
function Parser:parseParams()
  self:expect("OPERATOR", "(")
  local params = {}
  if not self:check("OPERATOR", ")") then
    repeat
      if self:check("OPERATOR", "...") then
        self:advance()
        table.insert(params, "...")
        break
      end
      table.insert(params, self:expect("IDENTIFIER").value)
    until not self:accept("OPERATOR", ",")
  end
  self:expect("OPERATOR", ")")
  return params
end

-- Basahin ang katawan ng function: (params) statements end
-- name = opsyonal (para sa named function)
function Parser:parseFunctionBody(name)
  local params = self:parseParams()
  local body = self:parseBlock()  -- hanggang "end"
  self:expect("KEYWORD", "end")
  return { kind = "Function", name = name, params = params, body = body }
end

-- local x = expr   O   local function f(...) ... end
function Parser:parseLocal()
  self:expect("KEYWORD", "local")

  -- local function f(...)
  if self:check("KEYWORD", "function") then
    self:advance()
    local name = self:expect("IDENTIFIER").value
    local fn = self:parseFunctionBody(name)
    return { kind = "LocalFunction", name = name, func = fn }
  end

  -- local x = expr  (isang variable muna)
  local name = self:expect("IDENTIFIER").value
  local value = nil
  if self:accept("OPERATOR", "=") then
    value = self:parseExpression(0)
  end
  return { kind = "LocalAssignment", name = name, value = value }
end

-- if cond then ... [elseif ...] [else ...] end
function Parser:parseIf()
  self:expect("KEYWORD", "if")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "then")
  local thenBody = self:parseBlock()

  local clauses = { { cond = cond, body = thenBody } }

  -- mga elseif
  while self:check("KEYWORD", "elseif") do
    self:advance()
    local c = self:parseExpression(0)
    self:expect("KEYWORD", "then")
    local b = self:parseBlock()
    table.insert(clauses, { cond = c, body = b })
  end

  -- opsyonal na else
  local elseBody = nil
  if self:accept("KEYWORD", "else") then
    elseBody = self:parseBlock()
  end

  self:expect("KEYWORD", "end")
  return { kind = "If", clauses = clauses, elseBody = elseBody }
end

-- while cond do ... end
function Parser:parseWhile()
  self:expect("KEYWORD", "while")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "While", cond = cond, body = body }
end

-- for i = start, stop [, step] do ... end   (numeric for)
-- for k, v in expr do ... end               (generic for)
function Parser:parseFor()
  self:expect("KEYWORD", "for")
  local firstName = self:expect("IDENTIFIER").value

  -- numeric for: for i = ...
  if self:accept("OPERATOR", "=") then
    local startExpr = self:parseExpression(0)
    self:expect("OPERATOR", ",")
    local stopExpr = self:parseExpression(0)
    local stepExpr = nil
    if self:accept("OPERATOR", ",") then
      stepExpr = self:parseExpression(0)
    end
    self:expect("KEYWORD", "do")
    local body = self:parseBlock()
    self:expect("KEYWORD", "end")
    return { kind = "NumericFor", var = firstName,
             startExpr = startExpr, stopExpr = stopExpr, stepExpr = stepExpr, body = body }
  end

  -- generic for: for k, v in expr do
  local names = { firstName }
  while self:accept("OPERATOR", ",") do
    table.insert(names, self:expect("IDENTIFIER").value)
  end
  self:expect("KEYWORD", "in")
  local iter = self:parseExpression(0)
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "GenericFor", names = names, iter = iter, body = body }
end

-- function name(...) ... end   (named, top-level)
function Parser:parseNamedFunction()
  self:expect("KEYWORD", "function")
  local name = self:expect("IDENTIFIER").value
  local fn = self:parseFunctionBody(name)
  return { kind = "FunctionDeclaration", name = name, func = fn }
end

-- return [expr]
function Parser:parseReturn()
  self:expect("KEYWORD", "return")
  local values = {}
  -- may value ba? (hindi dulo ng block)
  if not self:check("KEYWORD", "end") and not self:check("EOF")
     and not self:check("KEYWORD", "else") and not self:check("KEYWORD", "elseif") then
    repeat
      table.insert(values, self:parseExpression(0))
    until not self:accept("OPERATOR", ",")
  end
  return { kind = "Return", values = values }
end

-- Pumili kung anong statement
function Parser:parseStatement()
  local tok = self:peek()

  if tok.type == "KEYWORD" then
    if tok.value == "local"    then return self:parseLocal() end
    if tok.value == "if"       then return self:parseIf() end
    if tok.value == "while"    then return self:parseWhile() end
    if tok.value == "for"      then return self:parseFor() end
    if tok.value == "function" then return self:parseNamedFunction() end
    if tok.value == "return"   then return self:parseReturn() end
    if tok.value == "break"    then self:advance(); return { kind = "Break" } end
  end

  -- kung nagsisimula sa identifier: alinman sa call o assignment
  if tok.type == "IDENTIFIER" then
    local expr = self:parsePrimary()

    -- assignment: x = expr  (o t.x = expr, t[i] = expr)
    if self:accept("OPERATOR", "=") then
      local value = self:parseExpression(0)
      return { kind = "Assignment", target = expr, value = value }
    end

    -- kung hindi assignment, dapat function call statement ito
    if expr.kind == "Call" then
      return { kind = "CallStatement", call = expr }
    end

    error(string.format("Hindi wastong statement (linya %s)", tostring(tok.line)))
  end

  error(string.format("Hindi kilalang statement: %s '%s' (linya %s)",
    tok.type, tok.value, tostring(tok.line)))
end

-- Basahin ang blocke ng statements hanggang sa dulong keyword
function Parser:parseBlock()
  local statements = {}
  while true do
    local tok = self:peek()
    if tok.type == "EOF"
       or (tok.type == "KEYWORD" and (tok.value == "end" or tok.value == "else"
           or tok.value == "elseif")) then
      break
    end
    local stmt = self:parseStatement()
    table.insert(statements, stmt)
    -- ang return/break ay dapat huling statement sa block
    if stmt.kind == "Return" or stmt.kind == "Break" then
      break
    end
  end
  return statements
end

function Parser:parseProgram()
  local body = self:parseBlock()
  self:expect("EOF")
  return { kind = "Program", body = body }
end

function Parser.parse(tokens)
  local self = Parser.new(tokens)
  return self:parseProgram()
end

return Parser
