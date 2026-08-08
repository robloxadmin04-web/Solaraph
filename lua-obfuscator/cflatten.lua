-- cflatten.lua
-- Obfuscation pass: control-flow flattening (LIGTAS/conservative na bersyon).
--
-- IDEA: Ang isang tuwid na pagkakasunod ng mga statement ay ginagawang
-- state machine sa loob ng isang `while` loop na may dispatcher:
--
--   a()            local _state = 1
--   b()     -->    while _state ~= 0 do
--   c()              if _state == 1 then a() _state = 2
--                    elseif _state == 2 then b() _state = 3
--                    elseif _state == 3 then c() _state = 0
--                    end
--                  end
--
-- Parehong resulta, pero nawala ang tuwid na daloy.
--
-- BAKIT "LIGTAS":
--  * Hindi hinahati ang mga statement na may sariling control flow palabas
--    (Return, Break) â€” kapag may nakita nito sa isang sequence, ang buong
--    natitirang bahagi mula doon ay inilalagay sa iisang huling state, kaya
--    hindi nasisira ang semantics ng return/break.
--  * Recursive: pinapasok nito ang loob ng function/if/for/while/do para
--    ma-flatten din ang mga nested block.
--  * Ang state variable ay may prefix na "_cf" para hindi sumalpok sa scope
--    (tumatakbo ito pagkatapos ng renamer sa pipeline).
--  * Kailangan ng >= MIN_RUN na magkakasunod na "flat" na statement bago
--    mag-flatten â€” kung wala, iniiwan buo (walang saysay i-flatten ang 1-2).

local CFlatten = {}

local MIN_RUN = 3   -- pinakamababang haba ng sequence na fla-flatten-in

local cfCounter = 0
local function stateVar()
  cfCounter = cfCounter + 1
  return "_cf" .. cfCounter
end

-- Ang mga statement na "control-terminating": kapag nakita, huminto ang run.
local function isTerminator(node)
  return node.kind == "Return" or node.kind == "Break"
end

-- Ang mga statement na gumagawa ng LOCAL scope. HINDI ligtas biyakin ang mga
-- ito sa magkakahiwalay na state ng dispatcher: ang bawat clause ng if/elseif
-- ay may sariling scope, kaya ang local na idineklara sa isang state ay HINDI
-- na makikita ng ibang state (nagiging nil / global). Kaya ituturing itong
-- "hindi maaaring i-flatten" â€” iniiwan buo sa labas ng dispatcher.
local function makesLocal(node)
  return node.kind == "LocalAssignment" or node.kind == "LocalFunction"
end

-- Maaari bang isama ang statement sa isang fla-flatten na run?
-- HINDI kung terminator (return/break) o kung gumagawa ito ng local.
local function isFlattenable(node)
  return not isTerminator(node) and not makesLocal(node)
end

local flattenBlock

-- I-flatten ang isang listahan ng "flat" na statement (walang terminator sa gitna)
-- tungo sa isang dispatcher na `While`. Nagbabalik ng ISANG statement node.
-- shuffledOrder: para hindi 1,2,3 ang state, ginagawang random ang assignment.
local function buildDispatcher(stmts)
  local n = #stmts
  local sv = stateVar()

  -- gumawa ng random na state ID para sa bawat hakbang (1..n), tapos shuffle
  local ids = {}
  for i = 1, n do ids[i] = i end
  -- Fisher-Yates shuffle ng LABELS (hindi ng pagkakasunod ng pag-execute)
  local labels = {}
  for i = 1, n do labels[i] = i end
  for i = n, 2, -1 do
    local j = math.random(1, i)
    labels[i], labels[j] = labels[j], labels[i]
  end
  -- labels[k] = state number na kumakatawan sa k-th na hakbang

  -- Buuin ang mga clause ng if/elseif. Bawat hakbang k:
  --   if _cf == labels[k] then <stmt k> ; _cf = labels[k+1] (o 0 kung huli)
  local clauses = {}
  for k = 1, n do
    local thisLabel = labels[k]
    local nextLabel = (k < n) and labels[k + 1] or 0

    local body = {}
    table.insert(body, stmts[k])
    table.insert(body, {
      kind = "Assignment",
      targets = { { kind = "Variable", name = sv } },
      values  = { { kind = "Raw", text = tostring(nextLabel) } },
    })

    table.insert(clauses, {
      cond = {
        kind = "BinaryOp", op = "==",
        left  = { kind = "Variable", name = sv },
        right = { kind = "Raw", text = tostring(thisLabel) },
      },
      body = body,
    })
  end

  -- ang inisyal na state ay ang label ng UNANG hakbang
  local initState = labels[1]

  -- Ang buong dispatcher, binalot sa isang Do block para sarili ang scope
  -- ng state variable:
  --   do
  --     local _cf = <initState>
  --     while _cf ~= 0 do
  --       if _cf == ... then ... elseif ... end
  --     end
  --   end
  local ifNode = { kind = "If", clauses = clauses, elseBody = nil }

  local whileBody = { ifNode }
  local whileNode = {
    kind = "While",
    cond = {
      kind = "BinaryOp", op = "~=",
      left  = { kind = "Variable", name = sv },
      right = { kind = "Raw", text = "0" },
    },
    body = whileBody,
  }

  local doBody = {
    { kind = "LocalAssignment", names = { sv },
      values = { { kind = "Raw", text = tostring(initState) } } },
    whileNode,
  }

  return { kind = "Do", body = doBody }
end

-- I-flatten ang isang buong block (listahan ng statement).
-- Hinahati ito sa "runs" ng magkakasunod na non-terminator, flat na statement.
flattenBlock = function(statements)
  -- Una: recurse sa loob ng bawat statement para ma-flatten ang nested blocks.
  for _, stmt in ipairs(statements) do
    local k = stmt.kind
    if k == "LocalFunction" then flattenBlock(stmt.func.body)
    elseif k == "FunctionDeclaration" then flattenBlock(stmt.func.body)
    elseif k == "If" then
      for _, cl in ipairs(stmt.clauses) do flattenBlock(cl.body) end
      if stmt.elseBody then flattenBlock(stmt.elseBody) end
    elseif k == "While" then flattenBlock(stmt.body)
    elseif k == "Repeat" then flattenBlock(stmt.body)
    elseif k == "Do" then flattenBlock(stmt.body)
    elseif k == "NumericFor" then flattenBlock(stmt.body)
    elseif k == "GenericFor" then flattenBlock(stmt.body)
    end
  end

  -- Pangalawa: hatiin ang block sa runs at i-flatten ang bawat sapat-na-haba na run.
  local out = {}
  local run = {}

  local function flushRun()
    if #run >= MIN_RUN then
      table.insert(out, buildDispatcher(run))
    else
      for _, s in ipairs(run) do table.insert(out, s) end
    end
    run = {}
  end

  for _, stmt in ipairs(statements) do
    if isFlattenable(stmt) then
      -- ligtas na isama sa kasalukuyang run
      table.insert(run, stmt)
    else
      -- terminator O local-declaration: isara ang run BAGO ito, ilagay itong buo
      flushRun()
      table.insert(out, stmt)
    end
  end
  flushRun()

  -- palitan ang laman ng orihinal na table in-place
  for i = 1, #statements do statements[i] = nil end
  for i = 1, #out do statements[i] = out[i] end
  return statements
end

function CFlatten.flatten(ast)
  flattenBlock(ast.body)
  return ast
end

return CFlatten
