local magick_cli = require("image/processors/magick_cli")

---@type table<string, ImageProcessor>
local processors = {
  magick_cli = magick_cli,
}

---@param name string
---@return ImageProcessor
local function get_processor(name)
  if name == "magick_rock" and not processors.magick_rock then
    processors.magick_rock = require("image/processors/magick_rock")
  end
  local processor = processors[name]
  if not processor then error("image.nvim: processor not found: " .. name) end
  return processor
end

return {
  get_processor = get_processor,
}
