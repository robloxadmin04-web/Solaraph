-- lexer.lua
-- Lexer: source string -> listahan ng tokens
-- Luau support: compound operators (+=, -=, *=, /=, %=, ^=, ..=)

local Lexer = {}

-- Lahat ng reserved keywords sa Lua/Luau
-- NOTE: "continue" ay HINDI reserved (context-sensitive sa Luau) â€” identifier ito.
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
local function isHexDigit(c) return c:match("[%x]") ~= nil end

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
  return len + 1, line
end

local function readNumber(source, i)
  local len = #source
  if source:sub(i, i) == "0" and source:sub(i + 1, i + 1):match("[xX]") then
    i = i + 2
    while i <= len and (isHexDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
      i = i + 1
    end
    if source:sub(i, i):match("[pP]") then
      i = i + 1
      if source:sub(i, i):match("[%+%-]") then i = i + 1 end
      while i <= len and isDigit(source:sub(i, i)) do i = i + 1 end
    end
    return i
  end
  while i <= len and (isDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
    i = i + 1
  end
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

    if c == "\n" then
      line = line + 1
      i = i + 1

    elseif c:match("%s") then
      i = i + 1

    elseif c == "-" and nextC == "-" then
      i = i + 2
      local level, bodyStart = checkLongBracketOpen(source, i)
      if level ~= nil then
        i, line = readLongBracket(source, bodyStart, level, line)
      else
        while i <= len and source:sub(i, i) ~= "\n" do
          i = i + 1
        end
      end

    elseif c == "[" and checkLongBracketOpen(source, i) ~= nil then
      local level, bodyStart = checkLongBracketOpen(source, i)
      local start = i
      i, line = readLongBracket(source, bodyStart, level, line)
      table.insert(tokens, { type = "STRING", value = source:sub(start, i - 1), line = line })

    elseif c == "`" then
      -- Luau string interpolation: `text {expr} text`. Kunin ang BUONG raw
      -- token (kasama ang { } at anumang laman sa loob) â€” ang parser na
      -- ang mag-sub-parse ng mga {expr} bahagi. Depth-track ang { } para
      -- hindi masira ng isang literal "}" sa loob ng interpolated expr
      -- (hal. `{ {1,2,3}[1] }`), at huwag isara ang backtick sa loob ng {}.
      local start = i
      i = i + 1
      local depth = 0
      while i <= len do
        local ch = source:sub(i, i)
        if ch == "\\" then
          i = i + 2
        elseif ch == "{" then
          depth = depth + 1; i = i + 1
        elseif ch == "}" then
          if depth > 0 then depth = depth - 1 end
          i = i + 1
        elseif ch == "`" and depth == 0 then
          i = i + 1
          break
        else
          if ch == "\n" then line = line + 1 end
          i = i + 1
        end
      end
      table.insert(tokens, { type = "INTERP_STRING", value = source:sub(start, i - 1), line = line })

    elseif c == '"' or c == "'" then
      local quote = c
      local start = i
      i = i + 1
      while i <= len and source:sub(i, i) ~= quote do
        if source:sub(i, i) == "\\" then
          i = i + 1
        end
        i = i + 1
      end
      i = i + 1
      table.insert(tokens, { type = "STRING", value = source:sub(start, i - 1), line = line })

    elseif isAlpha(c) then
      local start = i
      while i <= len and isAlphaNum(source:sub(i, i)) do
        i = i + 1
      end
      local word = source:sub(start, i - 1)
      local kind = KEYWORDS[word] and "KEYWORD" or "IDENTIFIER"
      table.insert(tokens, { type = kind, value = word, line = line })

    elseif isDigit(c) or (c == "." and isDigit(nextC)) then
      local start = i
      i = readNumber(source, i)
      table.insert(tokens, { type = "NUMBER", value = source:sub(start, i - 1), line = line })

    else
      local three = source:sub(i, i + 2)
      local two   = source:sub(i, i + 1)

      -- Luau compound assignment: ..=, //= (3 char), tapos +=, -=, *=, /=, %=, ^=,
      -- // (floor division, 2 char)
      if three == "..." then
        table.insert(tokens, { type = "OPERATOR", value = "...", line = line })
        i = i + 3
      elseif three == "..=" then
        table.insert(tokens, { type = "OPERATOR", value = "..=", line = line })
        i = i + 3
      elseif three == "//=" then
        table.insert(tokens, { type = "OPERATOR", value = "//=", line = line })
        i = i + 3
      elseif two == "==" or two == "~=" or two == "<="
          or two == ">=" or two == ".." or two == "//" then
        table.insert(tokens, { type = "OPERATOR", value = two, line = line })
        i = i + 2
      elseif two == "+=" or two == "-=" or two == "*=" or two == "/="
          or two == "%=" or two == "^=" then
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
