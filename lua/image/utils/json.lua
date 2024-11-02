---@param data table
---@param indent? number
local json_encode = function(data, indent)
  if indent == nil then return vim.fn.json_encode(data) end

  local function pretty(target, level)
    local indentation = string.rep("  ", level)
    local prev_indentation = string.rep("  ", level - 1)
    if type(target) == "table" then
      local result = ""
      if next(target) ~= nil then
        result = result .. "{\n"
        for k, v in pairs(target) do
          result = result .. indentation .. pretty(k, level + 1) .. ": " .. pretty(v, level + 1) .. ",\n"
        end
        result = result .. prev_indentation .. "}"
        return result
      else
        return "{}"
      end
    elseif type(target) == "string" then
      return string.format("%q", target)
    elseif type(target) == "number" then
      return tostring(target)
    elseif type(target) == "boolean" then
      return tostring(target)
    elseif type(target) == "nil" then
      return "null"
    else
      error("invalid type: " .. type(target))
    end
  end

  return pretty(data, indent)
end

return {
  encode = json_encode,
}
