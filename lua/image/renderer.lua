local utils = require("image/utils")

---@return { x: number, y: number }
local get_global_offsets = function()
  local x = 0
  local y = 0
  if vim.opt.number then x = x + vim.opt.numberwidth:get() end
  if vim.opt.signcolumn ~= "no" then x = x + 2 end
  if vim.opt.showtabline == 2 then y = y + 1 end
  if vim.opt.winbar ~= "none" then y = y + 1 end
  return { x = x, y = y }
end

---@param term_size { cell_width: number, cell_height: number }
---@param dimensions { width: number, height: number }
---@param width number
---@param height number
local adjust_to_aspect_ratio = function(term_size, dimensions, width, height)
  local aspect_ratio = dimensions.width / dimensions.height
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  if width > height then
    local new_height = math.ceil(pixel_width / aspect_ratio / term_size.cell_height)
    utils.debug("adjust_to_aspect_ratio() landscape", { new_height = new_height })
    return width, new_height
  else
    local new_width = math.ceil(pixel_height * aspect_ratio / term_size.cell_width)
    utils.debug("adjust_to_aspect_ratio() portrait", { new_width = new_width })
    return new_width, height
  end
end

---@param image Image
---@param state State
local render = function(image, state)
  local term_size = utils.term.get_size()
  local image_dimensions = image.get_dimensions()
  local image_rows = math.ceil(image_dimensions.height / term_size.cell_height)
  local image_columns = math.ceil(image_dimensions.width / term_size.cell_width)

  local x = image.geometry.x or 0
  local y = image.geometry.y or 0
  local x_offset = 0
  local y_offset = 0
  local width = image.geometry.width or 0
  local height = image.geometry.height or 0
  local window_offset_x = 0
  local window_offset_y = 0

  -- infer missing w/h component
  if width == 0 and height ~= 0 then width = math.ceil(height * image_dimensions.width / image_dimensions.height) end
  if height == 0 and width ~= 0 then height = math.ceil(width * image_dimensions.height / image_dimensions.width) end

  -- if both w/h are missing, use the image dimensions
  if width == 0 and height == 0 then
    width = image_columns
    height = image_rows
  end

  utils.debug(
    ("render(1): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
  )

  -- rendered size cannot be larger than the image itself
  width = math.min(width, image_columns)
  height = math.min(height, image_rows)

  -- screen max width/height
  width = math.min(width, term_size.screen_cols)
  height = math.min(width, term_size.screen_rows)

  utils.debug(
    ("render(2): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
  )

  if image.window ~= nil then
    -- window is valid
    local window = utils.window.get_window(image.window)
    if window == nil then return false end

    -- window is visibile
    if not window.is_visible then return false end

    -- if the image is tied to a buffer the window must be displaying that buffer
    if image.buffer ~= nil and window.buffer ~= image.buffer then return false end

    -- global offsets
    local global_offsets = get_global_offsets()
    x_offset = global_offsets.x - window.scroll_x
    y_offset = global_offsets.y + 1 - window.scroll_y
    utils.debug("scroll_y", { window.scroll_y, y_offset })

    -- window offsets
    window_offset_x = window.x
    window_offset_y = window.y

    -- extmark offsets
    if image.buffer then
      -- local win_info = vim.fn.getwininfo(image.window)[1]
      local extmark_offset_y = 0
      local extmarks = vim.api.nvim_buf_get_extmarks(image.buffer, -1, 0, -1, { details = true })
      for _, extmark in ipairs(extmarks) do
        local mark_id, mark_row, mark_col, mark_opts = unpack(extmark)
        local virt_height = #(mark_opts.virt_lines or {})
        utils.debug(("render() mark_id=%d mark_row=%d virt_height=%d"):format(mark_id, mark_row, virt_height))
        if mark_row + 1 >= y then break end
        y_offset = y_offset - virt_height
        utils.debug(("render() extmark_offset_y=%d"):format(extmark_offset_y))
      end
    end

    -- w/h can take at most 100% of the window
    width = math.min(width, window.width - x - x_offset)
    height = math.min(height, window.height - y - y_offset)
    utils.debug(
      ("render(3): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
    )

    -- global max window width/height percentage (ex. 50 -> 50%)
    if type(state.options.max_width_window_percentage) == "number" then
      width = math.min(width, math.floor(window.width * state.options.max_width_window_percentage / 100))
    end
    if type(state.options.max_height_window_percentage) == "number" then
      height = math.min(height, math.floor(window.height * state.options.max_height_window_percentage / 100))
    end

    utils.debug(
      ("render(4): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
    )
  end

  -- global max width/height
  if type(state.options.max_width) == "number" then width = math.min(width, state.options.max_width) end
  if type(state.options.max_height) == "number" then height = math.min(height, state.options.max_height) end
  utils.debug(
    ("render(5): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
  )

  width, height = adjust_to_aspect_ratio(term_size, image_dimensions, width, height)
  utils.debug(
    ("render(6): x=%d y=%d w=%d h=%d x_offset=%d y_offset=%d"):format(x, y, width, height, x_offset, y_offset)
  )

  if width <= 0 or height <= 0 then return false end

  local absolute_x = x + x_offset + window_offset_x
  local absolute_y = y + y_offset + window_offset_y

  state.backend.render(image, absolute_x, absolute_y, width, height)
  image.rendered_geometry = { x = absolute_x, y = absolute_y, width = width, height = height }

  -- utils.debug(state.images)
  return true
end

return {
  get_global_offsets = get_global_offsets,
  render = render,
}
