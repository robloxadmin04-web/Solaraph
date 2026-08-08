-- demo2.lua — may tables at methods
local Account = {}
Account.__index = Account

function Account.new(name, balance)
  local self = setmetatable({}, Account)
  self.name = name
  self.balance = balance
  return self
end

function Account:deposit(amount)
  self.balance = self.balance + amount
  print(self.name .. " nagdeposito ng " .. amount)
end

local acc = Account.new("Solaraph", 100)
acc:deposit(50)
print("Balance: " .. acc.balance)