-- parser.lua
-- Parser: listahan ng tokens -> AST (tree)
-- Ngayon: expressions + statements (local, assignment, program).

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

function Parser:peek()
  return self.tokens[self.pos]
end

function Parser:advance()
  local tok = self.tokens[self.pos]
  self.pos = self.pos + 1
  return tok
end

-- Siguraduhing ang kasalukuyang token ay ang inaasahan, tapos kainin ito.
-- Para sa maayos na error kung mali ang syntax.
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

function Parser:parsePrimary()
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

-- local x = <expression>
-- (isang variable muna; palawakin natin sa multiple mamaya)
function Parser:parseLocal()
  self:expect("KEYWORD", "local")
  local name = self:expect("IDENTIFIER").value
  self:expect("OPERATOR", "=")
  local value = self:parseExpression(0)
  return { kind = "LocalAssignment", name = name, value = value }
end

-- x = <expression>   (assignment sa umiiral na variable)
function Parser:parseAssignment()
  local name = self:expect("IDENTIFIER").value
  self:expect("OPERATOR", "=")
  local value = self:parseExpression(0)
  return { kind = "Assignment", name = name, value = value }
end

-- Pumili kung anong statement base sa unang token
function Parser:parseStatement()
  local tok = self:peek()

  if tok.type == "KEYWORD" and tok.value == "local" then
    return self:parseLocal()

  elseif tok.type == "IDENTIFIER" then
    return self:parseAssignment()
  end

  error(string.format("Hindi kilalang statement: %s '%s' (linya %s)",
    tok.type, tok.value, tostring(tok.line)))
end

-- Basahin ang buong program: sunod-sunod na statements hanggang EOF
function Parser:parseProgram()
  local statements = {}
  while self:peek().type ~= "EOF" do
    table.insert(statements, self:parseStatement())
  end
  return { kind = "Program", body = statements }
end

-- Pangunahing entry point
function Parser.parse(tokens)
  local self = Parser.new(tokens)
  return self:parseProgram()
end

return Parser
