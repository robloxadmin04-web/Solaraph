-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")

local function printAST(node, indent)
  indent = indent or ""
  local k = node.kind

  if k == "Program" then
    print(indent .. "Program:")
    for _, s in ipairs(node.body) do printAST(s, indent .. "  ") end

  elseif k == "LocalAssignment" then
    print(indent .. "LocalAssignment: " .. node.name)
    if node.value then printAST(node.value, indent .. "  ") end

  elseif k == "Assignment" then
    print(indent .. "Assignment:")
    printAST(node.target, indent .. "  target: " == indent .. "  " and indent .. "  " or indent .. "  ")
    printAST(node.value, indent .. "  ")

  elseif k == "LocalFunction" or k == "FunctionDeclaration" then
    print(indent .. k .. ": " .. node.name)
    printAST(node.func, indent .. "  ")

  elseif k == "Function" then
    print(indent .. "Function(" .. table.concat(node.params, ", ") .. "):")
    for _, s in ipairs(node.body) do printAST(s, indent .. "  ") end

  elseif k == "If" then
    print(indent .. "If:")
    for i, cl in ipairs(node.clauses) do
      print(indent .. "  clause " .. i .. " cond:")
      printAST(cl.cond, indent .. "    ")
      print(indent .. "  clause " .. i .. " body:")
      for _, s in ipairs(cl.body) do printAST(s, indent .. "    ") end
    end
    if node.elseBody then
      print(indent .. "  else:")
      for _, s in ipairs(node.elseBody) do printAST(s, indent .. "    ") end
    end

  elseif k == "While" then
    print(indent .. "While cond:")
    printAST(node.cond, indent .. "  ")
    print(indent .. "  body:")
    for _, s in ipairs(node.body) do printAST(s, indent .. "    ") end

  elseif k == "NumericFor" then
    print(indent .. "NumericFor: " .. node.var)
    printAST(node.startExpr, indent .. "  start: " and indent .. "  ")
    for _, s in ipairs(node.body) do printAST(s, indent .. "  ") end

  elseif k == "GenericFor" then
    print(indent .. "GenericFor: " .. table.concat(node.names, ", "))
    for _, s in ipairs(node.body) do printAST(s, indent .. "  ") end

  elseif k == "Return" then
    print(indent .. "Return:")
    for _, v in ipairs(node.values) do printAST(v, indent .. "  ") end

  elseif k == "Break" then
    print(indent .. "Break")

  elseif k == "CallStatement" then
    print(indent .. "CallStatement:")
    printAST(node.call, indent .. "  ")

  elseif k == "Call" then
    print(indent .. "Call:")
    print(indent .. "  callee:")
    printAST(node.callee, indent .. "    ")
    print(indent .. "  args:")
    for _, a in ipairs(node.args) do printAST(a, indent .. "    ") end

  elseif k == "Index" then
    if node.field then
      print(indent .. "Index .field: " .. node.field)
      printAST(node.object, indent .. "  ")
    else
      print(indent .. "Index [expr]:")
      printAST(node.object, indent .. "  ")
      printAST(node.index, indent .. "  ")
    end

  elseif k == "Number"   then print(indent .. "Number: " .. node.value)
  elseif k == "String"   then print(indent .. "String: " .. node.value)
  elseif k == "Literal"  then print(indent .. "Literal: " .. node.value)
  elseif k == "Variable" then print(indent .. "Variable: " .. node.name)
  elseif k == "UnaryOp" then
    print(indent .. "UnaryOp: " .. node.op)
    printAST(node.operand, indent .. "  ")
  elseif k == "BinaryOp" then
    print(indent .. "BinaryOp: " .. node.op)
    printAST(node.left,  indent .. "  ")
    printAST(node.right, indent .. "  ")
  else
    print(indent .. "??? " .. tostring(k))
  end
end

local code = [[
local function add(a, b)
  return a + b
end

local total = 0
for i = 1, 10 do
  total = total + i
end

if total > 5 then
  print("malaki: " .. total)
else
  print("maliit")
end
]]

local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)
printAST(ast)
