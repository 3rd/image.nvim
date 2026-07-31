---@type { screen_x: number, screen_y: number, screen_cols: number, screen_rows: number, cell_width: number, cell_height: number }|nil
local cached_size = nil
local size_warned = false

-- Used when the pty reports no pixel geometry and nothing better is configured.
-- Historical value; mainly keeps cell_width/cell_height non-zero so the crop
-- math downstream can't divide by zero.
local FALLBACK_CELL_WIDTH = 8
local FALLBACK_CELL_HEIGHT = 16

---@type { width: number, height: number }|nil
local configured_cell_size = nil

---@param value string
---@param source string
---@return { width: number, height: number }|nil
local parse_cell_size = function(value, source)
  local w, h = value:match("^(%d+)[xX](%d+)$")
  if w and tonumber(w) > 0 and tonumber(h) > 0 then
    return { width = tonumber(w), height = tonumber(h) }
  end
  vim.notify(
    ("image.nvim: ignoring malformed %s=%s (expected e.g. 14x32)"):format(source, value),
    vim.log.levels.WARN
  )
  return nil
end

--- Accepts "WxH" or { width = W, height = H }.
---@param value string|{ width: number, height: number }
---@param source string
---@return { width: number, height: number }|nil
local normalize_cell_size = function(value, source)
  if type(value) == "string" then return parse_cell_size(value, source) end
  if type(value) == "table" then
    local w, h = tonumber(value.width), tonumber(value.height)
    if w and h and w > 0 and h > 0 then return { width = w, height = h } end
  end
  vim.notify(
    ('image.nvim: ignoring invalid %s (expected "14x32" or { width = 14, height = 32 })'):format(source),
    vim.log.levels.WARN
  )
  return nil
end

--- Resolve the cell size to assume when the pty reports no pixel geometry.
--- The option wins; IMAGE_NVIM_CELL_SIZE is the fallback, for when the value has
--- to come from outside Neovim (see set_cell_size).
---@param option string|{ width: number, height: number }|nil
---@return { width: number, height: number }|nil
local resolve_cell_size = function(option)
  if option ~= nil then return normalize_cell_size(option, "cell_size") end
  local env = vim.env.IMAGE_NVIM_CELL_SIZE
  if env then return parse_cell_size(env, "IMAGE_NVIM_CELL_SIZE") end
  return nil
end

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

  if not TIOCGWINSZ then
    if not size_warned then
      size_warned = true
      vim.notify("image.nvim: unsupported OS — cannot query terminal size", vim.log.levels.WARN)
    end
    return
  end

  ---@type { row: number, col: number, xpixel: number, ypixel: number }
  local sz = ffi.new("winsize")
  if ffi.C.ioctl(1, TIOCGWINSZ, sz) ~= 0 then
    if not size_warned then
      size_warned = true
      vim.notify("image.nvim: cannot query terminal size (non-terminal environment?)", vim.log.levels.WARN)
    end
    return
  end

  local xpixel = sz.xpixel
  local ypixel = sz.ypixel

  -- Some ptys report cells but no pixels: WSL2 always, and often SSH. Cell size
  -- scales every crop rectangle, so guessing wrong samples the wrong region of
  -- the source image -- prefer a configured size over the fallback.
  if xpixel == 0 or ypixel == 0 then
    local cw = configured_cell_size and configured_cell_size.width or FALLBACK_CELL_WIDTH
    local ch = configured_cell_size and configured_cell_size.height or FALLBACK_CELL_HEIGHT
    xpixel = sz.col * cw
    ypixel = sz.row * ch
  end

  cached_size = {
    screen_x = xpixel,
    screen_y = ypixel,
    screen_cols = sz.col,
    screen_rows = sz.row,
    cell_width = xpixel / sz.col,
    cell_height = ypixel / sz.row,
  }
end

--- Set the assumed cell size and recompute. Called from setup().
---
--- This module is required before setup() runs, so the size computed at load time
--- uses the fallback; this recomputes it once the option is known.
---
--- Neovim cannot ask the terminal itself -- TermResponse never fires for the
--- CSI 16 t reply, and a child process gets no /dev/tty -- so on a pty without
--- pixel geometry the value has to be supplied. Either pass `cell_size` here, or
--- export IMAGE_NVIM_CELL_SIZE from the shell that does own the tty:
---
---   printf '\033[16t'   # reply: CSI 6 ; height ; width t
---
---@param option string|{ width: number, height: number }|nil
local set_cell_size = function(option)
  configured_cell_size = resolve_cell_size(option)
  update_size()
end

configured_cell_size = resolve_cell_size(nil)
update_size()

vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    -- A resize can also mean a font-size change, so recompute rather than reuse.
    update_size()
  end,
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
  set_cell_size = set_cell_size,
}
