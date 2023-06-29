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
    return width, new_height
  else
    local new_width = math.ceil(pixel_height * aspect_ratio / term_size.cell_width)
    return new_width, height
  end
end

---@param image Image
---@param state State
local render = function(image, state)
  local term_size = utils.term.get_size()
  local image_dimensions = image.get_dimensions()
  local image_rows = math.floor(image_dimensions.height / term_size.cell_height)
  local image_columns = math.floor(image_dimensions.width / term_size.cell_width)

  local x = image.geometry.x or 0
  local y = image.geometry.y or 0
  local x_offset = 0
  local y_offset = 0
  local width = image.geometry.width or 0
  local height = image.geometry.height or 0
  local window_offset_x = 0
  local window_offset_y = 0
  local bounds = {
    top = 0,
    right = term_size.screen_cols,
    bottom = term_size.screen_rows,
    left = 0,
  }
  local topfill = 0

  -- infer missing w/h component
  if width == 0 and height ~= 0 then width = math.ceil(height * image_dimensions.width / image_dimensions.height) end
  if height == 0 and width ~= 0 then height = math.ceil(width * image_dimensions.height / image_dimensions.width) end

  -- if both w/h are missing, use the image dimensions
  if width == 0 and height == 0 then
    width = image_columns
    height = image_rows
  end

  -- rendered size cannot be larger than the image itself
  width = math.min(width, image_columns)
  height = math.min(height, image_rows)

  -- screen max width/height
  width = math.min(width, term_size.screen_cols)
  height = math.min(width, term_size.screen_rows)

  utils.debug(("(1) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(x, y, width, height, y_offset))

  if image.window ~= nil then
    -- bail if the window is invalid
    local window = utils.window.get_window(image.window)
    if window == nil then return false end

    -- bail if the window is not visible
    if not window.is_visible then return false end

    -- if the image is tied to a buffer the window must be displaying that buffer
    if image.buffer ~= nil and window.buffer ~= image.buffer then return false end

    -- get topfill and check fold status
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. image.window .. ")")
    topfill = vim.fn.winsaveview().topfill
    local is_folded = vim.fn.foldclosed(image.geometry.y) ~= -1
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. current_win .. ")")

    -- bail if the image is inside a fold
    if image.buffer and is_folded then
      utils.debug("inside fold", image.id)
      return false
    end

    -- global offsets
    local global_offsets = get_global_offsets()
    x_offset = global_offsets.x - window.scroll_x
    y_offset = global_offsets.y + 1 - window.scroll_y

    -- window offsets
    window_offset_x = window.x
    window_offset_y = window.y

    -- window bounds
    bounds = {
      top = window.y + global_offsets.y,
      right = window.x + window.width - global_offsets.x,
      bottom = window.y + window.height - global_offsets.y,
      left = window.x + global_offsets.x,
    }

    -- w/h can take at most 100% of the window
    width = math.min(width, window.width - x - x_offset)
    height = math.min(height, window.height - y - y_offset)

    -- global max window width/height percentage
    if type(state.options.max_width_window_percentage) == "number" then
      width = math.min(width, math.floor(window.width * state.options.max_width_window_percentage / 100))
    end
    if type(state.options.max_height_window_percentage) == "number" then
      height = math.min(height, math.floor(window.height * state.options.max_height_window_percentage / 100))
    end
  end

  -- utils.debug(("(2) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(x, y, width, height, y_offset))

  -- global max width/height
  if type(state.options.max_width) == "number" then width = math.min(width, state.options.max_width) end
  if type(state.options.max_height) == "number" then height = math.min(height, state.options.max_height) end

  width, height = adjust_to_aspect_ratio(term_size, image_dimensions, width, height)

  if width <= 0 or height <= 0 then return false end

  -- utils.debug(("(3) x: %d, y: %d, width: %d, height: %d y_offset: %d"):format(x, y, width, height, y_offset))

  local absolute_x = x + x_offset + window_offset_x
  local absolute_y = y + y_offset + window_offset_y
  local prevent_rendering = false

  -- utils.debug(("(4) x: %d, y: %d, width: %d, height: %d y_offset: %d absolute_x: %d absolute_y: %d"):format( x, y, width, height, y_offset, absolute_x, absolute_y))

  -- extmark offsets
  if image.with_virtual_padding and image.window and image.buffer then

  if image.window and image.buffer then
    local win_info = vim.fn.getwininfo(image.window)[1]
    local topline = win_info.topline
    local botline = win_info.botline

    -- bail if out of bounds
    if image.geometry.y + 1 < topline or image.geometry.y > botline then prevent_rendering = true end

    -- extmark offsets
    if image.with_virtual_padding then
      -- bail if the image is above the top of the window and there's no topfill
      if topfill == 0 and image.geometry.y < topline then prevent_rendering = true end

      -- bail if the image + its height is above the top of the window + topfill
      if image.geometry.y + height + 1 < topline + topfill then prevent_rendering = true end

      -- bail if the image is below the bottom of the window
      if image.geometry.y > botline then prevent_rendering = true end

      -- offset by topfill if the image started above the top of the window
      if not prevent_rendering then
        if topfill > 0 and image.geometry.y < topline then
          --
          absolute_y = absolute_y - (height - topfill)
        else
          -- offset by any pre-y virtual lines
          local extmarks = vim.tbl_map(
            function(mark)
              ---@diagnostic disable-next-line: deprecated
              local mark_id, mark_row, mark_col, mark_opts = unpack(mark)
              local virt_height = #(mark_opts.virt_lines or {})
              return { id = mark_id, row = mark_row + 1, col = mark_col, height = virt_height }
            end,
            vim.api.nvim_buf_get_extmarks(
              image.buffer,
              -1,
              { topline - 1, 0 },
              { image.geometry.y, 0 },
              { details = true }
            )
          )

          local offset = topfill
          for _, mark in ipairs(extmarks) do
            if mark.row ~= image.geometry.y then offset = offset + mark.height end
          end

          absolute_y = absolute_y + offset
        end
      end
    end

    -- folds
    local offset = 0
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. image.window .. ")")

    if vim.wo.foldenable then
      local i = topline
      while i <= image.geometry.y do
        local fold_start, fold_end = vim.fn.foldclosed(i), vim.fn.foldclosedend(i)
        if fold_start ~= -1 and fold_end ~= -1 then
          utils.debug(("i: %d fold start: %d, fold end: %d"):format(i, fold_start, fold_end))
          offset = offset + (fold_end - fold_start)
          i = fold_end + 1
        else
          i = i + 1
        end
      end
    end
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. current_win .. ")")
    utils.debug(("fold offset: %d"):format(offset))
    absolute_y = absolute_y - offset
  end

  if prevent_rendering then absolute_y = -999999 end

  image.bounds = bounds
  local rendered_geometry = { x = absolute_x, y = absolute_y, width = width, height = height }

  -- prevent useless rerendering
  if
    image.is_rendered
    and image.rendered_geometry.x == rendered_geometry.x
    and image.rendered_geometry.y == rendered_geometry.y
    and image.rendered_geometry.width == rendered_geometry.width
    and image.rendered_geometry.height == rendered_geometry.height
  then
    return true
  end

  state.backend.render(image, absolute_x, absolute_y, width, height)
  image.rendered_geometry = rendered_geometry

  return true
end

return {
  get_global_offsets = get_global_offsets,
  render = render,
}
