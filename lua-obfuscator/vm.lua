-- vm.lua
-- Obfuscation pass: FULL-PROGRAM VM (register-based, may closures/upvalues).
--
-- Kino-compile ang BUONG program tungo sa isang tree ng register-based protos
-- para sa isang maliit na VM, tapos pinapalitan ang buong AST body ng __vmmain().
-- Gumagamit ng free-register STACK DISCIPLINE (Lua/Guile style): ang callee at
-- args ng isang call ay palaging nasa contiguous slots sa tuktok, walang buhay
-- na value sa ibaba. Ang mga captured local ay naka-cell mula birth (upvalues).
--
-- KAYA NITO:
--   * local variables (registers) + function parameters
--   * arithmetic, concat, comparison, unary
--   * function calls, NESTED calls sa loob ng expressions
--   * global lookup + assignment
--   * if/elseif/else, while, numeric for
--   * NESTED functions (local function / function literal) + upvalues + recursion
--
-- SAFE FALLBACK: kung may nakitang hindi suportado (method call, table, index,
-- generic for, repeat, multi-assign, varargs, multi-return, break), itinatapon
-- ang buong pagtatangka at iniiwan ang program na normal â€” hindi masisira.
--
-- Tumatakbo dapat HULI-HULI (pagkatapos ng rename).

local VM = {}

local UNSUPPORTED = "__vm_unsupported"
local function fail() error(UNSUPPORTED, 0) end

local protos
local __keysrc
local OPMAP    -- logical opcode (1..36) -> physical number (random per build)
local function buildOpMap(seed)
  local n = 36
  local phys = {}
  for i = 1, n do phys[i] = i end
  local s = seed % 2147483648
  local function rnd() s = (s * 1103515245 + 12345) % 2147483648; return s end
  for i = n, 2, -1 do
    local j = (rnd() % i) + 1
    phys[i], phys[j] = phys[j], phys[i]
  end
  OPMAP = {}
  for logical = 1, n do OPMAP[logical] = phys[logical] end
end
local function resetProtos()
  protos = {}
  __keysrc = os.time() % 2147483647
  buildOpMap(os.time() * 2654435761 % 2147483648)
