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

function Lexer.tokenize(source)
  local tokens = {}
  local i = 1
  local line = 1
  local len = #source

  while i <= len do
    local c = source:sub(i, i)
    local nextC = source:sub(i + 1, i + 1)  -- ang kasunod na character (para sa dalawahang simbolo)

    -- 1. Newline: bilangin ang linya
    if c == "\n" then
      line = line + 1
      i = i + 1

    -- 2. Iba pang whitespace: laktawan lang
    elseif c:match("%s") then
      i = i + 1

    -- 3. COMMENT: nagsisimula sa "--"
    elseif c == "-" and nextC == "-" then
      i = i + 2  -- laktawan ang "--"
      -- basahin hanggang katapusan ng linya, tapos itapon (hindi ginagawang token)
      while i <= len and source:sub(i, i) ~= "\n" do
        i = i + 1
      end

    -- 4. STRING: nagsisimula sa " o '
    elseif c == '"' or c == "'" then
      local quote = c          -- tandaan kung " o ' ang ginamit
      local start = i
      i = i + 1                -- laktawan ang pambukas na quote
      while i <= len and source:sub(i, i) ~= quote do
        -- kung may escape (\), laktawan ang susunod na character (hal. \" )
        if source:sub(i, i) == "\\" then
          i = i + 1
        end
        i = i + 1
      end
      i = i + 1                -- laktawan ang pansarang quote
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

    -- 6. Numero
    elseif isDigit(c) then
      local start = i
      while i <= len and (isDigit(source:sub(i, i)) or source:sub(i, i) == ".") do
        i = i + 1
      end
      table.insert(tokens, { type = "NUMBER", value = source:sub(start, i - 1), line = line })

    -- 7. Operator o simbolo (isahan muna)
    else
      table.insert(tokens, { type = "OPERATOR", value = c, line = line })
      i = i + 1
    end
  end

  table.insert(tokens, { type = "EOF", value = "<eof>", line = line })
  return tokens
end

return Lexer
