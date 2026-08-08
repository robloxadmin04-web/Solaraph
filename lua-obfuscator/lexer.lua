-- lexer.lua
-- Lexer: source string -> listahan ng tokens

local Lexer = {}

-- Lahat ng reserved keywords sa Lua
local KEYWORDS = {
  ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true, ["elseif"]=true,
  ["end"]=true, ["false"]=true, ["for"]=true, ["function"]=true, ["goto"]=true,
  ["if"]=true, ["in"]=true, ["local"]=true, ["nil"]=true, ["not"]=true,
  ["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
  ["until"]=true, ["while"]=true,
}

local function isAlpha(c)    return c:match("[%a_]") ~= nil end
local function isDigit(c)    return c:match("%d") ~= nil end
local function isAlphaNum(c) return c:match("[%w_]") ~= nil end
local function isHexDigit(c) return c:match("[%x]") ~= nil end   -- 0-9, a-f, A-F

-- Sinusubukang basahin ang pambukas na long bracket sa posisyon i.
-- Nagbabalik ng level (bilang ng =) at posisyon pagkatapos ng pambukas, o nil.
-- Hal: "[[" -> level 0, "[=[" -> level 1, "[==[" -> level 2
local function checkLongBracketOpen(source, i)
  if source:sub(i, i) ~= "[" then return nil end
  local j = i + 1
  local level = 0
  while source:sub(j, j) == "=" do
    level = level + 1
    j = j + 1
  end
  if source:sub(j, j) == "[" then
    return level, j + 1
  end
  return nil
end

-- Binabasa ang laman ng long bracket hanggang sa katugmang pansara (]==]).
-- Nagbabalik ng dulo na posisyon (pagkatapos ng pansara) at bagong linya count.
local function readLongBracket(source, startBody, level, line)
  local len = #source
  local close = "]" .. string.rep("=", level) .. "]"
  local i = startBody
  while i <= len do
    if source:sub(i, i) == "\n" then
      line = line + 1
      i = i + 1
    elseif source:sub(i, i) == "]" and source:sub(i, i + #close - 1) == close then
      return i + #close, line
    else
      i = i + 1
    end
  end
  return len + 1, line   -- unterminated: hanggang dulo na lang
end

-- Binabasa ang isang numero mula sa posisyon i.
-- Sinasaklaw ang: hex (0xFF, 0x1p4), decimal, at scientific notation (1e10, 1.5e-3).
-- Nagbabalik ng bagong posisyon i.
local function readNumber(source, i)
  local len = #source

  -- Hex: nagsisimula sa 0x o 0X
  if source:sub(i, i) == "0" and source:sub(i + 1, i + 1):match("[xX]") then
    i = i + 2  -- laktawan ang "0x"
    while i <= len and (isHexDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
      i = i + 1
    end
    -- binary exponent para sa hex float: p / P
    if source:sub(i, i):match("[pP]") then
      i = i + 1
      if source:sub(i, i):match("[%+%-]") then i = i + 1 end
      while i <= len and isDigit(source:sub(i, i)) do i = i + 1 end
    end
    return i
  end

  -- Decimal: mga digit at isang tuldok
  while i <= len and (isDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
    i = i + 1
  end
  -- Scientific notation: e / E na sinusundan ng opsyonal na sign
  if source:sub(i, i):match("[eE]") then
    i = i + 1
    if source:sub(i, i):match("[%+%-]") then i = i + 1 end
    while i <= len and isDigit(source:sub(i, i)) do i = i + 1 end
  end
  return i
end

function Lexer.tokenize(source)
  local tokens = {}
  local i = 1
  local line = 1
  local len = #source

  while i <= len do
    local c = source:sub(i, i)
    local nextC = source:sub(i + 1, i + 1)

    -- 1. Newline
    if c == "\n" then
      line = line + 1
      i = i + 1

    -- 2. Iba pang whitespace
    elseif c:match("%s") then
      i = i + 1

    -- 3. COMMENT: "--" (line o block)
    elseif c == "-" and nextC == "-" then
      i = i + 2  -- laktawan ang "--"
      local level, bodyStart = checkLongBracketOpen(source, i)
      if level ~= nil then
        -- block comment: --[[ ... ]]
        i, line = readLongBracket(source, bodyStart, level, line)
      else
        -- line comment: hanggang katapusan ng linya
        while i <= len and source:sub(i, i) ~= "\n" do
          i = i + 1
        end
      end

    -- 4a. LONG STRING: [[ ... ]] o [=[ ... ]=]
    elseif c == "[" and checkLongBracketOpen(source, i) ~= nil then
      local level, bodyStart = checkLongBracketOpen(source, i)
      local start = i
      i, line = readLongBracket(source, bodyStart, level, line)
      table.insert(tokens, { type = "STRING", value = source:sub(start, i - 1), line = line })

    -- 4b. SHORT STRING: "..." o '...'
    elseif c == '"' or c == "'" then
      local quote = c
      local start = i
      i = i + 1
      while i <= len and source:sub(i, i) ~= quote do
        if source:sub(i, i) == "\\" then
          i = i + 1   -- laktawan ang escaped char (hal. \" )
        end
        i = i + 1
      end
      i = i + 1  -- laktawan ang pansarang quote
      table.insert(tokens, { type = "STRING", value = source:sub(start, i - 1), line = line })

    -- 5. Identifier o keyword
    elseif isAlpha(c) then
      local start = i
      while i <= len and isAlphaNum(source:sub(i, i)) do
        i = i + 1
      end
      local word = source:sub(start, i - 1)
      local kind = KEYWORDS[word] and "KEYWORD" or "IDENTIFIER"
      table.insert(tokens, { type = kind, value = word, line = line })

    -- 6. Numero (hex, decimal, scientific)
    elseif isDigit(c) or (c == "." and isDigit(nextC)) then
      local start = i
      i = readNumber(source, i)
      table.insert(tokens, { type = "NUMBER", value = source:sub(start, i - 1), line = line })

    -- 7. Operators at symbols (multi-char muna, tapos isahan)
    else
      local three = source:sub(i, i + 2)
      local two   = source:sub(i, i + 1)

      if three == "..." then
        table.insert(tokens, { type = "OPERATOR", value = "...", line = line })
        i = i + 3
      elseif two == "==" or two == "~=" or two == "<="
          or two == ">=" or two == ".." then
        table.insert(tokens, { type = "OPERATOR", value = two, line = line })
        i = i + 2
      else
        table.insert(tokens, { type = "OPERATOR", value = c, line = line })
        i = i + 1
      end
    end
  end

  table.insert(tokens, { type = "EOF", value = "<eof>", line = line })
  return tokens
end

return Lexer
