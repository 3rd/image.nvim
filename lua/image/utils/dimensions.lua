local bit = require("bit")
local magic = require("image/utils/magic")

local M = {}

local function read_bytes(file, n)
  local bytes = file:read(n)
  if not bytes then return nil end
  local t = { bytes:byte(1, n) }
  if #t < n then return nil end
  return t
end

local function bytes_to_int(bytes, offset, length, is_big_endian)
  if not bytes then return nil end
  if #bytes < (offset + length) then return nil end

  local val = 0
  for i = 0, length - 1 do
    local byte_pos = offset + (is_big_endian and i or (length - 1 - i))
    local byte = bytes[byte_pos + 1]
    if not byte then return nil end
    val = val * 256 + byte
  end
  return val
end

local function read_box_header(file)
  local bytes = read_bytes(file, 8)
  if not bytes then return nil end

  local size = bytes_to_int(bytes, 0, 4, true)
  local type = string.char(bytes[5], bytes[6], bytes[7], bytes[8])

  return {
    size = size,
    type = type,
    header_size = 8,
  }
end

-- Shared ISOBMFF (AVIF/HEIC) handler
local function read_isobmff_dimensions(file)
  -- Get file size for bounds checking
  local current = file:seek()
  local file_size = file:seek("end")
  file:seek("set", current)

  while file:seek() < file_size do
    local box = read_box_header(file)
    if not box then break end

    -- Keep track of end position for seeking
    local data_start = file:seek()
    local next_box = data_start + box.size - box.header_size

    -- First look for 'meta' box
    if box.type == "meta" then
      -- Skip version and flags
      if not pcall(function()
        file:seek("cur", 4)
      end) then break end

      -- Now look for boxes inside meta
      while file:seek() < next_box do
        local inner_box = read_box_header(file)
        if not inner_box then break end

        local inner_start = file:seek()
        local inner_next = inner_start + inner_box.size - inner_box.header_size

        if inner_box.type == "iprp" then
          -- Process iprp box contents
          while file:seek() < inner_next do
            local iprp_box = read_box_header(file)
            if not iprp_box then break end

            local iprp_start = file:seek()

            -- Look for ipco box
            if iprp_box.type == "ipco" then
              while file:seek() < iprp_start + iprp_box.size - iprp_box.header_size do
                local prop_box = read_box_header(file)
                if not prop_box then break end

                if prop_box.type == "ispe" then
                  -- Skip version and flags
                  if not pcall(function()
                    file:seek("cur", 4)
                  end) then break end

                  -- Read dimensions
                  local dims = read_bytes(file, 8)
                  if not dims then break end

                  local width = bytes_to_int(dims, 0, 4, true)
                  local height = bytes_to_int(dims, 4, 4, true)
                  if width and height then return { width = width, height = height } end
                end

                -- Skip to next property box
                if
                  not pcall(function()
                    file:seek("set", file:seek() + prop_box.size - prop_box.header_size)
                  end)
                then
                  break
                end
              end
            end

            -- Skip to next box in iprp
            if
              not pcall(function()
                file:seek("set", iprp_start + iprp_box.size - iprp_box.header_size)
              end)
            then
              break
            end
          end
        end

        -- Skip to next box in meta
        if not pcall(function()
          file:seek("set", inner_next)
        end) then break end
      end
    end

    -- Skip to next top-level box
    if not pcall(function()
      file:seek("set", next_box)
    end) then break end
  end

  return nil
end

local handlers = {}

handlers.avif = function(file)
  return read_isobmff_dimensions(file)
end

handlers.png = function(file)
  file:seek("set", 16)
  local dims = read_bytes(file, 8)
  if not dims then return nil end

  local width = bytes_to_int(dims, 0, 4, true)
  local height = bytes_to_int(dims, 4, 4, true)
  if not width or not height then return nil end

  return { width = width, height = height }
end

