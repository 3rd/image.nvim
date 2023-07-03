local utils = require("image/utils")
local renderer = require("image/renderer")
local magick = require("image/magick")

-- { ["buf:row"]: { id, height } }
---@type table<string, { id: number, height: number }>
local buf_extmark_map = {}
local next_numerical_id = 1

---@param path string
---@param options? ImageOptions
---@param state State
---@return Image
local from_file = function(path, options, state)
  if options and options.id then
    local existing_image = state.images[options.id] ---@type Image
    if existing_image then return existing_image end
  end

  if not vim.loop.fs_stat(path) then utils.throw(("image.nvim: file not found: %s"):format(path)) end

  local actual_path = path
  local magick_image = magick.load_image(path)
  if not magick_image then error(("image.nvim: magick failed to load image: %s"):format(path)) end
  if magick_image:get_format():lower() ~= "png" then
    magick_image:set_format("png")
    actual_path = vim.fn.tempname()
    magick_image:write(actual_path)
  end

  local opts = options or {}
  local numerical_id = next_numerical_id
  next_numerical_id = next_numerical_id + 1

  ---@type Image
  local instance = {
    id = opts.id or utils.random.id(),
    internal_id = numerical_id,
    path = actual_path,
    original_path = path,
    image_width = magick_image:get_width(),
    image_height = magick_image:get_height(),
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
  }

  ---@param geometry? ImageGeometry
  instance.render = function(geometry)
    if geometry then instance.geometry = vim.tbl_deep_extend("force", instance.geometry, geometry) end

    -- utils.debug(("\n\n---------------- %s ----------------"):format(instance.id))
    local ok = renderer.render(instance, state)
    -- utils.debug("render result", instance.id, ok)

    -- virtual padding
    if instance.buffer and instance.with_virtual_padding then
      local row = instance.geometry.y
      local width = instance.rendered_geometry.width or 1
      local height = instance.rendered_geometry.height or 1

      local previous_extmark = buf_extmark_map[instance.buffer .. ":" .. row]

      if not ok and previous_extmark then
        state.backend.clear(instance.id, true)
        vim.api.nvim_buf_del_extmark(instance.buffer, state.extmarks_namespace, previous_extmark.id)
        buf_extmark_map[instance.buffer .. ":" .. row] = nil
        return
      end

      if previous_extmark then
        if previous_extmark.height == height then return end
        vim.api.nvim_buf_del_extmark(instance.buffer, state.extmarks_namespace, previous_extmark.id)
      end

      if ok then
        local text = string.rep(" ", width)
        local filler = {}
        for _ = 0, height - 1 do
          filler[#filler + 1] = { { text, "" } }
        end
        vim.api.nvim_buf_set_extmark(instance.buffer, state.extmarks_namespace, row - 1, 0, {
          id = numerical_id,
          virt_lines = filler,
        })
        buf_extmark_map[instance.buffer .. ":" .. row] = { id = numerical_id, height = height }
      end
    end
  end

  instance.clear = function()
    state.backend.clear(instance.id)
    instance.rendered_geometry = {
      x = nil,
      y = nil,
      width = nil,
      height = nil,
    }
    vim.api.nvim_buf_del_extmark(instance.buffer, state.extmarks_namespace, numerical_id)
    buf_extmark_map[instance.buffer .. ":" .. instance.geometry.y] = nil
  end

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

  local tmp_path = os.tmpname() .. ".png"
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
