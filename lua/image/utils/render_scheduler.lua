local pending = {}

---@param key string
---@param callback fun()
local schedule = function(key, callback)
  local task = pending[key]
  if task then
    task.callback = callback
    return
  end

  pending[key] = { callback = callback }
  vim.schedule(function()
    local current = pending[key]
    if not current then return end

    pending[key] = nil
    current.callback()
  end)
end

local clear = function()
  pending = {}
end

return {
  clear = clear,
  schedule = schedule,
}
