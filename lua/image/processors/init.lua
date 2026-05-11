---@type table<string, string>
local processor_modules = {
  magick_cli = "image/processors/magick_cli",
  magick_rock = "image/processors/magick_rock",
}

---@param name string
local function validate_processor(name)
  if not processor_modules[name] then error("image.nvim: processor not found: " .. tostring(name)) end
end

---@type table<string, ImageProcessor>
local loaded_processors = {}

---@param name string
---@return ImageProcessor
local function get_processor(name)
  validate_processor(name)
  if not loaded_processors[name] then loaded_processors[name] = require(processor_modules[name]) end
  return loaded_processors[name]
end

---@param name string
---@return ImageProcessor
local function create_lazy_processor(name)
  validate_processor(name)
  local processor = nil
  return setmetatable({}, {
    __index = function(_, key)
      if not processor then processor = get_processor(name) end
      return processor[key]
    end,
    __newindex = function(_, key, value)
      if not processor then processor = get_processor(name) end
      processor[key] = value
    end,
  })
end

return {
  create_lazy_processor = create_lazy_processor,
  get_processor = get_processor,
  validate_processor = validate_processor,
}
