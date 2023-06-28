---@return Window|nil
local get_window = function(id)
  if not vim.api.nvim_win_is_valid(id) then return nil end

  local buffer = vim.api.nvim_win_get_buf(id)
  local columns = vim.api.nvim_win_get_width(id)
  local rows = vim.api.nvim_win_get_height(id)
  local pos = vim.api.nvim_win_get_position(id)

  local scroll_x = 0 -- TODO
  local scroll_y = tonumber(vim.fn.win_execute(id, "echo line('w0')"))

  local is_visible = false
  for _, handle in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if handle == id then
      is_visible = true
      break
    end
  end

  return {
    id = id,
    buffer = buffer,
    x = pos[2],
    y = pos[1],
    scroll_x = scroll_x,
    scroll_y = scroll_y,
    width = columns,
    height = rows,
    is_visible = is_visible,
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

return {
  get_window = get_window,
  get_visible_windows = get_visible_windows,
}
