-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")

local function printAST(node, indent)
  indent = indent or ""

  if node.kind == "Program" then
    print(indent .. "Program:")
    for _, stmt in ipairs(node.body) do
      printAST(stmt, indent .. "  ")
    end

  elseif node.kind == "LocalAssignment" then
    print(indent .. "LocalAssignment: " .. node.name)
    printAST(node.value, indent .. "  ")

  elseif node.kind == "Assignment" then
    print(indent .. "Assignment: " .. node.name)
    printAST(node.value, indent .. "  ")

  elseif node.kind == "Number" then
    print(indent .. "Number: " .. node.value)
  elseif node.kind == "String" then
    print(indent .. "String: " .. node.value)
  elseif node.kind == "Literal" then
    print(indent .. "Literal: " .. node.value)
  elseif node.kind == "Variable" then
    print(indent .. "Variable: " .. node.name)
  elseif node.kind == "UnaryOp" then
    print(indent .. "UnaryOp: " .. node.op)
    printAST(node.operand, indent .. "  ")
  elseif node.kind == "BinaryOp" then
    print(indent .. "BinaryOp: " .. node.op)
    printAST(node.left,  indent .. "  ")
    printAST(node.right, indent .. "  ")
  end
end

local code = [[
local x = 1 + 2 * 3
local name = "Solaraph"
x = x + 1
]]

local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)
printAST(ast)
