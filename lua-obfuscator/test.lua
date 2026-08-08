-- test.lua
local Lexer = require("lexer")
local Parser = require("parser")

-- Maliit na helper para makita ang tree (naka-indent)
local function printAST(node, indent)
  indent = indent or ""
  if node.kind == "Number" then
    print(indent .. "Number: " .. node.value)
  elseif node.kind == "Variable" then
    print(indent .. "Variable: " .. node.name)
  elseif node.kind == "BinaryOp" then
    print(indent .. "BinaryOp: " .. node.op)
    printAST(node.left,  indent .. "  ")
    printAST(node.right, indent .. "  ")
  end
end

-- Subukan ang expression
local code = "1 + 2 * 3"
local tokens = Lexer.tokenize(code)
local ast = Parser.parse(tokens)

print("Expression: " .. code)
print("---")
printAST(ast)
