local function __dec(t)
  local s = {}
  for i = 1, #t do s[i] = string.char(t[i] ~ 90) end
  return table.concat(s)
end
local _v1 = {} _v1.__index = _v1 function _v1.new(_v2, _v3) local _v4 = setmetatable({}, _v1) _v4.name = _v2 _v4.balance = _v3 return _v4 end function _v1:deposit(_v5) self.balance = self.balance + _v5 print(self.name .. __dec({122,52,59,61,62,63,42,53,41,51,46,53,122,52,61,122}) .. _v5) end local _v6 = _v1.new(__dec({9,53,54,59,40,59,42,50}), (61 + 39)) _v6:deposit((28 + 22)) print(__dec({24,59,54,59,52,57,63,96,122}) .. _v6.balance) 