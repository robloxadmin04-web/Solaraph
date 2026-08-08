-- lexer.lua
-- Ang unang lexer: source string -> listahan ng tokens

local Lexer = {}

-- Lahat ng reserved keywords sa Lua 5.1
local KEYWORDS = {
  ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true, ["elseif"]=true,
  ["end"]=true, ["false"]=true, ["for"]=true, ["function"]=true, ["goto"]=true,
  ["if"]=true, ["in"]=true, ["local"]=true, ["nil"]=true, ["not"]=true,
  ["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
  ["until"]=true, ["while"]=true,
}

-- Helper: totoo kung ang character ay letra o underscore
local function isAlpha(c)
  return c:match("[%a_]") ~= nil
end

-- Helper: totoo kung ang character ay numero
local function isDigit(c)
  return c:match("%d") ~= nil
end

-- Helper: letra, numero, o underscore (pang-loob ng identifier)
local function isAlphaNum(c)
  return c:match("[%w_]") ~= nil
end

function Lexer.tokenize(source)
  local tokens = {}   -- dito ilalagay ang lahat ng token
  local i = 1         -- kasalukuyang posisyon sa string
  local line = 1      -- linya, para sa error messages balang araw
  local len = #source

  while i <= len do
    local c = source:sub(i, i)

    -- 1. Laktawan ang whitespace
    if c == "\n" then
      line = line + 1
      i = i + 1
    elseif c:match("%s") then
      i = i + 1

    -- 2. Identifier o keyword (nagsisimula sa letra/underscore)
    elseif isAlpha(c) then
      local start = i
      while i <= len and isAlphaNum(source:sub(i, i)) do
        i = i + 1
      end
      local word = source:sub(start, i - 1)
      local kind = KEYWORDS[word] and "KEYWORD" or "IDENTIFIER"
      table.insert(tokens, { type = kind, value = word, line = line })

    -- 3. Numero (simpleng integer/decimal muna)
    elseif isDigit(c) then
      local start = i
      while i <= len and (isDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
        i = i + 1
      end
      table.insert(tokens, { type = "NUMBER", value = source:sub(start, i - 1), line = line })

    -- 4. Operators at symbols (isahang character muna)
    else
      table.insert(tokens, { type = "OPERATOR", value = c, line = line })
      i = i + 1
    end
  end

  -- Pandulong marker na wala nang natira
  table.insert(tokens, { type = "EOF", value = "<eof>", line = line })
  return tokens
end

return Lexer
