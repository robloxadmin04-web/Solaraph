--!strict
-- Simuweylang "real" Luau module: OOP class, event bus, inventory system.

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
	local self = setmetatable({}, EventBus)
	self._listeners = {}
	return self
end

function EventBus:on(name: string, fn)
	if not self._listeners[name] then
		self._listeners[name] = {}
	end
	table.insert(self._listeners[name], fn)
	return #self._listeners[name]
end

function EventBus:fire(name: string, ...)
	local list = self._listeners[name]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(...)
	end
end

--------------------------------------------------------------------
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(owner: string, capacity: number)
	return setmetatable({
		owner = owner,
		capacity = capacity,
		items = {},
		bus = EventBus.new(),
	}, Inventory)
end

function Inventory:totalCount(): number
	local total = 0
	for _, qty in pairs(self.items) do
		total += qty
	end
	return total
end

function Inventory:add(item: string, qty: number): boolean
	local current = self.items[item] or 0
	if self:totalCount() + qty > self.capacity then
		self.bus:fire("full", self.owner, item)
		return false
	end
	self.items[item] = current + qty
	self.bus:fire("added", item, qty)
	return true
end

function Inventory:remove(item: string, qty: number): boolean
	local current = self.items[item] or 0
	if current < qty then
		return false
	end
	if current == qty then
		self.items[item] = nil
	else
		self.items[item] -= qty
	end
	return true
end

function Inventory:describe(): string
	local parts = {}
	for item, qty in pairs(self.items) do
		table.insert(parts, `{item} x{qty}`)
	end
	table.sort(parts)
	local label = if #parts == 0 then "empty" else table.concat(parts, ", ")
	return `Inventory[{self.owner}] ({self:totalCount()}/{self.capacity}): {label}`
end

--------------------------------------------------------------------
-- recursive closures + upvalues (fibonacci memoized)
local function makeMemoFib()
	local cache = {}
	local fib
	fib = function(n: number): number
		if n <= 1 then return n end
		if cache[n] then return cache[n] end
		local result = fib(n - 1) + fib(n - 2)
		cache[n] = result
		return result
	end
	return fib
end

--------------------------------------------------------------------
-- generic for + varargs + multiple returns
local function sumAndCount(...: number): (number, number)
	local total, n = 0, 0
	for _, v in ipairs({...}) do
		total += v
		n += 1
	end
	return total, n
end

local function classify(n: number): string
	local bucket = if n % 15 == 0 then "fizzbuzz"
		elseif n % 3 == 0 then "fizz"
		elseif n % 5 == 0 then "buzz"
		else tostring(n)
	return bucket
end

--------------------------------------------------------------------
local fib = makeMemoFib()
local inv = Inventory.new("Player1", 10)

inv.bus:on("added", function(item, qty)
	print(`[log] added {qty}x {item}`)
end)
inv.bus:on("full", function(owner, item)
	print(`[warn] {owner} inventory full, could not add {item}`)
end)

inv:add("sword", 1)
inv:add("potion", 3)
local ok = inv:add("gem", 20)
print("gem add ok? " .. tostring(ok))
print(inv:describe())

local total, count = sumAndCount(1, 2, 3, 4, 5)
print(`sum={total} count={count} avg={total // count}`)

for i = 1, 10 do
	local msg = classify(i)
	local continueEarly = (i % 2 == 0)
	if continueEarly then
		continue
	end
	print(`{i}: {msg}, fib({i})={fib(i)}`)
end

local Weekday = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local weekendCount = 0
for idx, day in Weekday do
	if day == "Sat" or day == "Sun" then
		weekendCount += 1
	end
end
print(`weekend days: {weekendCount}`)
