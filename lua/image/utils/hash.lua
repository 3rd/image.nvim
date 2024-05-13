local bit = require("bit")

local filename = function(str)
  local hash = 5381
  for i = 1, #str do
    local char = string.byte(str, i)
    hash = bit.lshift(hash, 5) + hash + char
  end
  return hash
end

return {
  simple = filename,
}
