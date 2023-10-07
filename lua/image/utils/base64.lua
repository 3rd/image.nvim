-- LuaJIT FFI Base64 encoder/decoder
-- Copyright (c) 2022 Edward Lufadeju (edward@ncade.com)
-- See end of file for license information

local ffi = require("ffi")
local base64 = {}

local b64 = ffi.new("unsigned const char[65]", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-")

function base64.encode(str)
  ---@diagnostic disable-next-line: undefined-global
  local band, bor, lsh, rsh = bit.band, bit.bor, bit.lshift, bit.rshift
  local len = #str
  local enc_len = 4 * math.ceil(len / 3) -- (len + 2) // 3 * 4 after Lua 5.3

  local src = ffi.new("unsigned const char[?]", len + 1, str)
  local enc = ffi.new("unsigned char[?]", enc_len + 1)

  local i, j = 0, 0
  while i < len - 2 do
    enc[j] = b64[band(rsh(src[i], 2), 0x3F)]
    enc[j + 1] = b64[bor(lsh(band(src[i], 0x3), 4), rsh(band(src[i + 1], 0xF0), 4))]
    enc[j + 2] = b64[bor(lsh(band(src[i + 1], 0xF), 2), rsh(band(src[i + 2], 0xC0), 6))]
    enc[j + 3] = b64[band(src[i + 2], 0x3F)]
    i, j = i + 3, j + 4
  end

  if i < len then
    enc[j] = b64[band(rsh(src[i], 2), 0x3F)]
    if i == len - 1 then
      enc[j + 1] = b64[lsh(band(src[i], 0x3), 4)]
      enc[j + 2] = 0x3D
    else
      enc[j + 1] = b64[bor(lsh(band(src[i], 0x3), 4), rsh(band(src[i + 1], 0xF0), 4))]
      enc[j + 2] = b64[lsh(band(src[i + 1], 0xF), 2)]
    end
    enc[j + 3] = 0x3D
  end

  return ffi.string(enc, enc_len)
end

return base64

--[[
MIT License

Copyright (c) 2022 Edward Lufadeju

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
