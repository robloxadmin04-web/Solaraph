-- parser.lua
-- Parser: tokens -> AST. Luau-aware: continue, generalized for, compound assignment,
-- type annotations (local, for, AT function params/return).

local Lexer = require("lexer")

local Parser = {}
Parser.__index = Parser

local BINARY_PRECEDENCE = {
  ["or"]  = 1,
  ["and"] = 2,
  ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["=="] = 3,
  [".."] = 4,
  ["+"] = 5, ["-"] = 5,
  ["*"] = 6, ["/"] = 6, ["%"] = 6, ["//"] = 6,   -- Luau: floor division, same tier as * / %
}

local UNARY_PRECEDENCE = 7
local COMPOUND = { ["+="]="+", ["-="]="-", ["*="]="*", ["/="]="/", ["%="]="%",
                    ["^="]="^", ["..="]="..", ["//="]="//" }

-- ============ Luau string interpolation: `text {expr} text` ============
-- Desugar sa PARSE TIME tungo sa isang normal na concatenation expression
-- (String .. tostring(expr) .. String ...). Dahil existing AST node kinds
-- lang (String/Call/BinaryOp) ang ginagamit, awtomatikong sinusuportahan
-- ito ng LAHAT ng ibang pass (renamer, constfold, numenc, stringenc, vm)
-- nang walang kahit anong pagbabago doon.
local INTERP_ESCAPES = {
  n = "\n", t = "\t", r = "\r", ["\\"] = "\\",
  ["`"] = "`", ["{"] = "{", ["}"] = "}", ['"'] = '"', ["'"] = "'",
}
local function unescapeInterpText(s)
  return (s:gsub("\\(.)", function(c) return INTERP_ESCAPES[c] or ("\\" .. c) end))
end

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

function Parser:parseCallArgs()
  if self:check("STRING") then
    local s = self:advance()
    return { { kind = "String", value = s.value } }
  end
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

function Parser:parseTable()
  self:expect("OPERATOR", "{")
  local fields = {}
  while not self:check("OPERATOR", "}") do
    if self:check("OPERATOR", "[") then
      self:advance()
      local key = self:parseExpression(0)
      self:expect("OPERATOR", "]")
      self:expect("OPERATOR", "=")
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "keyed", key = key, value = val })
    elseif self:check("IDENTIFIER") and self.tokens[self.pos + 1]
           and self.tokens[self.pos + 1].type == "OPERATOR"
           and self.tokens[self.pos + 1].value == "=" then
      local name = self:advance().value
      self:advance()
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "named", name = name, value = val })
    else
      local val = self:parseExpression(0)
      table.insert(fields, { kind = "array", value = val })
    end
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
      local args = self:parseCallArgs()
      node = { kind = "Call", callee = node, args = args }
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

-- Sub-parse ang laman ng isang "{expr}" na bahagi ng interpolated string,
-- gamit ang parehong Lexer/Parser (bagong instance, hiwalay na token stream).
function Parser:parseInterpExpr(exprSrc)
  local tokens = Lexer.tokenize(exprSrc)
  local sub = Parser.new(tokens)
  local expr = sub:parseExpression(0)
  return expr
end

