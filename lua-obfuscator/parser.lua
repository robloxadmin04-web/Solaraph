-- parser.lua
-- Parser: listahan ng tokens -> AST (tree)
-- Ngayon: mga expression lang muna, na may tamang operator precedence.

local Parser = {}
Parser.__index = Parser

-- Precedence table: mas mataas = mas kumakapit (mas naunang gina-group)
local BINARY_PRECEDENCE = {
  ["+"] = 1, ["-"] = 1,
  ["*"] = 2, ["/"] = 2, ["%"] = 2,
}

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

-- Basahin ang isang "primary" — pinakasimpleng piraso: numero o naka-parentheses
function Parser:parsePrimary()
  local tok = self:peek()

  -- Numero -> Number node
  if tok.type == "NUMBER" then
    self:advance()
    return { kind = "Number", value = tok.value }

  -- Identifier -> Variable node
  elseif tok.type == "IDENTIFIER" then
    self:advance()
    return { kind = "Variable", name = tok.value }

  -- Naka-parentheses na expression: ( ... )
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
  -- kunin muna ang kaliwang bahagi
  local left = self:parsePrimary()

  -- habang ang kasunod na operator ay sapat ang precedence, ipagpatuloy
  while true do
    local tok = self:peek()
    if tok.type ~= "OPERATOR" then break end

    local prec = BINARY_PRECEDENCE[tok.value]
    if prec == nil or prec < minPrec then break end

    -- kainin ang operator, tapos basahin ang kanan na may mas mataas na hangganan
    local op = self:advance().value
    local right = self:parseExpression(prec + 1)

    -- gawing bagong tree node: (left op right)
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
