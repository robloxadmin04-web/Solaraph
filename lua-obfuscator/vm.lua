-- vm.lua
-- Obfuscation pass: VM-based obfuscation (subset).
--
-- IDEA: Sa halip na i-emit ang isang expression bilang normal na Lua source,
-- kino-compile ito sa BYTECODE para sa isang maliit na stack machine, tapos
-- pinapalitan ang expression ng isang tawag sa VM interpreter:
--
--    x = (a + b) * 2
--      -->
--    x = __vm({...bytecode...}, {...constants...})
--
-- Ang __vm interpreter (prelude) ang nagpapatakbo ng bytecode gamit ang value
-- stack. Parehong resulta, pero nawala ang orihinal na anyo ng expression â€”
-- ito na ang pinaka-malakas na layer dahil kailangang unawain ng attacker ang
-- buong VM bago mabasa kahit isang linya.
--
-- SAKLAW (LIGTAS/subset): kino-compile lang ang mga expression na PURONG
-- kaya ng stack machine â€” numbers, strings, booleans, variable reads,
-- unary/binary ops, at function calls kung saan simple ang callee. Kapag may
-- nakita itong hindi pa suportado (tables, method calls, varargs, function
-- literals, index/field access), IWINAN ang buong expression na buo â€” kaya
-- garantisadong hindi nasisira ang code, lumiliit lang ang saklaw.
--
-- Tumatakbo dapat HULI-HULI sa pipeline (pagkatapos ng rename/numbers) dahil
-- kino-capture nito ang variable NAMES bilang runtime lookup.

local VM = {}

-- ===== Opcodes (integer para compact) =====
local OP = {
  PUSHK  = 1,   -- push constant[operand]
  PUSHV  = 2,   -- push value ng variable na constant[operand] (string name)
  ADD=3, SUB=4, MUL=5, DIV=6, MOD=7, POW=8, CONCAT=9,
  EQ=10, NE=11, LT=12, GT=13, LE=14, GE=15,
  AND=16, OR=17,
  NEG=18, NOT=19, LEN=20,
  CALL=21,      -- operand = argc; stack: callee, arg1..argN
  TRUE=22, FALSE=23, NIL=24,
}

-- ===== Compiler: expr -> bytecode =====
-- Nagbabalik ng true kung na-compile nang buo; false kung may hindi suportado
-- (sa kasong iyon dapat iwan ng caller ang orihinal na expression).

local function newCompiler()
  return { consts = {}, code = {}, ok = true }
end

local function addConst(c, value)
  -- reuse kung existing na (maliit na optimization)
  for i, v in ipairs(c.consts) do
    if v.t == value.t and v.v == value.v then return i end
  end
  table.insert(c.consts, value)
  return #c.consts
end

local function emit(c, op, operand)
  table.insert(c.code, op)
  if operand ~= nil then table.insert(c.code, operand) end
end

local BINOP = {
  ["+"]=OP.ADD, ["-"]=OP.SUB, ["*"]=OP.MUL, ["/"]=OP.DIV, ["%"]=OP.MOD,
  [".."]=OP.CONCAT,
  ["=="]=OP.EQ, ["~="]=OP.NE, ["<"]=OP.LT, [">"]=OP.GT, ["<="]=OP.LE, [">="]=OP.GE,
  ["and"]=OP.AND, ["or"]=OP.OR,
}

local compileExpr