-- raw: buong token value kasama ang backticks, hal. "`Score: {score}!`"
-- Balik: isang expression node (BinaryOp ".." chain, o iisang String kung
-- walang { } sa loob, o "" String kung walang laman).
function Parser:parseInterpString(raw)
  local body = raw:sub(2, #raw - 1)
  local parts = {}
  local textBuf = {}
  local i, len = 1, #body
  while i <= len do
    local c = body:sub(i, i)
    if c == "\\" and i < len then
      table.insert(textBuf, body:sub(i, i + 1))
      i = i + 2
    elseif c == "{" then
      if #textBuf > 0 then
        table.insert(parts, { text = unescapeInterpText(table.concat(textBuf)) })
        textBuf = {}
      end
      local depth = 1
      local start = i + 1
      local j = start
      while j <= len and depth > 0 do
        local cj = body:sub(j, j)
        if cj == "{" then depth = depth + 1
        elseif cj == "}" then
          depth = depth - 1
          if depth == 0 then break end
        end
        j = j + 1
      end
      local exprSrc = body:sub(start, j - 1)
      table.insert(parts, { expr = self:parseInterpExpr(exprSrc) })
      i = j + 1
    else
      table.insert(textBuf, c)
      i = i + 1
    end
  end
  if #textBuf > 0 then
    table.insert(parts, { text = unescapeInterpText(table.concat(textBuf)) })
  end

  local result = nil
  for _, p in ipairs(parts) do
    local piece
    if p.text ~= nil then
      piece = { kind = "String", value = string.format("%q", p.text) }
    else
      piece = { kind = "Call", callee = { kind = "Variable", name = "tostring" }, args = { p.expr } }
    end
    result = (result == nil) and piece or { kind = "BinaryOp", op = "..", left = result, right = piece }
  end
  return result or { kind = "String", value = '""' }
end

-- Luau if-then-else EXPRESSION: `if cond then a elseif c2 then b else c`.
-- Desugar sa isang immediately-invoked function expression (IIFE) gamit ang
-- normal na If/Return/Function/Call node kinds â€” kaya ligtas din itong
-- dumaan sa lahat ng ibang obfuscation pass nang walang extra code doon.
function Parser:parseIfExpression()
  self:expect("KEYWORD", "if")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "then")
  local thenExpr = self:parseExpression(0)
  local clauses = { { cond = cond, body = { { kind = "Return", values = { thenExpr } } } } }
  while self:check("KEYWORD", "elseif") do
    self:advance()
    local c = self:parseExpression(0)
    self:expect("KEYWORD", "then")
    local e = self:parseExpression(0)
    table.insert(clauses, { cond = c, body = { { kind = "Return", values = { e } } } })
  end
  self:expect("KEYWORD", "else")
  local elseExpr = self:parseExpression(0)
  local ifNode = { kind = "If", clauses = clauses,
                    elseBody = { { kind = "Return", values = { elseExpr } } } }
  local fn = { kind = "Function", name = nil, params = {}, body = { ifNode } }
  return { kind = "Call", callee = fn, args = {} }
end

-- Luau attributes: @native, @checked, atbp. Laktawan lang â€” walang epekto
-- sa runtime behavior kaya ligtas na alisin sa output (hindi na kailangan
-- i-preserve para gumana ang na-obfuscate na code).
function Parser:skipAttributes()
  while self:check("OPERATOR", "@") do
    self:advance()
    if self:check("IDENTIFIER") or self:check("KEYWORD") then self:advance() end
  end
end

function Parser:parseAtom()
  local tok = self:peek()
  if tok.type == "NUMBER" then
    self:advance(); return { kind = "Number", value = tok.value }
  elseif tok.type == "STRING" then
    self:advance(); return { kind = "String", value = tok.value }
  elseif tok.type == "INTERP_STRING" then
    self:advance(); return self:parseInterpString(tok.value)
  elseif tok.type == "KEYWORD" and (tok.value == "true" or tok.value == "false" or tok.value == "nil") then
    self:advance(); return { kind = "Literal", value = tok.value }
  elseif tok.type == "KEYWORD" and tok.value == "if" then
    return self:parseIfExpression()
  elseif tok.type == "OPERATOR" and tok.value == "..." then
    self:advance(); return { kind = "Vararg" }
  elseif tok.type == "KEYWORD" and tok.value == "function" then
    self:advance(); return self:parseFunctionBody(nil)
  elseif tok.type == "OPERATOR" and tok.value == "{" then
    return self:parseTable()
  elseif tok.type == "IDENTIFIER" then
    self:advance(); return { kind = "Variable", name = tok.value }
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
        self:advance(); table.insert(params, "...")
        self:skipTypeAnnotation()   -- Luau: typed vararg  ...: T
        break
      end
      table.insert(params, self:expect("IDENTIFIER").value)
      self:skipTypeAnnotation()     -- Luau: typed param  param: T
    until not self:accept("OPERATOR", ",")
  end
  self:expect("OPERATOR", ")")
  self:skipTypeAnnotation()         -- Luau: return type  ): T
  return params
