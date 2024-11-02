local image_signatures = {
  PNG = "\x89\x50\x4E\x47",
  JPEG = "\xFF\xD8\xFF",
  WEBP = "\x52\x49\x46\x46",
  GIF = "\x47\x49\x46\x38",
  BMP = "\x42\x4D",
  HEIC = "\x66\x74\x79\x70",
  XPM = "\x2F\x2A\x20\x58\x50\x4D\x20\x2A\x2F",
  ICO = "\x00\x00\x01\x00",
  AVIF = "\x66\x74\x79\x70\x61\x76\x69\x66",
  SVG = "<svg",
  XML = "<?xml",
  PDF = "%PDF",
}

local function read_file_header(file, num_bytes)
  if not file then return nil end
  local current_pos = file:seek()
  file:seek("set", 0)
  local content = file:read(num_bytes)
  file:seek("set", current_pos)
  return content and { content:byte(1, #content) } or nil
end

local function has_jpeg_end_signature(file)
  if not file then return false end
  local size = file:seek("end")
  if size < 2 then return false end
  file:seek("set", size - 2)
  local end_signature = file:read(2)
  return end_signature == "\xFF\xD9", nil
end

local function is_image(path)
  local file, _ = io.open(path, "rb")
  if not file then return false end

  local max_bytes = 12
  local header, _ = read_file_header(file, max_bytes)
  if not header then
    file:close()
    return false
  end

  local is_image_flag = false
  for key, signature in pairs(image_signatures) do
    local bytes = { signature:byte(1, #signature) }
    local match = true
    if key == "AVIF" then
      for i = 1, #bytes do
        if header[i + 4] ~= bytes[i] then
          match = false
          break
        end
      end
    else
      for i = 1, #bytes do
        if header[i] ~= bytes[i] then
          match = false
          break
        end
      end
    end
    if match then
      if key == "JPEG" then
        is_image_flag = has_jpeg_end_signature(file)
      else
        is_image_flag = true
      end
      break
    end
  end

  file:close()
  return is_image_flag
end

return {
  is_image = is_image,
}
