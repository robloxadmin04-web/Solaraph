-- parser.lua
-- Parser: listahan ng tokens -> AST (tree)
-- Ngayon: buong expression parsing na may tamang operator precedence.

local Parser = {}
Parser.__index = Parser

-- Precedence table: mas mataas = mas kumakapit (mas naunang gina-group)
local BINARY_PRECEDENCE = {
  ["or"]  = 1,
  ["and"] = 2,
  ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["=="] = 3,
  [".."] = 4,
  ["+"] = 5, ["-"] = 5,
  ["*"] = 6, ["/"] = 6, ["%"] = 6,
}

-- Ang precedence ng unary operators (not, -, #)
local UNARY_PRECEDENCE = 7

-- Gumawa ng bagong parser mula sa tokens
function Parser.new(tokens)
  local self = setmetatable({}, Parser)
  self.tokens = tokens
  self.pos = 1              -- kasalukuyang token
  return self
end

-- Tignan ang kasalukuyang token nang hindi lumilipat
function Parser:peek()
  return self.tokens[self.pos]
end

-- Kunin ang kasalukuyang token at lumipat sa susunod
function Parser:advance()
  local tok = self.tokens[self.pos]
  self.pos = self.pos + 1
  return tok
end

-- Basahin ang isang "unary" o "primary"
function Parser:parseUnary()
  local tok = self:peek()

  -- Unary operator: not, -, #
  if (tok.type == "OPERATOR" and (tok.value == "-" or tok.value == "#"))
     or (tok.type == "KEYWORD" and tok.value == "not") then
    local op = self:advance().value
    local operand = self:parseExpression(UNARY_PRECEDENCE)
    return { kind = "UnaryOp", op = op, operand = operand }
  end

  return self:parsePrimary()
end

-- Basahin ang isang "primary" — pinakasimpleng piraso
function Parser:parsePrimary()
  local tok = self:peek()

  -- Numero
  if tok.type == "NUMBER" then
    self:advance()
    return { kind = "Number", value = tok.value }

  -- String
  elseif tok.type == "STRING" then
    self:advance()
    return { kind = "String", value = tok.value }

  -- Booleans at nil
  elseif tok.type == "KEYWORD" and (tok.value == "true" or tok.value == "false" or tok.value == "nil") then
    self:advance()
    return { kind = "Literal", value = tok.value }

  -- Identifier -> Variable
  elseif tok.type == "IDENTIFIER" then
    self:advance()
    return { kind = "Variable", name = tok.value }

  -- Naka-parentheses na expression
  elseif tok.type == "OPERATOR" and tok.value == "(" then
    self:advance()                      -- kainin ang "("
    local expr = self:parseExpression(0)
    self:advance()                      -- kainin ang ")"
    return expr
  end

  error("Hindi inaasahang token: " .. tok.type .. " '" .. tok.value .. "'")
end

-- Ang puso: precedence climbing
-- minPrec = pinakamababang precedence na tatanggapin sa lebel na ito
function Parser:parseExpression(minPrec)
  local left = self:parseUnary()

  while true do
    local tok = self:peek()
    -- tanggapin ang OPERATOR o ang keyword na and/or
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

-- Pangunahing entry point
function Parser.parse(tokens)
  local self = Parser.new(tokens)
  return self:parseExpression(0)
end

return Parser