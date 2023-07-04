local utils = require("image/utils")
local codes = require("image/backends/kitty/codes")

local stdout = vim.loop.new_tty(1, false)
local is_tmux = vim.env.TMUX ~= nil

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L77
local get_chunked = function(str)
  local chunks = {}
  for i = 1, #str, 4096 do
    local chunk = str:sub(i, i + 4096 - 1):gsub("%s", "")
    if #chunk > 0 then table.insert(chunks, chunk) end
  end
  return chunks
end

local encode = function(data)
  if is_tmux then return "\x1bPtmux;" .. data:gsub("\x1b", "\x1b\x1b") .. "\x1b\\" end
  return data
end

local write = function(data)
  if data == "" then return end
  -- utils.debug("write:", vim.inspect(data))
  stdout:write(data)
  -- vim.fn.chansend(vim.v.stderr, data)
end

local move_cursor = function(x, y, save, tmux_delay)
  if save then write("\x1b[s") end
  write("\x1b[" .. y .. ";" .. x .. "H")
  if is_tmux and tmux_delay then vim.loop.sleep(tmux_delay) end
end

local restore_cursor = function()
  write("\x1b[u")
end

---@param config KittyControlConfig
---@param data? string
-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L52
local write_graphics = function(config, data)
  local control_payload = ""

  -- utils.debug("kitty.write_graphics()", config, data)

  for k, v in pairs(config) do
    if v ~= nil then
      local key = codes.control.keys[k]
      control_payload = control_payload .. key .. "=" .. v .. ","
    end
  end
  control_payload = control_payload:sub(0, -2)

  if data then
    if config.transmit_medium ~= codes.control.transmit_medium.direct then data = utils.base64.encode(data) end
    local chunks = get_chunked(data)
    for i = 1, #chunks do
      write(encode("\x1b_G" .. control_payload .. ";" .. chunks[i] .. "\x1b\\"))
      if i == #chunks - 1 then
        control_payload = "m=0"
      else
        control_payload = "m=1"
      end
    end
  else
    -- utils.debug("kitty control payload:", control_payload)
    write(encode("\x1b_G" .. control_payload .. "\x1b\\"))
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
}
