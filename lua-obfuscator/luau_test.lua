--!strict
local function greet(name: string, score: number): string
	local grade = if score >= 90 then "A" elseif score >= 75 then "B" else "C"
	local msg = `Hello {name}, your score is {score} and grade is {grade}!`
	return msg
end

local function compute(a: number, b: number)
	local q = a // b
	q //= 2
	return q
end

@native
local function fastAdd(x: number, y: number): number
	return x + y
end

local total = 0
for i, v in ipairs({10, 20, 30}) do
	if v == 20 then
		continue
	end
	total += v
end

print(greet("Solaraph", 88))
print(compute(17, 3))
print(fastAdd(2, 3))
print(total)
