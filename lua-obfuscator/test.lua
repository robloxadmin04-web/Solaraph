-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")

-- Helper: i-print ang AST nang naka-indent
local function printAST(node, indent)
  indent = indent or ""
  if node.kind == "Number" then
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

local code = "a == 1 and b or not c"
local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)

print("Expression: " .. code)
print("---")
printAST(ast)
