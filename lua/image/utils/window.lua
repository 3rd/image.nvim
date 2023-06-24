---@return Window|nil
local get_window = function(id)
  if not vim.api.nvim_win_is_valid(id) then return nil end
  local buffer = vim.api.nvim_win_get_buf(id)
  local width = vim.api.nvim_win_get_width(id)
  local height = vim.api.nvim_win_get_height(id)
  local pos = vim.api.nvim_win_get_position(id)

  local scroll_x = 0 -- TODO
  local scroll_y = tonumber(vim.fn.win_execute(id, "echo line('w0')"))

  return {
    id = id,
    buf = buffer,
    x = pos[2],
    y = pos[1],
    width = width,
    height = height,
    scroll_x = scroll_x,
    scroll_y = scroll_y,
  }
end

---@return Window[]
local get_visible_windows = function()
  local windows = {}
  for _, handle in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local window = get_window(handle)
    if window then table.insert(windows, window) end
  end
  return windows
end

---@param win Window|number
---@return boolean
local is_window_visible = function(win)
  if type(win) == "number" and not vim.api.nvim_win_is_valid(win) then
    return false
  else
    if not vim.api.nvim_win_is_valid(win.id) then return false end
  end

  local target = type(win) == "number" and get_window(win) or win

  local visible_windows = get_visible_windows()
  for _, window in ipairs(visible_windows) do
    if window.id == target.id then return true end
  end
  return false
end

return {
  get_window = get_window,
  get_visible_windows = get_visible_windows,
  is_window_visible = is_window_visible,
}
