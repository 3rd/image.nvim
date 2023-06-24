local utils = require("image/utils")
local codes = require("image/backends/kitty/codes")

local stdout = vim.loop.new_tty(1, false)

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L77
local get_chunked = function(str)
  local chunks = {}
  for i = 1, #str, 4096 do
    local chunk = str:sub(i, i + 4096 - 1):gsub("%s", "")
    if #chunk > 0 then table.insert(chunks, chunk) end
  end
  return chunks
end

local write = vim.schedule_wrap(function(data)
  stdout:write(data)
end)

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/state.lua#L15
local get_term_size = function()
  local ffi = require("ffi")
  ffi.cdef([[
        typedef struct {
            unsigned short row;
            unsigned short col;
            unsigned short xpixel;
            unsigned short ypixel;
        } winsize;
        int ioctl(int, int, ...);
    ]])

  local TIOCGWINSZ = nil
  if vim.fn.has("linux") == 1 then
    TIOCGWINSZ = 0x5413
  elseif vim.fn.has("mac") == 1 then
    TIOCGWINSZ = 0x40087468
  elseif vim.fn.has("bsd") == 1 then
    TIOCGWINSZ = 0x40087468
  end

  local sz = ffi.new("winsize")
  assert(ffi.C.ioctl(1, TIOCGWINSZ, sz) == 0, "Hologram failed to get screen size: detected OS is not supported.")

  return {
    screen_x = sz.xpixel,
    screen_y = sz.ypixel,
    screen_cols = sz.col,
    screen_rows = sz.row,
    cell_width = sz.xpixel / sz.col,
    cell_height = sz.ypixel / sz.row,
  }
end

---@param config KittyControlConfig
---@param data? string
-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L52
local write_graphics = function(config, data)
  local control_payload = ""
  -- log(config)
  for k, v in pairs(config) do
    if v ~= nil then
      local key = codes.control.keys[k]
      control_payload = control_payload .. key .. "=" .. v .. ","
    end
  end
  control_payload = control_payload:sub(0, -2)
  log(control_payload)

  if data then
    if config.transmit_medium ~= codes.control.transmit_medium.direct then data = utils.base64.encode(data) end
    local chunks = get_chunked(data)
    for i = 1, #chunks do
      write("\x1b_G" .. control_payload .. ";" .. chunks[i] .. "\x1b\\")
      if i == #chunks - 1 then
        control_payload = "m=0"
      else
        control_payload = "m=1"
      end
    end
  else
    write("\x1b_G" .. control_payload .. "\x1b\\")
  end
end

local move_cursor = function(x, y)
  write("\x1b[s")
  write("\x1b[" .. y .. ":" .. x .. "H")
end

local restore_cursor = function()
  write("\x1b[u")
end

return {
  get_term_size = get_term_size,
  move_cursor = move_cursor,
  restore_cursor = restore_cursor,
  write = write,
  write_graphics = write_graphics,
}
