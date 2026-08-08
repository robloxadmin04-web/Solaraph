-- vm.lua
-- Obfuscation pass: FULL-PROGRAM VM (register-based, Hakbang 1+2).
--
-- Kino-compile ang mga block ng code sa REGISTER-BASED bytecode para sa isang
-- maliit na VM, tapos pinapalitan ang orihinal ng isang tawag sa interpreter:
--
--    <mga statement>  -->  __vmrun({...bytecode...}, {...constants...})
--
-- KAYA NITO (kabaligtaran ng lumang stack VM na constants-lang):
--   * local variables (registers/slots)
--   * arithmetic, concat, comparison, unary
--   * function calls na may tamang arguments
--   * global lookup (print, pairs, atbp.)
--   * if / elseif / else, while, numeric for  (via jumps)
--
-- HINDI PA (susunod na hakbang â€” closures):
--   * nested function definitions (local function / function ... end)
--   * generic for, repeat, method calls, multiple assignment >1, varargs
--   * tables, index/field access
-- Kapag may nakita nito, IWINAN ang buong block na normal (walang binago),
-- kaya garantisadong hindi nasisira ang code â€” lumiliit lang ang saklaw.
--
-- Tumatakbo dapat HULI-HULI (pagkatapos ng rename) â€” kino-capture ang GLOBAL
-- names bilang runtime lookup; ang locals ay nagiging registers.

local VM = {}

-- ===== Opcodes =====
local OP = {
  LOADK=1, MOVE=2, GETGLOBAL=3,
  ADD=4, SUB=5, MUL=6, DIV=7, MOD=8, POW=9, CONCAT=10,
  EQ=11, NE=12, LT=13, GT=14, LE=15, GE=16,
  NEG=17, NOT=18, LEN=19,
  CALL=20,       -- CALL base, argc   -> R[base] = R[base](R[base+1..base+argc])
  RETURN=21,     -- RETURN reg
  JMP=22,        -- JMP target
  JMPIFNOT=23,   -- JMPIFNOT reg, target
}

-- ===== Compiler (may exception para sa unsupported) =====

local function newCompiler()
  return {
    code = {}, K = {}, nextReg = 0,
    scopes = { {} },
    ok = true,
  }
end

local function fail(c) c.ok = false; error("__vm_unsupported", 0) end

local function addK(c, v)
  for i, e in ipairs(c.K) do
    if e.v == v and e.t == type(v) then return i end
  end
  table.insert(c.K, { v = v, t = type(v) })
  return #c.K
end