end
local function nextKey()
  __keysrc = (__keysrc * 1103515245 + 12345) % 2147483648
  return (__keysrc // 256) % 65536
end
local function addProto(p) table.insert(protos, p); return #protos end

-- ===== Compiler =====
local Compiler = {}
Compiler.__index = Compiler

local function newCompiler(parent)
  return setmetatable({
    code = {}, K = {},
    free = 0, nlocals = 0, np = 0,
    scopes = { {} },
    parent = parent,
    upvals = {}, captured = {}, boxed = {},
    lstack = {},
  }, Compiler)
end

function Compiler:addK(v)
  for i, e in ipairs(self.K) do if e.v == v and e.t == type(v) then return i end end
  table.insert(self.K, { v = v, t = type(v) }); return #self.K
end
function Compiler:reserve(n) local r = self.free; self.free = self.free + n; return r end
function Compiler:pushScope() table.insert(self.scopes, {}); table.insert(self.lstack, self.nlocals) end
function Compiler:popScope() table.remove(self.scopes); self.nlocals = table.remove(self.lstack); self.free = self.nlocals end
function Compiler:declare(name)
  local r = self.nlocals
  self.scopes[#self.scopes][name] = r
  self.nlocals = self.nlocals + 1
  if self.free < self.nlocals then self.free = self.nlocals end
  return r
end
function Compiler:resolveLocal(name)
  for i = #self.scopes, 1, -1 do local r = self.scopes[i][name]; if r ~= nil then return r end end
  return nil
end
function Compiler:resolveUpval(name)
  if self.captured[name] ~= nil then return self.captured[name] end
  if not self.parent then return nil end
  local pl = self.parent:resolveLocal(name)
  if pl ~= nil then
    self.parent.boxed[pl] = true
    local idx = #self.upvals + 1
    self.upvals[idx] = { fromLocal = pl }; self.captured[name] = idx; return idx
  end
  local pu = self.parent:resolveUpval(name)
  if pu ~= nil then
    local idx = #self.upvals + 1
    self.upvals[idx] = { fromUpval = pu }; self.captured[name] = idx; return idx
  end
  return nil
end
function Compiler:emit(...) local t = {...}; for _, x in ipairs(t) do table.insert(self.code, x) end end
function Compiler:here() return #self.code end
function Compiler:emitJmp() self:emit(OPMAP[24], 0); return #self.code end
function Compiler:emitJmpIfNot(reg) self:emit(OPMAP[25], reg, 0); return #self.code end
function Compiler:patch(idx) self.code[idx] = self:here() + 1 end
function Compiler:patchTo(idx, target) self.code[idx] = target end
function Compiler:refVar(name)
  local l = self:resolveLocal(name); if l ~= nil then return "local", l end
  local u = self:resolveUpval(name); if u ~= nil then return "upval", u end
  return "global", nil
end

local BINOP = {
  ["+"]=5, ["-"]=6, ["*"]=7, ["/"]=8, ["%"]=9, ["^"]=10, [".."]=11,
  ["=="]=12, ["~="]=13, ["<"]=14, [">"]=15, ["<="]=16, [">="]=17,
}

local compileFunction

function Compiler:ceTop(node)
  local dest = self:reserve(1)
  self:ceInto(node, dest)
  return dest
end

function Compiler:ceTopMulti(node)
  -- parang ceTop pero kung Call, kunin LAHAT ng results (want=-1) sa isang slot
  if node.kind == "Call" then
    local saved = self.free
    local base = self:ceTop(node.callee)
    for _, arg in ipairs(node.args) do self:ceTop(arg) end
    self:emit(OPMAP[21], base, #node.args, -1)
    self.free = saved + 1
    return base
  end
  return self:ceTop(node)
end

function Compiler:ceInto(node, dest)
  local k = node.kind

  if k == "Number" then
    local n = tonumber(node.value); if n == nil then fail() end
    self:emit(OPMAP[1], dest, self:addK(n))

  elseif k == "String" then
    local raw = node.value; local first = raw:sub(1,1)
    if first ~= '"' and first ~= "'" then fail() end
    local inner = raw:sub(2, #raw-1)
    if inner:find("\\", 1, true) then fail() end
    self:emit(OPMAP[1], dest, self:addK(inner))

  elseif k == "Literal" then
    if node.value == "true" then self:emit(OPMAP[1], dest, self:addK(true))
    elseif node.value == "false" then self:emit(OPMAP[1], dest, self:addK(false))
    else fail() end

  elseif k == "Variable" then
    local kind, x = self:refVar(node.name)
    if kind == "local" then self:emit(OPMAP[2], dest, x)
    elseif kind == "upval" then self:emit(OPMAP[27], dest, x)
    else self:emit(OPMAP[3], dest, self:addK(node.name)) end

  elseif k == "BinaryOp" then
    local opc = BINOP[node.op]; if not opc then fail() end; opc = OPMAP[opc]
    local saved = self.free
    local a = self:ceTop(node.left)
    local b = self:ceTop(node.right)
    self:emit(opc, dest, a, b)
    self.free = saved; if self.free < dest + 1 then self.free = dest + 1 end

  elseif k == "UnaryOp" then
    local saved = self.free
    local a = self:ceTop(node.operand)
    if node.op == "-" then self:emit(OPMAP[18], dest, a)
    elseif node.op == "not" then self:emit(OPMAP[19], dest, a)
    elseif node.op == "#" then self:emit(OPMAP[20], dest, a)
    else fail() end
    self.free = saved; if self.free < dest + 1 then self.free = dest + 1 end

  elseif k == "Call" then
    local saved = self.free
    local base = self:ceTop(node.callee)
    for _, arg in ipairs(node.args) do self:ceTop(arg) end
    self:emit(OPMAP[21], base, #node.args, 1)
    self.free = saved
    if base ~= dest then self:emit(OPMAP[2], dest, base) end
    if self.free < dest + 1 then self.free = dest + 1 end

  elseif k == "Function" then
    local pi = compileFunction(self, node.params, node.body)
    self:emit(OPMAP[26], dest, pi)

  elseif k == "Table" then
    self:emit(OPMAP[29], dest)
    local arrayIdx = 1
    for _, f in ipairs(node.fields) do
      local saved = self.free
      local keyReg, valReg
      if f.kind == "array" then
        keyReg = self:ceTop({ kind = "Number", value = tostring(arrayIdx) }); arrayIdx = arrayIdx + 1
        valReg = self:ceTop(f.value)
      elseif f.kind == "named" then
        keyReg = self:ceTop({ kind = "String", value = string.format("%q", f.name) })
        valReg = self:ceTop(f.value)
      else
        keyReg = self:ceTop(f.key)
        valReg = self:ceTop(f.value)
      end
      self:emit(OPMAP[31], dest, keyReg, valReg)
      self.free = saved
    end
    if self.free < dest + 1 then self.free = dest + 1 end

  elseif k == "Index" then
    local saved = self.free
    local obj = self:ceTop(node.object)
    local keyReg
    if node.field ~= nil then keyReg = self:ceTop({ kind = "String", value = string.format("%q", node.field) })
    else keyReg = self:ceTop(node.index) end
    self:emit(OPMAP[30], dest, obj, keyReg)
    self.free = saved; if self.free < dest + 1 then self.free = dest + 1 end

  elseif k == "Vararg" then
    self:emit(OPMAP[36], dest, 1)

  elseif k == "MethodCall" then
    local saved = self.free
    local objReg = self:ceTop(node.object)
    local base = self:reserve(1)
    self:reserve(1)
    self:emit(OPMAP[32], base, objReg, self:addK(node.method))
    for _, arg in ipairs(node.args) do self:ceTop(arg) end
    self:emit(OPMAP[21], base, #node.args + 1, 1)
    self.free = saved
    if base ~= dest then self:emit(OPMAP[2], dest, base) end
    if self.free < dest + 1 then self.free = dest + 1 end

  else
    fail()
  end
end

function Compiler:compileStmt(node)
  local k = node.kind

  if k == "LocalAssignment" then
    local vs = {}
    if node.values then for _, v in ipairs(node.values) do table.insert(vs, self:ceTop(v)) end end
    local regs = {}
    for _, name in ipairs(node.names) do table.insert(regs, self:declare(name)) end
    for i = 1, #node.names do if vs[i] ~= nil then self:emit(OPMAP[2], regs[i], vs[i]) end end
    self.free = self.nlocals

  elseif k == "LocalFunction" then
    local r = self:declare(node.name)
    local pi = compileFunction(self, node.func.params, node.func.body)
    self:emit(OPMAP[26], r, pi)
    self.free = self.nlocals

  elseif k == "Assignment" then
    if #node.targets ~= #node.values then fail() end
    local saved = self.free
    local vs = {}
    for _, v in ipairs(node.values) do table.insert(vs, self:ceTop(v)) end
    for i, t in ipairs(node.targets) do
      if t.kind == "Variable" then
        local kind, x = self:refVar(t.name)
        if kind == "local" then self:emit(OPMAP[2], x, vs[i])
        elseif kind == "upval" then self:emit(OPMAP[28], vs[i], x)
        else self:emit(OPMAP[4], vs[i], self:addK(t.name)) end
      elseif t.kind == "Index" then
        local s2 = self.free
        local obj = self:ceTop(t.object)
        local keyReg
        if t.field ~= nil then keyReg = self:ceTop({ kind = "String", value = string.format("%q", t.field) })
        else keyReg = self:ceTop(t.index) end
        self:emit(OPMAP[31], obj, keyReg, vs[i])
        self.free = s2
      else fail() end
    end
    self.free = saved

  elseif k == "CallStatement" then
    local saved = self.free; self:ceTop(node.call); self.free = saved

  elseif k == "Return" then
    if #node.values == 0 then self:emit(OPMAP[23])
    elseif #node.values == 1 and node.values[1].kind ~= "Vararg" and node.values[1].kind ~= "Call" then
      local saved = self.free; local r = self:ceTop(node.values[1]); self:emit(OPMAP[22], r); self.free = saved
    else
      local saved = self.free; local base = self.free; local n = 0
      for idx, val in ipairs(node.values) do
        local isLast = (idx == #node.values)
        if val.kind == "Vararg" then local d = self:reserve(1); self:emit(OPMAP[36], d, 1); n = n + 1
        elseif val.kind == "Call" and isLast then self:ceTopMulti(val); n = n + 1
        else self:ceTop(val); n = n + 1 end
      end
      self:emit(OPMAP[35], base, n)
      self.free = saved
    end

  elseif k == "If" then
    local endJumps = {}
    for _, cl in ipairs(node.clauses) do
      local saved = self.free
      local cond = self:ceTop(cl.cond)
      local skip = self:emitJmpIfNot(cond)
      self.free = saved
      self:pushScope(); self:compileBlock(cl.body); self:popScope()
      table.insert(endJumps, self:emitJmp())
      self:patch(skip)
    end
    if node.elseBody then self:pushScope(); self:compileBlock(node.elseBody); self:popScope() end
    for _, j in ipairs(endJumps) do self:patch(j) end

  elseif k == "While" then
    local top = self:here() + 1
    local saved = self.free
    local cond = self:ceTop(node.cond)
    local exit = self:emitJmpIfNot(cond)
    self.free = saved
    self:pushScope(); self:compileBlock(node.body); self:popScope()
    self:patchTo(self:emitJmp(), top)
    self:patch(exit)

  elseif k == "NumericFor" then
    self:pushScope()
    local v = self:declare(node.var)
    local saved = self.free
    local st = self:ceTop(node.startExpr); self:emit(OPMAP[2], v, st); self.free = saved
    local stopReg = self:declare("(stop)")
    local s1 = self:ceTop(node.stopExpr); self:emit(OPMAP[2], stopReg, s1); self.free = self.nlocals
    local stepReg = self:declare("(step)")
    if node.stepExpr then
      local s2 = self:ceTop(node.stepExpr); self:emit(OPMAP[2], stepReg, s2); self.free = self.nlocals
    else
      self:emit(OPMAP[1], stepReg, self:addK(1))
    end
    local top = self:here() + 1
    local saved2 = self.free
    local cmp = self:reserve(1); self:emit(OPMAP[16], cmp, v, stopReg)
    local exit = self:emitJmpIfNot(cmp)
    self.free = saved2
    self:compileBlock(node.body)
    self:emit(OPMAP[5], v, v, stepReg)
    self:patchTo(self:emitJmp(), top)
    self:patch(exit)
    self:popScope()

  elseif k == "Do" then
    self:pushScope(); self:compileBlock(node.body); self:popScope()

  elseif k == "Repeat" then
    self:pushScope()
    local top = self:here() + 1
    self:compileBlock(node.body)
    local sf = self.free
    local cond = self:ceTop(node.cond)
    self:emit(OPMAP[25], cond, top)   -- JMPIFNOT cond -> top (ulitin kung false)
    self.free = sf
    self:popScope()

  elseif k == "MultiAssign" then
    local saved = self.free
    local valRegs = {}
    for _, v in ipairs(node.values) do table.insert(valRegs, self:ceTop(v)) end
    for idx, t in ipairs(node.targets) do
      local vr = valRegs[idx]
      if vr ~= nil then
        if t.kind == "Variable" then
          local kind, x = self:refVar(t.name)
          if kind == "local" then self:emit(OPMAP[2], x, vr)
          elseif kind == "upval" then self:emit(OPMAP[28], vr, x)
          else self:emit(OPMAP[4], vr, self:addK(t.name)) end
        elseif t.kind == "Index" then
          local s2 = self.free
          local obj = self:ceTop(t.object)
          local keyReg
          if t.field ~= nil then keyReg = self:ceTop({ kind = "String", value = string.format("%q", t.field) })
          else keyReg = self:ceTop(t.index) end
          self:emit(OPMAP[31], obj, keyReg, vr)
          self.free = s2
        end
      end
    end
    self.free = saved

  elseif k == "GenericFor" then
    -- Generic-for is virtualized only for the canonical Roblox-safe pairs/ipairs shape.
    -- All other iterator shapes intentionally fail so VM.transform() safely falls back
    -- to the original AST instead of producing incorrect semantics.
    if #node.iters ~= 1 then fail() end
    local iter = node.iters[1]
    if not iter or iter.kind ~= "Call" or not iter.callee or iter.callee.kind ~= "Variable" then fail() end
    local iterName = iter.callee.name
    if iterName ~= "pairs" and iterName ~= "ipairs" then fail() end

    self:pushScope()
    local fReg = self:declare("(f)")
    local stateReg = self:declare("(state)")
    local ctrlReg = self:declare("(ctrl)")

    -- pairs(t)/ipairs(t) returns iterator, state, initial-control.
    local saved = self.free
    local initBase = self:reserve(3)
    local callee = self:ceTop(iter.callee)
    for _, arg in ipairs(iter.args) do self:ceTop(arg) end
    self:emit(OPMAP[21], callee, #iter.args, 3)
    self:emit(OPMAP[2], fReg, callee)
    self:emit(OPMAP[2], stateReg, callee + 1)
    self:emit(OPMAP[2], ctrlReg, callee + 2)
    self.free = self.nlocals

    local varRegs = {}
    for _, nm in ipairs(node.names) do table.insert(varRegs, self:declare(nm)) end
    local top = self:here() + 1
    local sf2 = self.free
    local callBase = self:reserve(#node.names)
    self:emit(OPMAP[33], callBase, fReg, stateReg, ctrlReg, #node.names)
    for idx, nm in ipairs(node.names) do
      self:emit(OPMAP[2], varRegs[idx], callBase + idx - 1)
    end
    if #node.names > 0 then self:emit(OPMAP[2], ctrlReg, callBase) end
    self.free = sf2
    local exit = self:emitJmpIfNot(varRegs[1])
    self.free = self.nlocals
    self:compileBlock(node.body)
    self:patchTo(self:emitJmp(), top)
    self:patch(exit)
    self:popScope()

  else
    fail()
  end
end

function Compiler:compileBlock(statements)
  for _, stmt in ipairs(statements) do self:compileStmt(stmt); self.free = self.nlocals end
end

local function encryptCode(code, key)
  local out = {}
  for i = 1, #code do out[i] = (code[i] ~ key) end
  return out
end
local function checksum(code)
  local h = 5381
  for i = 1, #code do h = (h * 33 + code[i]) % 2147483647 end
  return h
end
compileFunction = function(parent, params, body)
  local c = newCompiler(parent)
  for _, p in ipairs(params) do if p == "..." then fail() end; c:declare(p) end
  c.np = #params
  c:compileBlock(body)
  c:emit(OPMAP[23])
  local key = nextKey()
  local enc = encryptCode(c.code, key)
  return addProto({ code = enc, K = c.K, upvals = c.upvals, boxed = c.boxed, np = c.np, key = key, sum = checksum(enc) })
end

-- ===== Serialize proto tree -> Lua data literal =====

local function serializeK(K)
  local parts = {}
  for _, e in ipairs(K) do
    if e.t == "number" then table.insert(parts, tostring(e.v))
    elseif e.t == "string" then table.insert(parts, string.format("%q", e.v))
    elseif e.t == "boolean" then table.insert(parts, tostring(e.v)) end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function serializeBoxed(boxed)
  local parts = {}
  for reg in pairs(boxed) do table.insert(parts, "[" .. reg .. "]=true") end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function serializeUpvals(ups)
  local parts = {}
  for _, u in ipairs(ups) do
    if u.fromLocal ~= nil then table.insert(parts, "{l=" .. u.fromLocal .. "}")
    else table.insert(parts, "{u=" .. u.fromUpval .. "}") end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function serializeProtos()
  local parts = {}
  for _, p in ipairs(protos) do
    table.insert(parts, "{c={" .. table.concat(p.code, ",") .. "},k=" .. serializeK(p.K)
      .. ",u=" .. serializeUpvals(p.upvals) .. ",b=" .. serializeBoxed(p.boxed)
      .. ",np=" .. (p.np or 0) .. ",key=" .. p.key .. ",sum=" .. p.sum .. "}")
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function VM.transform(ast)
  resetProtos()
  local ok, res = pcall(function()
    local mainC = newCompiler(nil)
    mainC:compileBlock(ast.body)
    mainC:emit(OPMAP[23])
    local mkey = nextKey()
    local menc = encryptCode(mainC.code, mkey)
    return addProto({ code = menc, K = mainC.K, upvals = mainC.upvals, boxed = mainC.boxed, np = 0, key = mkey, sum = checksum(menc) })
  end)
  if not ok then VM._payload = nil; return ast end
  local opmapParts = {}
  for logical = 1, 36 do table.insert(opmapParts, OPMAP[logical]) end
  VM._payload = { protoData = serializeProtos(), mainIndex = res, opmap = "{" .. table.concat(opmapParts, ",") .. "}" }
  ast.body = { { kind = "CallStatement", call = { kind = "Raw", text = "__vmmain()" } } }
  return ast
end

-- ===== Interpreter prelude =====

function VM.prelude()
  if not VM._payload then return "" end
  local L = {
    "local __OPMAP = " .. VM._payload.opmap,
    "local __DEC = {}",
    "for __l = 1, #__OPMAP do __DEC[__OPMAP[__l]] = __l end",
    "local __protos = " .. VM._payload.protoData,
    "local __exec, __mkclosure",
    "__exec = function(proto, upvals, args)",
    "  local code = proto.c",
    "  local K = proto.k",
    "  local boxed = proto.b",
    "  local __key = proto.key",
    "  local __sum = 5381",
    "  for __z = 1, #code do __sum = (__sum * 33 + code[__z]) % 2147483647 end",
    "  if __sum ~= proto.sum then error('integrity check failed') end",
    "  local function d(x) return code[x] ~ __key end",
    "  local R = {}",
    "  local cells = {}",
    "  for r in pairs(boxed) do cells[r] = { v = nil } end",
    "  local function gR(r) if boxed[r] then return cells[r].v else return R[r] end end",
    "  local function sR(r, val) if boxed[r] then cells[r].v = val else R[r] = val end end",
    "  local np = proto.np or 0",
    "  local __va = {}",
    "  for p = np + 1, #args do __va[p - np] = args[p] end",
    "  for p = 1, np do sR(p-1, args[p]) end",
    "  local i = 1",
    "  local n = #code",
    "  while i <= n do",
    "    local op = __DEC[d(i)]; i = i + 1",
    "    if op == 1 then sR(d(i), K[d(i+1)]); i = i + 2",
    "    elseif op == 2 then sR(d(i), gR(d(i+1))); i = i + 2",
    "    elseif op == 3 then sR(d(i), _ENV[K[d(i+1)]]); i = i + 2",
    "    elseif op == 4 then _ENV[K[d(i+1)]] = gR(d(i)); i = i + 2",
    "    elseif op == 5 then sR(d(i), gR(d(i+1)) + gR(d(i+2))); i = i + 3",
    "    elseif op == 6 then sR(d(i), gR(d(i+1)) - gR(d(i+2))); i = i + 3",
    "    elseif op == 7 then sR(d(i), gR(d(i+1)) * gR(d(i+2))); i = i + 3",
    "    elseif op == 8 then sR(d(i), gR(d(i+1)) / gR(d(i+2))); i = i + 3",
    "    elseif op == 9 then sR(d(i), gR(d(i+1)) % gR(d(i+2))); i = i + 3",
    "    elseif op == 10 then sR(d(i), gR(d(i+1)) ^ gR(d(i+2))); i = i + 3",
    "    elseif op == 11 then sR(d(i), gR(d(i+1)) .. gR(d(i+2))); i = i + 3",
    "    elseif op == 12 then sR(d(i), gR(d(i+1)) == gR(d(i+2))); i = i + 3",
    "    elseif op == 13 then sR(d(i), gR(d(i+1)) ~= gR(d(i+2))); i = i + 3",
    "    elseif op == 14 then sR(d(i), gR(d(i+1)) < gR(d(i+2))); i = i + 3",
    "    elseif op == 15 then sR(d(i), gR(d(i+1)) > gR(d(i+2))); i = i + 3",
    "    elseif op == 16 then sR(d(i), gR(d(i+1)) <= gR(d(i+2))); i = i + 3",
    "    elseif op == 17 then sR(d(i), gR(d(i+1)) >= gR(d(i+2))); i = i + 3",
    "    elseif op == 18 then sR(d(i), -gR(d(i+1))); i = i + 2",
    "    elseif op == 19 then sR(d(i), not gR(d(i+1))); i = i + 2",
    "    elseif op == 20 then sR(d(i), #gR(d(i+1))); i = i + 2",
    "    elseif op == 21 then",
    "      local base = d(i); local argc = d(i+1); local want = d(i+2); i = i + 3",
    "      local fn = gR(base)",
    "      local a = {}",
    "      for j = 1, argc do a[j] = gR(base + j) end",
    "      local rv = { fn(table.unpack(a, 1, argc)) }",
    "      if want < 0 then rv.__multi = true; sR(base, rv) else for w = 1, want do sR(base + w - 1, rv[w]) end end",
    "    elseif op == 22 then return gR(d(i))",
    "    elseif op == 23 then return",
    "    elseif op == 35 then",
    "      local base = d(i); local nn = d(i+1); i = i + 2",
    "      local rv = {}",
    "      local ri = 0",
    "      for j = 0, nn - 1 do",
    "        local val = gR(base + j)",
    "        if type(val) == 'table' and val.__multi then",
    "          for _, vv in ipairs(val) do ri = ri + 1; rv[ri] = vv end",
    "        else ri = ri + 1; rv[ri] = val end",
    "      end",
    "      return table.unpack(rv, 1, ri)",
    "    elseif op == 36 then",
    "      local dest = d(i); local nn = d(i+1); i = i + 2",
    "      for j = 0, nn - 1 do sR(dest + j, __va[j + 1]) end",
    "    elseif op == 24 then i = d(i)",
    "    elseif op == 25 then",
    "      local reg = d(i); local target = d(i+1); i = i + 2",
    "      if not gR(reg) then i = target end",
    "    elseif op == 26 then sR(d(i), __mkclosure(__protos[d(i+1)], cells, upvals)); i = i + 2",
    "    elseif op == 27 then sR(d(i), upvals[d(i+1)].v); i = i + 2",
    "    elseif op == 28 then upvals[d(i+1)].v = gR(d(i)); i = i + 2",
    "    elseif op == 29 then sR(d(i), {}); i = i + 1",
    "    elseif op == 30 then sR(d(i), gR(d(i+1))[gR(d(i+2))]); i = i + 3",
    "    elseif op == 31 then gR(d(i))[gR(d(i+1))] = gR(d(i+2)); i = i + 3",
    "    elseif op == 32 then local __t = gR(d(i+1)); sR(d(i), __t[K[d(i+2)]]); sR(d(i)+1, __t); i = i + 3",
    "    elseif op == 33 then",
    "      local base = d(i); local fReg = d(i+1); local stateReg = d(i+2); local ctrlReg = d(i+3); local ns = d(i+4); i = i + 5",
    "      local f = gR(fReg); local state = gR(stateReg); local ctrl = gR(ctrlReg)",
    "      local rv = { f(state, ctrl) }",
    "      for w = 1, ns do sR(base + w - 1, rv[w]) end",
    "    elseif op == 34 then",
    "      local reg = d(i); local target = d(i+1); i = i + 2",
    "      if gR(reg) then i = target end",
    "    end",
    "  end",
    "end",
    "__mkclosure = function(proto, parentCells, parentUpvals)",
    "  local captured = {}",
    "  for idx = 1, #proto.u do",
    "    local spec = proto.u[idx]",
    "    if spec.l ~= nil then captured[idx] = parentCells[spec.l]",
    "    else captured[idx] = parentUpvals[spec.u] end",
    "  end",
    "  return function(...) return __exec(proto, captured, {...}) end",
    "end",
    "local function __vmmain() return __exec(__protos[" .. VM._payload.mainIndex .. "], {}, {}) end",
  }
  return table.concat(L, "\n") .. "\n"
end

return VM