compileExpr = function(c, node)
  if not c.ok then return end
  local k = node.kind

  if k == "Number" then
    local n = tonumber(node.value)
    if n == nil then c.ok = false; return end
    emit(c, OP.PUSHK, addConst(c, { t = "n", v = n }))

  elseif k == "String" then
    -- kailanganin ang unquoted na laman; laktawan kung long-bracket o may escape
    local raw = node.value
    local first = raw:sub(1, 1)
    if first ~= '"' and first ~= "'" then c.ok = false; return end
    local inner = raw:sub(2, #raw - 1)
    if inner:find("\\", 1, true) then c.ok = false; return end
    emit(c, OP.PUSHK, addConst(c, { t = "s", v = inner }))

  elseif k == "Literal" then
    if node.value == "true" then emit(c, OP.TRUE)
    elseif node.value == "false" then emit(c, OP.FALSE)
    elseif node.value == "nil" then emit(c, OP.NIL)
    else c.ok = false end

  elseif k == "Variable" then
    -- HINDI suportado: ang VM ay walang access sa local scope, kaya iniiwan
    -- ang variable reads bilang normal na code.
    c.ok = false

  elseif k == "UnaryOp" then
    compileExpr(c, node.operand)
    if node.op == "-" then emit(c, OP.NEG)
    elseif node.op == "not" then emit(c, OP.NOT)
    elseif node.op == "#" then emit(c, OP.LEN)
    else c.ok = false end

  elseif k == "BinaryOp" then
    local opc = BINOP[node.op]
    if not opc then c.ok = false; return end
    compileExpr(c, node.left)
    compileExpr(c, node.right)
    emit(c, opc)

  elseif k == "Call" then
    -- HINDI suportado: nangangailangan ng scope lookup para sa callee.
    c.ok = false

  else
    -- Table, MethodCall, Index, Function, Vararg, Raw: hindi pa suportado
    c.ok = false
  end
end

-- Bumuo ng Raw node na naglalaman ng __vm(...) na tawag.
local function buildVMCall(c)
  -- bytecode array -> "{1,5,2,...}"
  local codeStr = "{" .. table.concat(c.code, ",") .. "}"

  -- constants -> "{...}" na may tamang Lua literal bawat isa
  local parts = {}
  for _, k in ipairs(c.consts) do
    if k.t == "n" then
      table.insert(parts, tostring(k.v))
    elseif k.t == "s" then
      table.insert(parts, string.format("%q", k.v))
    end
  end
  local constStr = "{" .. table.concat(parts, ",") .. "}"

  return { kind = "Raw", text = "__vm(" .. codeStr .. "," .. constStr .. ")" }
end

-- Subukang i-VM ang isang expression. Kung kaya nang buo, ibalik ang bagong
-- Raw node; kung hindi, ibalik ang orihinal (walang binago).
local function tryVMExpr(node)
  -- huwag i-VM ang trivial na node (walang saysay balutin ang isang literal/var)
  if node.kind == "Number" or node.kind == "String"
     or node.kind == "Literal" or node.kind == "Variable"
     or node.kind == "Raw" then
    return node
  end
  local c = newCompiler()
  compileExpr(c, node)
  if c.ok and #c.code > 0 then
    return buildVMCall(c)
  end
  return node
end

-- ===== Traversal: palitan ang mga expression sa buong AST =====

local walkBlock, walkStatement

-- I-VM ang isang expression slot: subukan sa buong node; kung hindi kaya,
-- pumasok sa loob para i-VM ang mga sub-expression (partial coverage).
local function walkExpr(node)
  if node == nil then return node end
  -- subukan muna ang buong node
  local replaced = tryVMExpr(node)
  if replaced ~= node then return replaced end

  -- hindi na-VM nang buo: pumasok sa mga anak para sa partial coverage
  local k = node.kind
  if k == "UnaryOp" then
    node.operand = walkExpr(node.operand)
  elseif k == "BinaryOp" then
    node.left = walkExpr(node.left)
    node.right = walkExpr(node.right)
  elseif k == "Call" then
    node.callee = walkExpr(node.callee)
    for i, a in ipairs(node.args) do node.args[i] = walkExpr(a) end
  elseif k == "MethodCall" then
    node.object = walkExpr(node.object)
    for i, a in ipairs(node.args) do node.args[i] = walkExpr(a) end
  elseif k == "Index" then
    node.object = walkExpr(node.object)
    if node.index then node.index = walkExpr(node.index) end
  elseif k == "Table" then
    for _, f in ipairs(node.fields) do
      if f.kind == "keyed" then f.key = walkExpr(f.key) end
      f.value = walkExpr(f.value)
    end
  elseif k == "Function" then
    walkBlock(node.body)
  end
  return node
end

walkStatement = function(node)
  local k = node.kind
  if k == "LocalAssignment" then
    if node.values then for i, v in ipairs(node.values) do node.values[i] = walkExpr(v) end end
  elseif k == "Assignment" then
    for i, v in ipairs(node.values) do node.values[i] = walkExpr(v) end
    -- targets: HUWAG i-VM (kailangang assignable pa rin)
  elseif k == "LocalFunction" then walkBlock(node.func.body)
  elseif k == "FunctionDeclaration" then walkBlock(node.func.body)
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do
      cl.cond = walkExpr(cl.cond); walkBlock(cl.body)
    end
    if node.elseBody then walkBlock(node.elseBody) end
  elseif k == "While" then node.cond = walkExpr(node.cond); walkBlock(node.body)
  elseif k == "Repeat" then walkBlock(node.body); node.cond = walkExpr(node.cond)
  elseif k == "Do" then walkBlock(node.body)
  elseif k == "NumericFor" then
    node.startExpr = walkExpr(node.startExpr)
    node.stopExpr = walkExpr(node.stopExpr)
    if node.stepExpr then node.stepExpr = walkExpr(node.stepExpr) end
    walkBlock(node.body)
  elseif k == "GenericFor" then
    for i, it in ipairs(node.iters) do node.iters[i] = walkExpr(it) end
    walkBlock(node.body)
  elseif k == "Return" then
    for i, v in ipairs(node.values) do node.values[i] = walkExpr(v) end
  elseif k == "CallStatement" then
    -- ang call statement mismo ay pwedeng may side-effect; i-VM lang kung
    -- ligtas â€” pero dahil nagbabalik ng value ang __vm, at ok lang itapon,
    -- i-VM natin ang loob (args) sa halip na ang buong call, para 'di masira
    -- ang mga MethodCall/multi-return semantics.
    node.call = walkExpr(node.call)
  end
end

walkBlock = function(statements)
  for _, stmt in ipairs(statements) do walkStatement(stmt) end
end

-- ===== Interpreter prelude (naka-inject sa itaas ng output) =====

function VM.prelude()
  local lines = {
    "local function __vm(code, K)",
    "  local st = {}",
    "  local sp = 0",
    "  local i = 1",
    "  local n = #code",
    "  while i <= n do",
    "    local op = code[i]; i = i + 1",
    "    if op == 1 then sp = sp + 1; st[sp] = K[code[i]]; i = i + 1",
    "    elseif op == 2 then local name = K[code[i]]; i = i + 1; sp = sp + 1; st[sp] = _ENV[name]",
    "    elseif op == 3 then st[sp-1] = st[sp-1] + st[sp]; sp = sp - 1",
    "    elseif op == 4 then st[sp-1] = st[sp-1] - st[sp]; sp = sp - 1",
    "    elseif op == 5 then st[sp-1] = st[sp-1] * st[sp]; sp = sp - 1",
    "    elseif op == 6 then st[sp-1] = st[sp-1] / st[sp]; sp = sp - 1",
    "    elseif op == 7 then st[sp-1] = st[sp-1] % st[sp]; sp = sp - 1",
    "    elseif op == 8 then st[sp-1] = st[sp-1] ^ st[sp]; sp = sp - 1",
    "    elseif op == 9 then st[sp-1] = st[sp-1] .. st[sp]; sp = sp - 1",
    "    elseif op == 10 then st[sp-1] = st[sp-1] == st[sp]; sp = sp - 1",
    "    elseif op == 11 then st[sp-1] = st[sp-1] ~= st[sp]; sp = sp - 1",
    "    elseif op == 12 then st[sp-1] = st[sp-1] < st[sp]; sp = sp - 1",
    "    elseif op == 13 then st[sp-1] = st[sp-1] > st[sp]; sp = sp - 1",
    "    elseif op == 14 then st[sp-1] = st[sp-1] <= st[sp]; sp = sp - 1",
    "    elseif op == 15 then st[sp-1] = st[sp-1] >= st[sp]; sp = sp - 1",
    "    elseif op == 16 then st[sp-1] = st[sp-1] and st[sp]; sp = sp - 1",
    "    elseif op == 17 then st[sp-1] = st[sp-1] or st[sp]; sp = sp - 1",
    "    elseif op == 18 then st[sp] = -st[sp]",
    "    elseif op == 19 then st[sp] = not st[sp]",
    "    elseif op == 20 then st[sp] = #st[sp]",
    "    elseif op == 21 then",
    "      local argc = code[i]; i = i + 1",
    "      local args = {}",
    "      for a = argc, 1, -1 do args[a] = st[sp]; sp = sp - 1 end",
    "      local fn = st[sp]; sp = sp - 1",
    "      sp = sp + 1; st[sp] = fn(table.unpack(args))",
    "    elseif op == 22 then sp = sp + 1; st[sp] = true",
    "    elseif op == 23 then sp = sp + 1; st[sp] = false",
    "    elseif op == 24 then sp = sp + 1; st[sp] = nil",
    "    end",
    "  end",
    "  return st[sp]",
    "end"
  }
  return table.concat(lines, "\n") .. "\n"
end

function VM.transform(ast)
  walkBlock(ast.body)
  return ast
end

return VM
