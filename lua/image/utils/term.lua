-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/state.lua#L15
local get_size = function()
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

  return {
    screen_x = sz.xpixel,
    screen_y = sz.ypixel,
    screen_cols = sz.col,
    screen_rows = sz.row,
    cell_width = sz.xpixel / sz.col,
    cell_height = sz.ypixel / sz.row,
  }
end

return {
  get_size = get_size,
}
