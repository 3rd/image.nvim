local image_signatures = {
  PNG = "\x89\x50\x4E\x47",
  JPEG = "\xFF\xD8\xFF",
  WEBP = "\x52\x49\x46\x46",
  GIF = "\x47\x49\x46\x38",
  BMP = "\x42\x4D",
  HEIC = "\x66\x74\x79\x70",
  XPM = "\x2F\x2A\x20\x58\x50\x4D\x20\x2A\x2F",
  ICO = "\x00\x00\x01\x00",
  SVG = "<svg",
  XML = "<?xml",
}

local function read_file_header(path, numBytes)
  local file, err = io.open(path, "rb")
  if not file then return nil, "Failed to open file: " .. err end
  local content = file:read(numBytes)
  file:close()
  return content and { content:byte(1, #content) } or nil
end

local function has_jpeg_end_signature(path)
  local file, _ = io.open(path, "rb")
  if not file then return false end
  local size = file:seek("end")
  if size < 2 then
    file:close()
    return false
  end
  file:seek("set", size - 2)
  local end_signature = file:read(2)
  file:close()
  return end_signature == "\xFF\xD9", nil
end

local function is_image(path)
  local max_bytes = 9
  local header, err = read_file_header(path, max_bytes)
  if not header then return false, err end

  for _, signature in pairs(image_signatures) do
    local bytes = { signature:byte(1, #signature) }
    for i = 1, #bytes do
      if header[i] == bytes[i] then
        if signature == image_signatures.JPEG then
          if has_jpeg_end_signature(path) then return true, nil end
        else
          return true
        end
      end
    end
  end

  return false
end

return {
  is_image = is_image,
}
