local is_tmux = vim.env.TMUX ~= nil
local pane_id = vim.env.TMUX_PANE
local pane_position = nil
local pane_position_clear_scheduled = false

local has_passthrough = false
if is_tmux then
  local ok, result = pcall(vim.fn.system, { "tmux", "show", "-Apv", "allow-passthrough" })
  if ok and (result:sub(-3) == "on\n" or result:sub(-4) == "all\n") then has_passthrough = true end
end

local create_dm_getter = function(name)
  return function()
    if not is_tmux then return nil end
    local result = vim.fn.system({ "tmux", "display-message", "-p", "#{" .. name .. "}" })
    return vim.fn.trim(result)
  end
end

local clear_pane_position = function()
  pane_position = nil
  pane_position_clear_scheduled = false
end

local get_pane_position = function()
  if not is_tmux then return { left = 0, top = 0 } end
  if pane_position then return pane_position end

  local command = { "tmux", "display-message", "-p", "#{pane_left} #{pane_top}" }
  if pane_id then command = { "tmux", "display-message", "-p", "-t", pane_id, "#{pane_left} #{pane_top}" } end

  local result = vim.fn.system(command)
  local left, top = result:match("(%-?%d+)%s+(%-?%d+)")
  pane_position = {
    left = tonumber(left) or 0,
    top = tonumber(top) or 0,
  }

  if not pane_position_clear_scheduled then
    pane_position_clear_scheduled = true
    vim.schedule(clear_pane_position)
  end

  return pane_position
end

local get_current_session = create_dm_getter("client_session")

local create_dm_window_getter = function(name)
  return function()
    if not is_tmux then return nil end
    local result = vim.fn.system({
      "tmux",
      "list-windows",
      "-t",
      get_current_session(),
      "-F",
      "#{" .. name .. "}",
      "-f",
      "#{window_active}",
    })
    return vim.fn.trim(result)
  end
end

local create_dm_pane_getter = function(name)
  return function()
    if not is_tmux then return nil end
    local result = vim.fn.system({
      "tmux",
      "list-panes",
      "-t",
      get_current_session(),
      "-F",
      "#{" .. name .. "}",
      "-f",
      "#{pane_active}",
    })
    return vim.fn.trim(result)
  end
end

local escape = function(sequence)
  return "\x1bPtmux;" .. sequence:gsub("\x1b", "\x1b\x1b") .. "\x1b\\"
end

local get_version = function()
  local result = vim.fn.system({ "tmux", "-V" })
  return result:match("tmux (%d+%.%d+)")
end

return {
  is_tmux = is_tmux,
  has_passthrough = has_passthrough,
  get_pid = create_dm_getter("pid"),
  get_socket_path = create_dm_getter("socket_path"),
  get_current_session = get_current_session,
  get_window_id = create_dm_window_getter("window_id"),
  get_window_name = create_dm_window_getter("window_name"),
  get_pane_id = create_dm_pane_getter("pane_id"),
  get_pane_pid = create_dm_pane_getter("pane_pid"),
  get_pane_left = create_dm_getter("pane_left"),
  get_pane_position = get_pane_position,
  get_pane_top = create_dm_getter("pane_top"),
  get_pane_tty = create_dm_pane_getter("pane_tty"),
  get_cursor_x = create_dm_getter("cursor_x"),
  get_cursor_y = create_dm_getter("cursor_y"),
  get_version = get_version,
  escape = escape,
}
