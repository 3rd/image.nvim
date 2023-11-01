local is_tmux = vim.env.TMUX ~= nil

local has_passthrough = false
if is_tmux then
  local ok, result = pcall(vim.fn.system, "tmux show -Apv allow-passthrough")
  if ok and result:sub(-3) == "on\n" then has_passthrough = true end
end

local create_dm_getter = function(name)
  return function()
    if not is_tmux then return nil end
    local result = vim.fn.system("tmux display-message -p '#{" .. name .. "}'")
    return vim.fn.trim(result)
  end
end

local escape = function(sequence)
  return "\x1bPtmux;" .. sequence:gsub("\x1b", "\x1b\x1b") .. "\x1b\\"
end

return {
  is_tmux = is_tmux,
  has_passthrough = has_passthrough,
  get_pid = create_dm_getter("pid"),
  get_socket_path = create_dm_getter("socket_path"),
  get_window_id = create_dm_getter("window_id"),
  get_window_name = create_dm_getter("window_name"),
  get_pane_id = create_dm_getter("pane_id"),
  get_pane_pid = create_dm_getter("pane_pid"),
  get_pane_tty = create_dm_getter("pane_tty"),
  get_cursor_x = create_dm_getter("cursor_x"),
  get_cursor_y = create_dm_getter("cursor_y"),
  escape = escape,
}
