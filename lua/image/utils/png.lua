local ffi = require("ffi")

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/fs.lua

-- big endian
local bytes2int = function(bufp)
  ---@diagnostic disable-next-line: undefined-global
  local bor, lsh = bit.bor, bit.lshift
  return bor(lsh(bufp[0], 24), lsh(bufp[1], 16), lsh(bufp[2], 8), bufp[3])
end

---@return { width: number, height: number }
local get_dimensions = function(path)
  local fd = assert(vim.loop.fs_open(path, "r", 438))
  local buf = ffi.new("const unsigned char[?]", 25, assert(vim.loop.fs_read(fd, 24, 0)))
  assert(vim.loop.fs_close(fd))

  local width = bytes2int(buf + 16)
  local height = bytes2int(buf + 20)
  return { width = width, height = height }
end

local is_png = function(path)
  local fd = vim.loop.fs_open(path, "r", 438)
  if fd == nil then return end

  local sig = ffi.new("const unsigned char[?]", 9, assert(vim.loop.fs_read(fd, 8, 0)))

  return sig[0] == 137
    and sig[1] == 80
    and sig[2] == 78
    and sig[3] == 71
    and sig[4] == 13
    and sig[5] == 10
    and sig[6] == 26
    and sig[7] == 10
end

local get_chunked = function(buf)
  local len = ffi.sizeof(buf)
  local i, j, chunks = 0, 0, {}
  while i < len - 4096 do
    chunks[j] = ffi.string(buf + i, 4096)
    i, j = i + 4096, j + 1
  end
  chunks[j] = ffi.string(buf + i)
  return chunks
end

return {
  get_dimensions = get_dimensions,
  is_png = is_png,
  get_chunked = get_chunked,
}
