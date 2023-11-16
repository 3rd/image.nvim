-- local log = require("image/utils/logger")

local max_bytes = 9

local sigs = {
  "\x89\x50\x4E\x47", -- PNG
  "\xFF\xD8\xFF\xE0", -- JPEG
  "\x52\x49\x46\x46", -- WEBP
  "\x47\x49\x46\x38", -- GIF87a, GIF89a
  "\x42\x4D", -- BMP
  "\x66\x74\x79\x70", -- HEIC
  "\x2F\x2A\x20\x58\x50\x4D\x20\x2A\x2F", -- XPM
  "\x00\x00\x01\x00", -- ICO
  "<svg", -- SVG
  "<?xml", -- alternative SVG
}

---@param path string
---@param n? number
local get_header = function(path, n)
  local f = assert(io.open(path, "rb"))
  local bytes = { f:read(n):byte(1, n) }
  f:close()
  return bytes
end

local is_image = function(path)
  local header_bytes = get_header(path, max_bytes)
  -- local header_str = string.char(unpack(header_bytes))
  -- log.debug("signature", header_str)

  for _, sig in ipairs(sigs) do
    local match = true
    for i = 1, #sig do
      if header_bytes[i] ~= string.byte(sig, i) then
        match = false
        break
      end
    end
    if match then return true end
  end
  return false
end

return {
  is_image = is_image,
}
