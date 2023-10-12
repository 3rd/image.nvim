local cached_size = {
  screen_x = 0,
  screen_y = 0,
  screen_cols = 0,
  screen_rows = 0,
  cell_width = 0,
  cell_height = 0,
}

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/state.lua#L15
local update_size = function()
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

  ---@type { row: number, col: number, xpixel: number, ypixel: number }
  local sz = ffi.new("winsize")
  assert(ffi.C.ioctl(1, TIOCGWINSZ, sz) == 0, "Failed to get terminal size")

  cached_size = {
    screen_x = sz.xpixel,
    screen_y = sz.ypixel,
    screen_cols = sz.col,
    screen_rows = sz.row,
    cell_width = sz.xpixel / sz.col,
    cell_height = sz.ypixel / sz.row,
  }
end

update_size()
vim.api.nvim_create_autocmd("VimResized", {
  callback = update_size,
})

local get_tty = function()
  local handle = io.popen("tty 2>/dev/null")
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  result = vim.fn.trim(result)
  if result == "" then return nil end
  return result
end

return {
  get_size = function()
    return cached_size
  end,
  get_tty = get_tty,
}
