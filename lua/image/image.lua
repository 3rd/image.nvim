local utils = require("image/utils")
local renderer = require("image/renderer")

local next_numerical_id = 1

---@param path string
---@param options? ImageOptions
---@param state State
local create_image = function(path, options, state)
  if options and options.id then
    local existing_image = state.images[options.id] ---@type Image
    if existing_image then return existing_image end
  end

  local opts = options or {}
  local numerical_id = next_numerical_id
  next_numerical_id = next_numerical_id + 1

  ---@type Image
  local instance = {
    id = opts.id or utils.random.id(),
    path = path,
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
  }

  instance.get_dimensions = function()
    return utils.png.get_dimensions(instance.path)
  end

  ---@param geometry? ImageGeometry
  instance.render = function(geometry)
    if geometry then instance.geometry = vim.tbl_deep_extend("force", instance.geometry, geometry) end

    local ok = renderer.render(instance, state)

    -- virtual padding
    if ok and instance.buffer and instance.with_virtual_padding then
      local row = instance.geometry.y - 1
      local width = instance.rendered_geometry.width or 1
      local height = instance.rendered_geometry.height or 1

      -- remove same-row extmarks
      -- local extmarks =
      --   vim.api.nvim_buf_get_extmarks(instance.buffer, state.extmarks_namespace, 0, -1, { details = true })
      -- for _, extmark in ipairs(extmarks) do
      --   local mark_id, mark_row, mark_col, mark_opts = unpack(extmark)
      --   local virt_height = #(mark_opts.virt_lines or {})
      --   if mark_row == row then
      --     if virt_height == height then return end
      --     vim.api.nvim_buf_del_extmark(instance.buffer, state.extmarks_namespace, mark_id)
      --   end
      -- end

      local text = string.rep(" ", width)
      local filler = {}
      for _ = 0, height - 1 do
        filler[#filler + 1] = { { text, "" } }
      end
      vim.api.nvim_buf_set_extmark(instance.buffer, state.extmarks_namespace, row, 0, {
        id = numerical_id,
        virt_lines = filler,
      })
    end
  end

  instance.clear = function()
    state.backend.clear(instance.id)
    utils.debug("extmark del", { id = numerical_id, buf = instance.buffer })
    vim.api.nvim_buf_del_extmark(instance.buffer, state.extmarks_namespace, numerical_id)
  end

  return instance
end

---@param path string
---@param options? ImageOptions
---@param state State
local from_file = function(path, options, state)
  return create_image(path, options, state)
end

return {
  from_file = from_file,
}
