-- demo.lua — pansubok na script
local function factorial(n)
  if n <= 1 then
    return 1
  end
  return n * factorial(n - 1)
end

local function greet(name)
  print("Kumusta, " .. name)
end

greet("Solaraph")
for i = 1, 5 do
  print(i .. "! = " .. factorial(i))
end
