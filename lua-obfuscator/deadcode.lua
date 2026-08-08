-- deadcode.lua
-- Obfuscation pass: dead code injection.
-- Nagsisingit ng mga statement na hindi kailanman tatakbo (`if false then ... end`,
-- o `while false do ... end`) na may random na garbage sa loob. Semantically inert:
-- 'di nagbabago ng behavior ng program, pinapalabo lang ang static analysis.
--
-- Tugma sa AST ng parser.lua. Ang mga injected node ay gumagamit ng existing
-- node kinds (If, While, LocalAssignment, CallStatement, Raw) para 100% na
-- ma-generate ng generator.lua nang walang bagong branch na kailangan.
--
-- Ligtas na disenyo:
--  * Guard ay literal `false` -> garantisadong dead ang branch.
--  * Ang mga fake na variable ay may prefix na "_dead" para 'di sumalpok sa
--    scope-aware rename (tumatakbo ito PAGKATAPOS ng renamer sa pipeline).
--  * Walang side-effect na global na tinatawag; puro local dummy lang.

local DeadCode = {}

local INJECT_CHANCE = 0.5   -- posibilidad na magsingit bago ang isang statement

local deadCounter = 0
local function deadName()
  deadCounter = deadCounter + 1
  return "_dead" .. deadCounter
end

-- ---------- mga fake garbage builder (lahat ay valid AST node) ----------

local function randInt(a, b) return math.random(a, b) end

-- gumawa ng random na arithmetic Raw expression, hal. "(48 % 7 + 12)"
local function junkExpr()
  local a, b, c = randInt(2, 99), randInt(2, 20), randInt(1, 50)
  local forms = {
    "(" .. a .. " * " .. b .. " - " .. c .. ")",
    "(" .. a .. " % " .. (b + 1) .. " + " .. c .. ")",
    "(" .. a .. " + " .. b .. " * " .. c .. ")",
  }
  return { kind = "Raw", text = forms[randInt(1, #forms)] }
end

-- local _deadN = <junk>
local function junkLocal()
  return {
    kind = "LocalAssignment",
    names = { deadName() },
    values = { junkExpr() },
  }
end

-- _deadN = _deadN + <junk>   (assignment sa sariling fake var — inert)
local function junkAssign(name)
  return {
    kind = "Assignment",
    targets = { { kind = "Variable", name = name } },
    values = { { kind = "Raw", text = "(" .. randInt(1, 999) .. ")" } },
  }
end

-- Gumawa ng dead block body: 1-3 na garbage statement.
local function deadBody()
  local body = {}
  local n = randInt(1, 3)
  local lastName = nil
  for _ = 1, n do
    if lastName and math.random() < 0.5 then
      table.insert(body, junkAssign(lastName))
    else
      local stmt = junkLocal()
      lastName = stmt.names[1]
      table.insert(body, stmt)
    end
  end
  return body
end

-- Gumawa ng isang dead statement — random sa dalawang anyo.
local function makeDeadStatement()
  if math.random() < 0.5 then
    -- if false then ... end
    return {
      kind = "If",
      clauses = { { cond = { kind = "Literal", value = "false" }, body = deadBody() } },
      elseBody = nil,
    }
  else
    -- while false do ... end
    return {
      kind = "While",
      cond = { kind = "Literal", value = "false" },
      body = deadBody(),
    }
  end
end

-- ---------- traversal: mag-inject sa bawat block ----------

local injectBlock, injectStatement

-- Bumuo ng bagong statement list na may naka-inj, tapos i-recurse sa loob.
injectBlock = function(statements)
  local out = {}
  for _, stmt in ipairs(statements) do
    -- huwag maglagay ng dead code pagkatapos ng Return/Break sa loob ng iisang
    -- block dahil pinuputol ng parser ang block doon — pero dahil nasa harap
    -- tayo nagsisingit, ligtas: ilagay ang junk BAGO ang statement.
    if math.random() < INJECT_CHANCE then
      table.insert(out, makeDeadStatement())
    end
    injectStatement(stmt)   -- i-recurse muna sa nested blocks
    table.insert(out, stmt)
  end
  -- palitan ang laman ng orihinal na table in-place
  for i = 1, #statements do statements[i] = nil end
  for i = 1, #out do statements[i] = out[i] end
  return statements
end

injectStatement = function(node)
  local k = node.kind
  if k == "LocalFunction" then injectBlock(node.func.body)
  elseif k == "FunctionDeclaration" then injectBlock(node.func.body)
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do injectBlock(cl.body) end
    if node.elseBody then injectBlock(node.elseBody) end
  elseif k == "While" then injectBlock(node.body)
  elseif k == "Repeat" then injectBlock(node.body)
  elseif k == "Do" then injectBlock(node.body)
  elseif k == "NumericFor" then injectBlock(node.body)
  elseif k == "GenericFor" then injectBlock(node.body)
  end
  -- expression-level statements: walang nested block, walang gagawin
end

function DeadCode.inject(ast)
  injectBlock(ast.body)
  return ast
end

return DeadCode
