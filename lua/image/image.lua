local utils = require("image/utils")
local renderer = require("image/renderer")
local magick = require("image/magick")

-- { ["buf:row"]: { id, height } }
---@type table<string, { id: number, height: number }>
local buf_extmark_map = {}

---@type Image
local Image = {
  next_internal_id = 1,
}
Image.__index = Image

---@param template Image
---@param global_state State
---@return Image
local createImage = function(template, global_state)
  local instance = template or {}
  instance.global_state = global_state

  instance.internal_id = Image.next_internal_id
  Image.next_internal_id = Image.next_internal_id + 1

  setmetatable(instance, Image)
  return instance
end

---@param geometry? ImageGeometry
function Image:render(geometry)
  if geometry then self.geometry = vim.tbl_deep_extend("force", self.geometry, geometry) end

  -- utils.debug(("\n\n---------------- %s ----------------"):format(self.id))
  local was_rendered = renderer.render(self)
  -- utils.log("render result", self.id, was_rendered)

  -- virtual padding
  if self.buffer and self.with_virtual_padding then
    local row = self.geometry.y
    local width = self.rendered_geometry.width or 1
    local height = self.rendered_geometry.height or 1

    local previous_extmark = buf_extmark_map[self.buffer .. ":" .. row]

    if not was_rendered and previous_extmark then
      self.global_state.backend.clear(self.id, true)
      vim.api.nvim_buf_del_extmark(self.buffer, self.global_state.extmarks_namespace, previous_extmark.id)
      buf_extmark_map[self.buffer .. ":" .. row] = nil
      return
    end

    if previous_extmark then
      if previous_extmark.height == height then return end
      vim.api.nvim_buf_del_extmark(self.buffer, self.global_state.extmarks_namespace, previous_extmark.id)
    end

    if was_rendered then
      local text = string.rep(" ", width)
      local filler = {}
      for _ = 0, height - 1 do
        filler[#filler + 1] = { { text, "" } }
      end
      vim.api.nvim_buf_set_extmark(self.buffer, self.global_state.extmarks_namespace, row - 1, 0, {
        id = self.internal_id,
        virt_lines = filler,
      })
      buf_extmark_map[self.buffer .. ":" .. row] = { id = self.internal_id, height = height }

      -- rerender any images that are below this one
      for _, image in pairs(self.global_state.images) do
        if image.buffer == self.buffer and image.geometry.y > self.geometry.y then image:render() end
      end
    end
  end
end

function Image:clear()
  self.global_state.backend.clear(self.id)
  self.rendered_geometry = {
    x = nil,
    y = nil,
    width = nil,
    height = nil,
  }
  if self.buffer then
    vim.api.nvim_buf_del_extmark(self.buffer, self.global_state.extmarks_namespace, self.internal_id)
    buf_extmark_map[self.buffer .. ":" .. self.geometry.y] = nil
  end
end

function Image:move(x, y)
  self.geometry.x = x
  self.geometry.y = y
  self:render()
end

---@param brightness number
function Image:brightness(brightness)
  local magick_image = magick.load_image(self.path)
  if not magick_image then error(("image.nvim: magick failed to load image: %s"):format(self.path)) end
  magick_image:modulate(brightness)
  local tmp_file = self.global_state.tmp_dir .. "/" .. utils.random.id()
  magick_image:write(tmp_file)
  self.path = tmp_file
  self.cropped_path = tmp_file
  magick_image:destroy()
  if self.is_rendered then
    self:clear()
    self:render()
  end
end

---@param saturation number
function Image:saturation(saturation)
  local magick_image = magick.load_image(self.path)
  if not magick_image then error(("image.nvim: magick failed to load image: %s"):format(self.path)) end
  magick_image:modulate(nil, saturation)
  local tmp_file = self.global_state.tmp_dir .. "/" .. utils.random.id()
  magick_image:write(tmp_file)
  self.path = tmp_file
  self.cropped_path = tmp_file
  magick_image:destroy()
  if self.is_rendered then
    self:clear()
    self:render()
  end
end

---@param hue number
function Image:hue(hue)
  local magick_image = magick.load_image(self.path)
  if not magick_image then error(("image.nvim: magick failed to load image: %s"):format(self.path)) end
  magick_image:modulate(nil, nil, hue)
  local tmp_file = self.global_state.tmp_dir .. "/" .. utils.random.id()
  magick_image:write(tmp_file)
  self.path = tmp_file
  self.cropped_path = tmp_file
  magick_image:destroy()
  if self.is_rendered then
    self:clear()
    self:render()
  end
end

---@param path string
---@param options? ImageOptions
---@param state State
---@return Image
local from_file = function(path, options, state)
  local opts = options or {}
  if options and options.id then
    local existing_image = state.images[options.id] ---@type Image
    if existing_image then return existing_image end
  end

  local absolute_path = vim.fn.fnamemodify(path, ":p")
  if not vim.loop.fs_stat(absolute_path) then utils.throw(("image.nvim: file not found: %s"):format(absolute_path)) end

  local rendered_path = absolute_path
  local magick_image = magick.load_image(absolute_path)
  if not magick_image then error(("image.nvim: magick failed to load image: %s"):format(absolute_path)) end
  if magick_image:get_format():lower() ~= "png" then
    magick_image:set_format("png")
    rendered_path = state.tmp_dir .. "/" .. utils.random.id()
    magick_image:write(rendered_path)
  end
  local image_width = magick_image:get_width()
  local image_height = magick_image:get_height()
  magick_image:destroy()

  local instance = createImage({
    id = opts.id or utils.random.id(),
    path = rendered_path,
    cropped_path = rendered_path,
    original_path = path,
    image_width = image_width,
    image_height = image_height,
    window = opts.window or nil,
    buffer = opts.buffer or nil,
    geometry = {
      x = opts.x or nil,
      y = opts.y or nil,
      width = opts.width or nil,
      height = opts.height or nil,
    },
    rendered_geometry = {
      x = nil,
      y = nil,
      width = nil,
      height = nil,
    },
    with_virtual_padding = opts.with_virtual_padding or false,
    is_rendered = false,
    crop_resize_hash = nil,
  }, state)

  return instance
end

---@param url string
---@param options? ImageOptions
---@param callback fun(image: Image|nil)
---@param state State
local from_url = function(url, options, callback, state)
  if state.remote_cache[url] then
    local image = from_file(state.remote_cache[url], options, state)
    callback(image)
    return
  end

  local tmp_path = state.tmp_dir .. "/" .. utils.random.id() .. ".png"
  local stdout = vim.loop.new_pipe()

  vim.loop.spawn("curl", {
    args = { "-s", "-o", tmp_path, url },
    stdio = { nil, stdout, nil },
    hide = true,
  }, function(code, signal)
    if code ~= 0 then
      utils.throw("image: curl errored while downloading " .. url, {
        code = code,
        signal = signal,
      })
    end
  end)

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if not data then utils.debug("image: downloaded " .. url .. " to " .. tmp_path) end
    state.remote_cache[url] = tmp_path

    vim.defer_fn(function()
      local ok, image = pcall(from_file, tmp_path, options, state)
      if ok then callback(image) end
    end, 0)
  end)
end

return {
  from_file = from_file,
  from_url = from_url,
}