end

function Parser:parseFunctionBody(name)
  local params = self:parseParams()
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "Function", name = name, params = params, body = body }
end

function Parser:parseLocal()
  self:expect("KEYWORD", "local")
  self:skipAttributes()   -- Luau: local @native function foo() ... end
  if self:check("KEYWORD", "function") then
    self:advance()
    local name = self:expect("IDENTIFIER").value
    local fn = self:parseFunctionBody(name)
    return { kind = "LocalFunction", name = name, func = fn }
  end
  local names = { self:expect("IDENTIFIER").value }
  -- Luau: opsyonal na type annotation  local x: T
  self:skipTypeAnnotation()
  while self:accept("OPERATOR", ",") do
    table.insert(names, self:expect("IDENTIFIER").value)
    self:skipTypeAnnotation()
  end
  local values = {}
  if self:accept("OPERATOR", "=") then
    repeat
      table.insert(values, self:parseExpression(0))
    until not self:accept("OPERATOR", ",")
  end
  return { kind = "LocalAssignment", names = names, values = values }
end

-- Luau type annotation: laktawan ang ": Type" (simpleng version)
function Parser:skipTypeAnnotation()
  if self:check("OPERATOR", ":") then
    self:advance()
    -- laktawan ang isang type token stream: identifier na may .Name, <...>, |, ?, {}
    local depth = 0
    while true do
      local t = self:peek()
      if t.type == "EOF" then break end
      if t.type == "OPERATOR" and (t.value == "<" or t.value == "{" or t.value == "(") then depth = depth + 1; self:advance()
      elseif t.type == "OPERATOR" and (t.value == ">" or t.value == "}" or t.value == ")") then
        if depth == 0 then break end
        depth = depth - 1; self:advance()
      elseif depth == 0 and (t.type == "IDENTIFIER" or (t.type=="OPERATOR" and (t.value=="."or t.value=="?"or t.value=="|"or t.value=="&")) or (t.type=="KEYWORD" and (t.value=="nil"or t.value=="true"or t.value=="false"))) then
        self:advance()
      elseif depth > 0 then self:advance()
      else break end
    end
  end
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

-- ============ continue desugar helper ============
-- I-transform ang "Continue" nodes sa top level ng body -> "Break" ng inner
-- "repeat ... until true", para tumalon sa dulo ng loop body (Luau semantics).
-- HINDI pumapasok sa nested loops (may sariling continue scope).
local function bodyHasContinue(stmts)
  for _, s in ipairs(stmts) do
    if s.kind == "Continue" then return true end
    if s.kind == "If" then
      for _, cl in ipairs(s.clauses) do if bodyHasContinue(cl.body) then return true end end
      if s.elseBody and bodyHasContinue(s.elseBody) then return true end
    elseif s.kind == "Do" and bodyHasContinue(s.body) then return true
    end
  end
  return false
end
local function replaceContinue(stmts)
  for i, s in ipairs(stmts) do
    if s.kind == "Continue" then
      stmts[i] = { kind = "Break" }
    elseif s.kind == "If" then
      for _, cl in ipairs(s.clauses) do replaceContinue(cl.body) end
      if s.elseBody then replaceContinue(s.elseBody) end
    elseif s.kind == "Do" then
      replaceContinue(s.body)
    end
    -- huwag pumasok sa While/For/Repeat: sarili nilang scope
  end
end
local function wrapContinue(body)
  if not bodyHasContinue(body) then return body end
  replaceContinue(body)
  return { { kind = "Repeat", body = body, cond = { kind = "Literal", value = "true" } } }
end

function Parser:parseWhile()
  self:expect("KEYWORD", "while")
  local cond = self:parseExpression(0)
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "While", cond = cond, body = wrapContinue(body) }
end

function Parser:parseRepeat()
  self:expect("KEYWORD", "repeat")
  local body = self:parseBlock()
  self:expect("KEYWORD", "until")
  local cond = self:parseExpression(0)
  return { kind = "Repeat", body = wrapContinue(body), cond = cond }
end

