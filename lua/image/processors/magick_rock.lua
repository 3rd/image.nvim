local utils = require("image/utils")
local magick = require("image/magick")

---@class MagickRockProcessor: ImageProcessor
local MagickRockProcessor = {}

function MagickRockProcessor.get_format(path)
  local result = utils.magic.detect_format(path)
  if result then return result end
  -- fallback to slower method:
  local image = magick.load_image(path)
  local format = image:get_format()
  image:destroy()
  return format:lower()
end

function MagickRockProcessor.convert_to_png(path, output_path)
  local image = magick.load_image(path)
  local out_path = output_path or path:gsub("%.[^.]+$", ".png")
  image:set_format("png")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.get_dimensions(path)
  local result = utils.dimensions.get_dimensions(path)
  if result then return result end
  -- fallback to slower method:
  local image = magick.load_image(path)
  local width = image:get_width()
  local height = image:get_height()
  image:destroy()
  return { width = width, height = height }
end

function MagickRockProcessor.resize(path, width, height, output_path)
  local image = magick.load_image(path)
  image:scale(width, height)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-resized.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.crop(path, x, y, width, height, output_path)
  local image = magick.load_image(path)
  image:crop(width, height, x, y)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-cropped.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.transform(path, request, output_path, callback)
  vim.schedule(function()
    local image = nil
    local ok, err = pcall(function()
      image = magick.load_image(path)
      if request.target_width and request.target_height then
        image:scale(request.target_width, request.target_height)
      end
      if request.crop then image:crop(request.crop.width, request.crop.height, request.crop.x, request.crop.y) end
      image:set_format(request.output_format or "png")
      image:write(output_path)
      image:destroy()
      image = nil
    end)

    if image then pcall(function()
      image:destroy()
    end) end
    if ok then
      callback({ ok = true, path = output_path })
    else
      callback({ ok = false, error = tostring(err) })
    end
  end)
end

function MagickRockProcessor.brightness(path, brightness, output_path)
  local image = magick.load_image(path)
  image:modulate(brightness)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-bright.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.saturation(path, saturation, output_path)
  local image = magick.load_image(path)
  image:modulate(nil, saturation)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-sat.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.hue(path, hue, output_path)
  local image = magick.load_image(path)
  image:modulate(nil, nil, hue)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-hue.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

return MagickRockProcessor
