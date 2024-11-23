local M = {}

local image_signatures = {
  png = "\x89\x50\x4E\x47",
  jpeg = "\xFF\xD8\xFF",
  webp = "\x52\x49\x46\x46",
  gif = "\x47\x49\x46\x38",
  bmp = "\x42\x4D",
  heic = "\x66\x74\x79\x70\x68\x65\x69\x63",
  xpm = "\x2F\x2A\x20\x58\x50\x4D\x20\x2A\x2F",
  ico = "\x00\x00\x01\x00",
  avif = "\x66\x74\x79\x70\x61\x76\x69\x66",
  svg = "<svg",
  xml = "<?xml",
  pdf = "%PDF",
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

local function check_signature_match(header, format, signature)
  local bytes = { signature:byte(1, #signature) }
  local match = true

  -- Both AVIF and HEIC signatures start at offset 4
  if format == "avif" or format == "heic" then
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

  return match
end

M.detect_format = function(path)
  local file, _ = io.open(path, "rb")
  if not file then return nil end

  local max_bytes = 16
  local header = read_file_header(file, max_bytes)
  if not header then
    file:close()
    return nil
  end

  for format, signature in pairs(image_signatures) do
    if check_signature_match(header, format, signature) then
      if format == "jpeg" then
        local is_jpeg = has_jpeg_end_signature(file)
        file:close()
        return is_jpeg and format or nil
      else
        file:close()
        return format
      end
    end
  end

  file:close()
  return nil
end

M.is_image = function(path)
  return M.detect_format(path) ~= nil
end

return M