function Parser:parseFor()
  self:expect("KEYWORD", "for")
  local firstName = self:expect("IDENTIFIER").value
  self:skipTypeAnnotation()

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
             startExpr = startExpr, stopExpr = stopExpr, stepExpr = stepExpr, body = wrapContinue(body) }
  end

  local names = { firstName }
  while self:accept("OPERATOR", ",") do
    table.insert(names, self:expect("IDENTIFIER").value)
    self:skipTypeAnnotation()
  end
  self:expect("KEYWORD", "in")
  local iters = { self:parseExpression(0) }
  while self:accept("OPERATOR", ",") do
    table.insert(iters, self:parseExpression(0))
  end
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")

  -- Luau generalized iteration: `for k,v in someTable do` (a bare table value,
  -- not a call) is wrapped in pairs() so it works under the standard protocol.
  -- Function-call iterators (pairs, ipairs, gmatch, coroutine.wrap, custom
  -- factories, ...) already return a proper iterator and must NOT be wrapped.
  if #iters == 1 and iters[1].kind ~= "Call" then
    iters = { { kind = "Call", callee = { kind = "Variable", name = "pairs" }, args = { iters[1] } } }
  end

  return { kind = "GenericFor", names = names, iters = iters, body = wrapContinue(body) }
end

function Parser:parseNamedFunction()
  self:expect("KEYWORD", "function")
  local target = { kind = "Variable", name = self:expect("IDENTIFIER").value }
  while self:check("OPERATOR", ".") do
    self:advance()
    local field = self:expect("IDENTIFIER").value
    target = { kind = "Index", object = target, field = field }
  end
  local isMethod = false
  if self:accept("OPERATOR", ":") then
    isMethod = true
    local methodName = self:expect("IDENTIFIER").value
    target = { kind = "Index", object = target, field = methodName }
  end
  local fn = self:parseFunctionBody(nil)
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

function Parser:parseDo()
  self:expect("KEYWORD", "do")
  local body = self:parseBlock()
  self:expect("KEYWORD", "end")
  return { kind = "Do", body = body }
end

-- Luau: "continue" ay context-sensitive â€” statement lang kung ang SUNOD na token
-- ay hindi (. [ : ( { = , string) â€” kung hindi, ordinaryong identifier ito.
function Parser:isContinueStatement()
  local tok = self:peek()
  if not (tok.type == "IDENTIFIER" and tok.value == "continue") then return false end
  local nxt = self.tokens[self.pos + 1]
  if not nxt then return true end
  if nxt.type == "STRING" then return false end
  if nxt.type == "OPERATOR" and (nxt.value=="."or nxt.value=="["or nxt.value==":"or nxt.value=="("or nxt.value=="{"or nxt.value=="="or nxt.value==","or COMPOUND[nxt.value]) then
    return false
  end
  return true
end

function Parser:parseStatement()
  local tok = self:peek()

  -- Luau continue (context-sensitive keyword)
  if self:isContinueStatement() then
    self:advance()
    return { kind = "Continue" }
  end

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

  if tok.type == "IDENTIFIER" or (tok.type == "OPERATOR" and tok.value == "(") then
    local first = self:parsePrimary()

    -- compound assignment: a += b, a ..= b, atbp.
    local pk = self:peek()
    if pk.type == "OPERATOR" and COMPOUND[pk.value] then
      local op = COMPOUND[self:advance().value]
      local rhs = self:parseExpression(0)
      return { kind = "Assignment", targets = { first },
               values = { { kind = "BinaryOp", op = op, left = first, right = rhs } } }
    end

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
    -- Lua/Luau: opsyonal na ";" separator â€” laktawan ang stray semicolons
    while self:accept("OPERATOR", ";") do end
    self:skipAttributes()   -- Luau: @native / @checked bago ang function/local
    local tok = self:peek()
    if tok.type == "EOF"
       or (tok.type == "KEYWORD" and (tok.value == "end" or tok.value == "else"
           or tok.value == "elseif" or tok.value == "until")) then
      break
    end
    local stmt = self:parseStatement()
    table.insert(statements, stmt)
    if stmt.kind == "Return" or stmt.kind == "Break" or stmt.kind == "Continue" then
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
