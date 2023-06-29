local utils = require("image/utils")
local renderer = require("image/renderer")

-- { ["buf:row"]: { id, height } }
---@type table<string, { id: number, height: number }>
local buf_extmark_map = {}
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
    internal_id = numerical_id,
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
    is_rendered = false,
  }

  instance.get_dimensions = function()
    return utils.png.get_dimensions(instance.path)
  end

  ---@param geometry? ImageGeometry
  instance.render = function(geometry)
    if geometry then instance.geometry = vim.tbl_deep_extend("force", instance.geometry, geometry) end

    local ok = renderer.render(instance, state)

    -- virtual padding
    if instance.buffer and instance.with_virtual_padding then
      local row = instance.geometry.y
      local width = instance.rendered_geometry.width or 1
      local height = instance.rendered_geometry.height or 1

      -- for some reason this doesn't work, we set an extmark with 23 filler lines
      -- and when retrieving it, it has 25 lines
      -- local previous_extmark = vim.api.nvim_buf_get_extmarks(
      --   instance.buffer,
      --   state.extmarks_namespace,
      --   { row - 1, 0 },
      --   { row - 1, 0 },
      --   { details = true }
      -- )
      -- if #previous_extmark > 0 then
      --   local mark = previous_extmark[1]
      --   utils.debug("prev extmark", previous_extmark)
      --   local virt_height = #(mark[4].virt_lines or {})
      --   utils.debug("coaie", mark[4].virt_lines)
      --   for i, line in ipairs(mark[4].virt_lines or {}) do
      --     utils.debug(i, line)
      --   end
      --   if virt_height == height then
      --     utils.debug("extmark already exists", { id = numerical_id, buf = instance.buffer, height = height })
      --     return
      --   end
      --   utils.debug("deleting extmark", { id = numerical_id, buf = instance.buffer, height = virt_height })
      -- end

      --   vim.api.nvim_buf_get_extmark_by_id(instance.buffer, state.extmarks_namespace, numerical_id, {})
      -- if #previous_extmark > 0 then
      --   utils.debug("prev extmark", previous_extmark)
      --   if previous_extmark[1] == row - 1 then
      --     utils.debug(
      --       "extmark already exists",
      --       { id = numerical_id, buf = instance.buffer, height = height, row = previous_extmark[1] }
      --     )
      --     return
      --   end
      --   utils.debug("deleting extmark", { id = numerical_id, buf = instance.buffer, row = previous_extmark[1] })
      -- end

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

---@param path string
---@param options? ImageOptions
---@param state State
local from_file = function(path, options, state)
  return create_image(path, options, state)
end

return {
  from_file = from_file,
}
