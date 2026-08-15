local t = {1, 2, 3}
local label = `Items: {#t} first={t[1]} nested={ if #t > 0 then "yes" else "no" }`
print(label)

local Account = {}
Account.__index = Account
function Account.new(balance: number)
	local self = setmetatable({}, Account)
	self.balance = balance
	return self
end
function Account:deposit(amount: number)
	self.balance += amount
end
local acc = Account.new(100)
acc:deposit(50)
print(`Balance: {acc.balance}`)

local function classify(n: number)
	return if n % 2 == 0 then "even" else "odd"
end
for i = 1, 5 do
	print(`{i} is {classify(i)}`)
end
