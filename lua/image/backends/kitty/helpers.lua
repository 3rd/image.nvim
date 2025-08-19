local codes = require("image/backends/kitty/codes")
local utils = require("image/utils")
local log = require("image/utils/logger").within("backend.kitty")

local uv = vim.uv
-- Allow for loop to be used on older versions
if not uv then uv = vim.loop end

local stdout = vim.loop.new_tty(1, false)
if not stdout then error("failed to open stdout") end

local is_SSH = (vim.env.SSH_CLIENT ~= nil) or (vim.env.SSH_TTY ~= nil)

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L77
local get_chunked = function(str)
  local chunks = {}
  for i = 1, #str, 4096 do
    local chunk = str:sub(i, i + 4096 - 1):gsub("%s", "")
    if #chunk > 0 then table.insert(chunks, chunk) end
  end
  return chunks
end

---@param data string
---@param tty? string
---@param escape? boolean
local write = function(data, tty, escape)
  if data == "" then return end

  local payload = data
  if escape and utils.tmux.is_tmux then payload = utils.tmux.escape(data) end
  log.debug("write", { payload_len = #payload, tty = tty })
  if tty then
    local handle = io.open(tty, "w")
    if not handle then error("failed to open tty") end
    handle:write(payload)
    handle:close()
  else
    -- vim.fn.chansend(vim.v.stderr, payload)
    stdout:write(payload)
  end
end

local move_cursor = function(x, y, save)
  if is_SSH and utils.tmux.is_tmux then
    -- When tmux is running over ssh, set-cursor sometimes doesn't actually get sent
    -- I don't know why this fixes the issue...
    utils.tmux.get_cursor_x()
    utils.tmux.get_cursor_y()
  end
  if save then write("\x1b[s") end
  write("\x1b[" .. y .. ";" .. x .. "H")
  uv.sleep(1)
end

local restore_cursor = function()
  write("\x1b[u")
end

local update_sync_start = function()
  write("\x1b[?2026h")
end

local update_sync_end = function()
  write("\x1b[?2026l")
end

---@param config KittyControlConfig
---@param data? string
-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L52
local write_graphics = function(config, data)
  local control_payload = ""

  log.debug("write_graphics", { config = config, has_data = data ~= nil })

  for k, v in pairs(config) do
    if v ~= nil then
      local key = codes.control.keys[k]
      if key then
        if type(v) == "number" then
          -- There are currently no floating-point values in the Kitty graphics
          -- specification. All values are either signed or unsigned 32-bit integers.
          -- As such, we just stringify the number values here using "%d" to drop any
          -- possible fractional portions.
          --
          -- (Note that string.format here is used to accommodate older versions of
          -- Lua, in addition to the fact that we are just writing the string below
          -- anyway).
          v = string.format("%d", v)
        end
        control_payload = control_payload .. key .. "=" .. v .. ","
      end
    end
  end
  control_payload = control_payload:sub(0, -2)

  if data then
    if config.transmit_medium == codes.control.transmit_medium.direct then
      local file = io.open(data, "rb")
      data = file:read("*all")
    end
    data = vim.base64.encode(data):gsub("%-", "/")
    local chunks = get_chunked(data)
    local m = #chunks > 1 and 1 or 0
    control_payload = control_payload .. ",m=" .. m
    for i = 1, #chunks do
      write("\x1b_G" .. control_payload .. ";" .. chunks[i] .. "\x1b\\", config.tty, true)
      if i == #chunks - 1 then
        control_payload = "m=0"
      else
        control_payload = "m=1"
      end
      uv.sleep(1)
    end
  else
    log.debug("control payload", { payload = control_payload })
    write("\x1b_G" .. control_payload .. "\x1b\\", config.tty, true)
  end
end

local write_placeholder = function(image_id, x, y, width, height)
  local foreground = "\x1b[38;5;" .. image_id .. "m"
  local restore = "\x1b[39m"

  write(foreground)
  for i = 0, height - 1 do
    move_cursor(x, y + i + 1)
    for j = 0, width - 1 do
      write(codes.placeholder .. codes.diacritics[i + 1] .. codes.diacritics[j + 1])
    end
  end
  write(restore)
end

return {
  move_cursor = move_cursor,
  restore_cursor = restore_cursor,
  write = write,
  write_graphics = write_graphics,
  write_placeholder = write_placeholder,
  update_sync_start = update_sync_start,
  update_sync_end = update_sync_end,
}
