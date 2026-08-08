-- parser.lua
-- Parser: tokens -> AST. Buo: expressions + statements + tables + methods + multi-assign.

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

function Parser:check(kind, value)
  local tok = self:peek()
  if tok.type ~= kind then return false end
  if value ~= nil and tok.value ~= value then return false end
  return true
end

function Parser:accept(kind, value)
  if self:check(kind, value) then self:advance(); return true end
  return false
end

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

-- ( arg1, arg2, ... )  o  "string"  o  {table}  bilang call args
function Parser:parseCallArgs()
  -- string call: f"text"  ->  f("text")
  if self:check("STRING") then
    local s = self:advance()
    return { { kind = "String", value = s.value } }
  end
  -- table call: f{...}  ->  f({...})
  if self:check("OPERATOR", "{") then
    return { self:parseTable() }
  end
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

-- Table constructor: { 1, 2, x = 3, [k] = v }
function Parser:parseTable()
  self:expect("OPERATOR", "{")
  local fields = {}
  while not self:check("OPERATOR", "}") do
    if self:check("OPERATOR", "[") then
      -- [expr] = value
      self:advance()
      local key = self:parseExpression(0)
      self:expect("OPERATOR", "]")
      self:expect("OPERATOR", "=")
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "keyed", key = key, value = val })

    elseif self:check("IDENTIFIER") and self.tokens[self.pos + 1]
           and self.tokens[self.pos + 1].type == "OPERATOR"
           and self.tokens[self.pos + 1].value == "=" then
      -- name = value
      local name = self:advance().value
      self:advance()  -- "="
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "named", name = name, value = val })

    else
      -- array-style: value lang
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "array", value = val })
    end

    -- separator: , o ;
    if not (self:accept("OPERATOR", ",") or self:accept("OPERATOR", ";")) then
      break
    end
  end
  self:expect("OPERATOR", "}")
  return { kind = "Table", fields = fields }
end

function Parser:parsePrimary()
  local node = self:parseAtom()

  while true do
    if self:check("OPERATOR", "(") or self:check("STRING") or self:check("OPERATOR", "{") then
      -- function call (tandaan: string/table call din)
      -- pero huwag ituring na call ang { kung table literal ang gusto — safe dito kasi
      -- suffix position: t{...} ay call, {...} bilang atom ay nasa parseAtom na.
      if self:check("STRING") or self:check("OPERATOR", "{") then
        -- string/table call sa suffix position lang kung may callee na
        local args = self:parseCallArgs()
        node = { kind = "Call", callee = node, args = args }
      else
        local args = self:parseCallArgs()
        node = { kind = "Call", callee = node, args = args }
      end

    elseif self:check("OPERATOR", ".") then
      self:advance()
      local name = self:expect("IDENTIFIER").value
      node = { kind = "Index", object = node, field = name }

    elseif self:check("OPERATOR", "[") then
      self:advance()
      local index = self:parseExpression(0)
      self:expect("OPERATOR", "]")
      node = { kind = "Index", object = node, index = index }

    elseif self:check("OPERATOR", ":") then
      -- method call: obj:method(args)
      self:advance()
      local method = self:expect("IDENTIFIER").value
      local args = self:parseCallArgs()
      node = { kind = "MethodCall", object = node, method = method, args = args }

    else
      break
    end
  end

  return node
end

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

  elseif tok.type == "OPERATOR" and tok.value == "..." then
    self:advance()
    return { kind = "Vararg" }

  elseif tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    return self:parseFunctionBody(nil)

  elseif tok.type == "OPERATOR" and tok.value == "{" then
    return self:parseTable()

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

function Parser:parseFunctionBody(name)
  local params = self:parseParams()
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "Function", name = name, params = params, body = body }
end

-- local a, b, c = expr1, expr2   (multiple)
function Parser:parseLocal()
  self:expect("KEYWORD", "local")

  if self:check("KEYWORD", "function") then
    self:advance()
    local name = self:expect("IDENTIFIER").value
    local fn = self:parseFunctionBody(name)
    return { kind = "LocalFunction", name = name, func = fn }
  end

  -- listahan ng pangalan
  local names = { self:expect("IDENTIFIER").value }
  while self:accept("OPERATOR", ",") do
    table.insert(names, self:expect("IDENTIFIER").value)
  end

  local values = {}
  if self:accept("OPERATOR", "=") then
    repeat
      table.insert(values, self:parseExpression(0))
    until not self:accept("OPERATOR", ",")
  end

  return { kind = "LocalAssignment", names = names, values = values }
end

