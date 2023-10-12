math.randomseed(tonumber(tostring(os.time()):reverse():sub(1, 9)) or 0)

-- https://gist.github.com/jrus/3197011
local id = function()
  local template = "xxxxxxxx"
  return (
    string.gsub(template, "[x]", function(c)
      local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format("%x", v)
    end)
  )
end

return {
  id = id,
}