local function alloc(c) local r = c.nextReg; c.nextReg = r + 1; return r end
local function pushScope(c) table.insert(c.scopes, {}) end
local function popScope(c) table.remove(c.scopes) end
local function declare(c, name) local r = alloc(c); c.scopes[#c.scopes][name] = r; return r end
local function resolve(c, name)
  for i = #c.scopes, 1, -1 do
    local r = c.scopes[i][name]
    if r ~= nil then return r end
  end
  return nil
end
local function emit(c, ...) local t = {...}; for _, x in ipairs(t) do table.insert(c.code, x) end end
local function here(c) return #c.code end
-- emit ng jump na may placeholder na target; ibalik ang index ng operand
local function emitJmp(c) emit(c, OP.JMP, 0); return #c.code end
local function emitJmpIfNot(c, reg) emit(c, OP.JMPIFNOT, reg, 0); return #c.code end
local function patch(c, idx) c.code[idx] = here(c) end
local function patchTo(c, idx, target) c.code[idx] = target end

local BINOP = {
  ["+"]=OP.ADD, ["-"]=OP.SUB, ["*"]=OP.MUL, ["/"]=OP.DIV, ["%"]=OP.MOD, ["^"]=OP.POW,
  [".."]=OP.CONCAT, ["=="]=OP.EQ, ["~="]=OP.NE,
  ["<"]=OP.LT, [">"]=OP.GT, ["<="]=OP.LE, [">="]=OP.GE,
}

local compileExpr, compileStmt, compileBlock

compileExpr = function(c, node)
  local k = node.kind

  if k == "Number" then
    local n = tonumber(node.value); if n == nil then fail(c) end
    local r = alloc(c); emit(c, OP.LOADK, r, addK(c, n)); return r

  elseif k == "String" then
    local raw = node.value; local first = raw:sub(1,1)
    if first ~= '"' and first ~= "'" then fail(c) end
    local inner = raw:sub(2, #raw-1)
    if inner:find("\\", 1, true) then fail(c) end
    local r = alloc(c); emit(c, OP.LOADK, r, addK(c, inner)); return r

  elseif k == "Literal" then
    if node.value == "true" then local r=alloc(c); emit(c,OP.LOADK,r,addK(c,true)); return r
    elseif node.value == "false" then local r=alloc(c); emit(c,OP.LOADK,r,addK(c,false)); return r
    else fail(c) end   -- nil: laktawan (walang malinis na K rep)

  elseif k == "Variable" then
    local localReg = resolve(c, node.name)
    if localReg ~= nil then return localReg end
    local r = alloc(c); emit(c, OP.GETGLOBAL, r, addK(c, node.name)); return r

  elseif k == "BinaryOp" then
    local opc = BINOP[node.op]; if not opc then fail(c) end
    local a = compileExpr(c, node.left)
    local b = compileExpr(c, node.right)
    local r = alloc(c); emit(c, opc, r, a, b); return r

  elseif k == "UnaryOp" then
    local a = compileExpr(c, node.operand)
    local r = alloc(c)
    if node.op == "-" then emit(c, OP.NEG, r, a)
    elseif node.op == "not" then emit(c, OP.NOT, r, a)
    elseif node.op == "#" then emit(c, OP.LEN, r, a)
    else fail(c) end
    return r

  elseif k == "Call" then
    local fnReg = compileExpr(c, node.callee)
    local argRegs = {}
    for _, a in ipairs(node.args) do table.insert(argRegs, compileExpr(c, a)) end
    -- contiguous block: base = fn, base+1..base+argc = args
    local base = alloc(c); emit(c, OP.MOVE, base, fnReg)
    for _, ar in ipairs(argRegs) do local slot = alloc(c); emit(c, OP.MOVE, slot, ar) end
    emit(c, OP.CALL, base, #node.args)
    return base

  else
    fail(c)  -- MethodCall, Index, Table, Function, Vararg, Raw: hindi pa
  end
end

compileStmt = function(c, node)
  local k = node.kind

  if k == "LocalAssignment" then
    -- suportado lang ang 1:1 o values muna tapos declare
    local vals = {}
    if node.values then for _, v in ipairs(node.values) do table.insert(vals, compileExpr(c, v)) end end
    for i, name in ipairs(node.names) do
      local r = declare(c, name)
      if vals[i] ~= nil then emit(c, OP.MOVE, r, vals[i]) end
    end

  elseif k == "Assignment" then
    -- targets ay dapat simpleng local Variable
    local vals = {}
    for _, v in ipairs(node.values) do table.insert(vals, compileExpr(c, v)) end
    for i, t in ipairs(node.targets) do
      if t.kind ~= "Variable" then fail(c) end
      local r = resolve(c, t.name)
      if r == nil then fail(c) end   -- assignment sa global: hindi pa
      if vals[i] ~= nil then emit(c, OP.MOVE, r, vals[i]) end
    end

  elseif k == "CallStatement" then
    compileExpr(c, node.call)

  elseif k == "Return" then
    if #node.values == 0 then fail(c) end       -- bare return: laktawan
    if #node.values > 1 then fail(c) end        -- multi-return: hindi pa
    local r = compileExpr(c, node.values[1])
    emit(c, OP.RETURN, r)

  elseif k == "If" then
    local endJumps = {}
    for _, cl in ipairs(node.clauses) do
      local cond = compileExpr(c, cl.cond)
      local skip = emitJmpIfNot(c, cond)
      pushScope(c); compileBlock(c, cl.body); popScope(c)
      table.insert(endJumps, emitJmp(c))
      patch(c, skip)
    end
    if node.elseBody then pushScope(c); compileBlock(c, node.elseBody); popScope(c) end
    for _, j in ipairs(endJumps) do patch(c, j) end

  elseif k == "While" then
    local top = here(c)
    local cond = compileExpr(c, node.cond)
    local exit = emitJmpIfNot(c, cond)
    pushScope(c); compileBlock(c, node.body); popScope(c)
    patchTo(c, emitJmp(c), top)
    patch(c, exit)

  elseif k == "NumericFor" then
    pushScope(c)
    local v = declare(c, node.var)
    local startR = compileExpr(c, node.startExpr); emit(c, OP.MOVE, v, startR)
    local stopR = compileExpr(c, node.stopExpr)
    local stepR
    if node.stepExpr then stepR = compileExpr(c, node.stepExpr)
    else stepR = alloc(c); emit(c, OP.LOADK, stepR, addK(c, 1)) end
    local top = here(c)
    local cmp = alloc(c); emit(c, OP.LE, cmp, v, stopR)
    local exit = emitJmpIfNot(c, cmp)
    compileBlock(c, node.body)
    local nv = alloc(c); emit(c, OP.ADD, nv, v, stepR); emit(c, OP.MOVE, v, nv)
    patchTo(c, emitJmp(c), top)
    patch(c, exit)
    popScope(c)

  else
    fail(c)  -- LocalFunction, FunctionDeclaration, Repeat, GenericFor, Do, Break
  end
end

compileBlock = function(c, statements)
  for _, stmt in ipairs(statements) do compileStmt(c, stmt) end
end

-- ===== Builder: gumawa ng Raw node na __vmrun(code, K) =====

local function buildVMNode(c, paramNames)
  local codeStr = "{" .. table.concat(c.code, ",") .. "}"
  local parts = {}
  for _, e in ipairs(c.K) do
    if e.t == "number" then table.insert(parts, tostring(e.v))
    elseif e.t == "string" then table.insert(parts, string.format("%q", e.v))
    elseif e.t == "boolean" then table.insert(parts, tostring(e.v)) end
  end
  local constStr = "{" .. table.concat(parts, ",") .. "}"
  -- ang function params ay ipinapasa bilang karagdagang argumento sa __vmrun,
  -- na maglalagay sa kanila sa registers 0,1,2,... bago tumakbo ang bytecode.
  local paramList = ""
  if paramNames and #paramNames > 0 then
    paramList = "," .. table.concat(paramNames, ",")
  end
  return "__vmrun(" .. codeStr .. "," .. constStr .. paramList .. ")"
end

-- Subukang i-VM ang isang buong function body (o top-level block).
-- Kailangang MAY exactly one Return sa dulo para maging expression-able? Hindi â€”
-- gumagana rin bilang statement na itinatapon ang return. Pero para ligtas,
-- ini-VM lang natin ang mga body na nagtatapos sa Return (function bodies) O
-- puro statement (top-level, walang return).
local function tryCompileBlock(statements, params)
  local c = newCompiler()
  -- i-declare ang mga function parameter bilang unang registers (R[0], R[1], ...)
  -- para tumugma sa __vmrun na naglalagay ng passed args doon.
  local paramNames = {}
  if params then
    for _, p in ipairs(params) do
      if p == "..." then return nil end   -- varargs: hindi pa suportado
      declare(c, p)
      table.insert(paramNames, p)
    end
  end
  local ok = pcall(function() compileBlock(c, statements) end)
  if ok and c.ok and #c.code > 0 then
    return buildVMNode(c, paramNames)
  end
  return nil
end

-- ===== Traversal: palitan ang mga function body ng VM call =====

local walkBlock, walkStatement

-- Subukang i-VM ang isang function body. Kung kaya, palitan ang body ng
-- iisang statement na: return __vmrun(...) O CallStatement(__vmrun(...)).
local function tryVMFunctionBody(bodyStmts, params)
  -- kung ang huling statement ay Return, ang buong body ay expression-producing
  local last = bodyStmts[#bodyStmts]
  local vmText = tryCompileBlock(bodyStmts, params)
  if not vmText then return nil end

  if last and last.kind == "Return" then
    -- ang __vmrun ang nagbabalik ng return value
    return { { kind = "Return", values = { { kind = "Raw", text = vmText } } } }
  else
    -- puro side-effect: tawagin lang
    return { { kind = "CallStatement", call = { kind = "Raw", text = vmText } } }
  end
end

walkStatement = function(node)
  local k = node.kind
  if k == "LocalFunction" then
    local vm = tryVMFunctionBody(node.func.body, node.func.params)
    if vm then node.func.body = vm else walkBlock(node.func.body) end
  elseif k == "FunctionDeclaration" then
    local vm = tryVMFunctionBody(node.func.body, node.func.params)
    if vm then node.func.body = vm else walkBlock(node.func.body) end
  elseif k == "If" then
    for _, cl in ipairs(node.clauses) do walkBlock(cl.body) end
    if node.elseBody then walkBlock(node.elseBody) end
  elseif k == "While" then walkBlock(node.body)
  elseif k == "Repeat" then walkBlock(node.body)
  elseif k == "Do" then walkBlock(node.body)
  elseif k == "NumericFor" then walkBlock(node.body)
  elseif k == "GenericFor" then walkBlock(node.body)
  end
end

walkBlock = function(statements)
  for _, stmt in ipairs(statements) do walkStatement(stmt) end
end

-- ===== Interpreter prelude =====

function VM.prelude()
  local L = {
    "local function __vmrun(code, K, ...)",
    "  local R = {}",
    "  local __args = {...}",
    "  for __p = 1, select('#', ...) do R[__p - 1] = __args[__p] end",
    "  local i = 1",
    "  local n = #code",
    "  while i <= n do",
    "    local op = code[i]; i = i + 1",
    "    if op == 1 then R[code[i]] = K[code[i+1]]; i = i + 2",              -- LOADK
    "    elseif op == 2 then R[code[i]] = R[code[i+1]]; i = i + 2",         -- MOVE
    "    elseif op == 3 then R[code[i]] = _ENV[K[code[i+1]]]; i = i + 2",   -- GETGLOBAL
    "    elseif op == 4 then R[code[i]] = R[code[i+1]] + R[code[i+2]]; i = i + 3",   -- ADD
    "    elseif op == 5 then R[code[i]] = R[code[i+1]] - R[code[i+2]]; i = i + 3",   -- SUB
    "    elseif op == 6 then R[code[i]] = R[code[i+1]] * R[code[i+2]]; i = i + 3",   -- MUL
    "    elseif op == 7 then R[code[i]] = R[code[i+1]] / R[code[i+2]]; i = i + 3",   -- DIV
    "    elseif op == 8 then R[code[i]] = R[code[i+1]] % R[code[i+2]]; i = i + 3",   -- MOD
    "    elseif op == 9 then R[code[i]] = R[code[i+1]] ^ R[code[i+2]]; i = i + 3",   -- POW
    "    elseif op == 10 then R[code[i]] = R[code[i+1]] .. R[code[i+2]]; i = i + 3", -- CONCAT
    "    elseif op == 11 then R[code[i]] = R[code[i+1]] == R[code[i+2]]; i = i + 3", -- EQ
    "    elseif op == 12 then R[code[i]] = R[code[i+1]] ~= R[code[i+2]]; i = i + 3", -- NE
    "    elseif op == 13 then R[code[i]] = R[code[i+1]] < R[code[i+2]]; i = i + 3",  -- LT
    "    elseif op == 14 then R[code[i]] = R[code[i+1]] > R[code[i+2]]; i = i + 3",  -- GT
    "    elseif op == 15 then R[code[i]] = R[code[i+1]] <= R[code[i+2]]; i = i + 3", -- LE
    "    elseif op == 16 then R[code[i]] = R[code[i+1]] >= R[code[i+2]]; i = i + 3", -- GE
    "    elseif op == 17 then R[code[i]] = -R[code[i+1]]; i = i + 2",       -- NEG
    "    elseif op == 18 then R[code[i]] = not R[code[i+1]]; i = i + 2",    -- NOT
    "    elseif op == 19 then R[code[i]] = #R[code[i+1]]; i = i + 2",       -- LEN
    "    elseif op == 20 then",                                            -- CALL
    "      local base = code[i]; local argc = code[i+1]; i = i + 2",
    "      local fn = R[base]",
    "      local args = {}",
    "      for a = 1, argc do args[a] = R[base + a] end",
    "      R[base] = fn(table.unpack(args))",
    "    elseif op == 21 then return R[code[i]]",                          -- RETURN
    "    elseif op == 22 then i = code[i]",                                -- JMP
    "    elseif op == 23 then",                                           -- JMPIFNOT
    "      local reg = code[i]; local target = code[i+1]; i = i + 2",
    "      if not R[reg] then i = target end",
    "    end",
    "  end",
    "end",
  }
  return table.concat(L, "\n") .. "\n"
end

function VM.transform(ast)
  walkBlock(ast.body)
  return ast
end

return VM
