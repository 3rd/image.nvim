local utils = require("image/utils")
local has_magick, magick = pcall(require, "magick")

local function guard()
  if not has_magick then
    error("image.nvim: magick not found")
  end
end

---@class MagickRockProcessor: ImageProcessor
local MagickRockProcessor = {}

function MagickRockProcessor.get_format(path)
  local result = utils.magic.detect_format(path)
  if result then return result end
  -- fallback to slower method:
  guard()
  local image = magick.load_image(path)
  local format = image:get_format()
  image:destroy()
  return format:lower()
end

function MagickRockProcessor.convert_to_png(path, output_path)
  guard()
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
  guard()
  local image = magick.load_image(path)
  local width = image:get_width()
  local height = image:get_height()
  image:destroy()
  return { width = width, height = height }
end

function MagickRockProcessor.resize(path, width, height, output_path)
  guard()
  local image = magick.load_image(path)
  image:scale(width, height)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-resized.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.crop(path, x, y, width, height, output_path)
  guard()
  local image = magick.load_image(path)
  image:crop(width, height, x, y)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-cropped.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.brightness(path, brightness, output_path)
  guard()
  local image = magick.load_image(path)
  image:modulate(brightness)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-bright.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.saturation(path, saturation, output_path)
  guard()
  local image = magick.load_image(path)
  image:modulate(nil, saturation)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-sat.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

function MagickRockProcessor.hue(path, hue, output_path)
  guard()
  local image = magick.load_image(path)
  image:modulate(nil, nil, hue)
  local out_path = output_path or path:gsub("%.([^.]+)$", "-hue.%1")
  image:write(out_path)
  image:destroy()
  return out_path
end

return MagickRockProcessor
