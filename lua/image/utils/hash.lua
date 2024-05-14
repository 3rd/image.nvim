local bit = require("bit")

local simple = function(str)
  local hash = 5381
  for i = 1, #str do
    local char = string.byte(str, i)
    hash = bit.lshift(hash, 5) + hash + char
  end
  return hash
end

local sha256 = function(str)
  return vim.fn.sha256(str)
end

return {
  simple = simple,
  sha256 = sha256,
}