handlers.jpeg = function(file)
  file:seek("set", 2) -- Skip JPEG header marker

  while true do
    local marker = read_bytes(file, 2)
    if not marker then break end

    -- Look for Start Of Frame markers
    if
      marker[1] == 0xFF
      and (
        marker[2] == 0xC0 -- SOF0 (Baseline)
        or marker[2] == 0xC1 -- SOF1 (Extended Sequential)
        or marker[2] == 0xC2 -- SOF2 (Progressive)
        or marker[2] == 0xC3 -- SOF3 (Lossless)
      )
    then
      local length = read_bytes(file, 2)
      if not length then break end

      -- Skip precision byte
      file:seek("cur", 1)

      local dims = read_bytes(file, 4)
      if not dims then break end

      local height = dims[1] * 256 + dims[2]
      local width = dims[3] * 256 + dims[4]

      if width == 0 or height == 0 then return nil end
      return { width = width, height = height }
    end

    -- Skip unknown/unsupported segments
    local length = read_bytes(file, 2)
    if not length then break end
    local skip_length = bytes_to_int(length, 0, 2, true)
    if not skip_length then break end

    if
      not pcall(function()
        file:seek("cur", skip_length - 2) -- -2 because we already read the length bytes
      end)
    then
      break
    end
  end

  return nil
end

handlers.gif = function(file)
  file:seek("set", 6)
  local dims = read_bytes(file, 4)
  if not dims then return nil end

  local width = bytes_to_int(dims, 0, 2, false)
  local height = bytes_to_int(dims, 2, 2, false)
  if not width or not height then return nil end

  return { width = width, height = height }
end

handlers.webp = function(file)
  -- Skip RIFF header
  file:seek("set", 12)

  -- Read VP8 chunk header
  local chunk_header = read_bytes(file, 4)
  if not chunk_header then return nil end

  -- Skip chunk size
  file:seek("cur", 4)

  -- Read dimensions
  local dims = read_bytes(file, 10)
  if not dims then return nil end

  -- Extract size from frame tag
  local width = bit.bor(dims[7], bit.lshift(bit.band(dims[8], 0x3F), 8))
  local height = bit.bor(dims[9], bit.lshift(bit.band(dims[10], 0x3F), 8))

  return { width = width, height = height }
end

handlers.bmp = function(file)
  file:seek("set", 18)
  local dims = read_bytes(file, 8)
  if not dims then return nil end

  local width = bytes_to_int(dims, 0, 4, false)
  local height = bytes_to_int(dims, 4, 4, false)
  if not width or not height then return nil end

  return { width = width, height = height }
end

handlers.ico = function(file)
  local header = read_bytes(file, 6)
  if not header then return nil end

  local num_images = bytes_to_int(header, 4, 2, false)
  if not num_images or num_images == 0 then return nil end

  -- Read first image entry
  local dims = read_bytes(file, 2)
  if not dims then return nil end

  -- ICO uses 0 to represent 256
  local width = dims[1] == 0 and 256 or dims[1]
  local height = dims[2] == 0 and 256 or dims[2]

  return { width = width, height = height }
end

handlers.heic = function(file)
  return read_isobmff_dimensions(file)
end

handlers.xpm = function(file)
  local content = file:read(1024) -- Read enough to get past the header
  if not content then return nil end

  -- Look for the dimensions line, typically like: "512 512 2 1"
  for line in content:gmatch("[^\n]+") do
    local w, h = line:match("%s*(%d+)%s+(%d+)%s+%d+%s+%d+")
    if w and h then return {
      width = tonumber(w),
      height = tonumber(h),
    } end
  end
  return nil
end

---Get image dimensions without spawning external process
---@param path string Path to image file
---@return table? dimensions Table with width and height, or nil if format not supported
M.get_dimensions = function(path)
  -- Detect format using magic module
  local format = magic.detect_format(path)
  if not format then return nil end

  -- Skip SVG/XML/PDF as they require more complex parsing
  if format == "svg" or format == "xml" or format == "pdf" then return nil end

  local file = io.open(path, "rb")
  if not file then return nil end

  local handler = handlers[format]
  if not handler then return nil end

  local dimensions = handler(file)

  file:close()

  return dimensions
end

return M