function Parser:parseIf()
  self:expect("KEYWORD", "if")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "then")
  local thenBody = self:parseBlock()
  local clauses = { { cond = cond, body = thenBody } }

  while self:check("KEYWORD", "elseif") do
    self:advance()
    local c = self:parseExpression(0)
    self:expect("KEYWORD", "then")
    local b = self:parseBlock()
    table.insert(clauses, { cond = c, body = b })
  end

  local elseBody = nil
  if self:accept("KEYWORD", "else") then
    elseBody = self:parseBlock()
  end

  self:expect("KEYWORD", "end")
  return { kind = "If", clauses = clauses, elseBody = elseBody }
end

function Parser:parseWhile()
  self:expect("KEYWORD", "while")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "While", cond = cond, body = body }
end

function Parser:parseRepeat()
  self:expect("KEYWORD", "repeat")
  local body = self:parseBlock()
  self:expect("KEYWORD", "until")
  local cond = self:parseExpression(0)
  return { kind = "Repeat", body = body, cond = cond }
end

function Parser:parseFor()
  self:expect("KEYWORD", "for")
  local firstName = self:expect("IDENTIFIER").value

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

  local names = { firstName }
  while self:accept("OPERATOR", ",") do
    table.insert(names, self:expect("IDENTIFIER").value)
  end
  self:expect("KEYWORD", "in")
  local iters = { self:parseExpression(0) }
  while self:accept("OPERATOR", ",") do
    table.insert(iters, self:parseExpression(0))
  end
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "GenericFor", names = names, iters = iters, body = body }
end

-- function a.b.c(...)  o  function a:m(...)
function Parser:parseNamedFunction()
  self:expect("KEYWORD", "function")
  -- basahin ang target: name(.name)*(:method)?
  local target = { kind = "Variable", name = self:expect("IDENTIFIER").value }
  while self:check("OPERATOR", ".") do
    self:advance()
    local field = self:expect("IDENTIFIER").value
    target = { kind = "Index", object = target, field = field }
  end
  local isMethod = false
  local methodName = nil
  if self:accept("OPERATOR", ":") then
    isMethod = true
    methodName = self:expect("IDENTIFIER").value
    target = { kind = "Index", object = target, field = methodName }
  end

  local fn = self:parseFunctionBody(nil)
  -- kung method, may implicit na "self" na unang param
  if isMethod then
    table.insert(fn.params, 1, "self")
  end
  return { kind = "FunctionDeclaration", target = target, func = fn, isMethod = isMethod }
end

function Parser:parseReturn()
  self:expect("KEYWORD", "return")
  local values = {}
  if not self:check("KEYWORD", "end") and not self:check("EOF")
     and not self:check("KEYWORD", "else") and not self:check("KEYWORD", "elseif")
     and not self:check("KEYWORD", "until") then
    repeat
      table.insert(values, self:parseExpression(0))
    until not self:accept("OPERATOR", ",")
  end
  return { kind = "Return", values = values }
end

-- do ... end (block scope)
function Parser:parseDo()
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "Do", body = body }
end

function Parser:parseStatement()
  local tok = self:peek()

  if tok.type == "KEYWORD" then
    if tok.value == "local"    then return self:parseLocal() end
    if tok.value == "if"       then return self:parseIf() end
    if tok.value == "while"    then return self:parseWhile() end
    if tok.value == "repeat"   then return self:parseRepeat() end
    if tok.value == "for"      then return self:parseFor() end
    if tok.value == "function" then return self:parseNamedFunction() end
    if tok.value == "return"   then return self:parseReturn() end
    if tok.value == "do"       then return self:parseDo() end
    if tok.value == "break"    then self:advance(); return { kind = "Break" } end
  end

  -- expression-based statement: call o assignment (single/multiple)
  if tok.type == "IDENTIFIER" or (tok.type == "OPERATOR" and tok.value == "(") then
    local first = self:parsePrimary()

    -- multiple assignment: a, b, ... = ...
    if self:check("OPERATOR", ",") or self:check("OPERATOR", "=") then
      local targets = { first }
      while self:accept("OPERATOR", ",") do
        table.insert(targets, self:parsePrimary())
      end
      self:expect("OPERATOR", "=")
      local values = { self:parseExpression(0) }
      while self:accept("OPERATOR", ",") do
        table.insert(values, self:parseExpression(0))
      end
      return { kind = "Assignment", targets = targets, values = values }
    end

    -- kung hindi assignment, dapat call statement
    if first.kind == "Call" or first.kind == "MethodCall" then
      return { kind = "CallStatement", call = first }
    end

    error(string.format("Hindi wastong statement (linya %s)", tostring(tok.line)))
  end

  error(string.format("Hindi kilalang statement: %s '%s' (linya %s)",
    tok.type, tok.value, tostring(tok.line)))
end

function Parser:parseBlock()
  local statements = {}
  while true do
    local tok = self:peek()
    if tok.type == "EOF"
       or (tok.type == "KEYWORD" and (tok.value == "end" or tok.value == "else"
           or tok.value == "elseif" or tok.value == "until")) then
      break
    end
    local stmt = self:parseStatement()
    table.insert(statements, stmt)
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