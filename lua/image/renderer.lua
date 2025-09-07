local utils = require("image/utils")
local log = require("image/utils/logger").within("renderer")

-- Images get resized and cropped to fit in the context they are rendered in.
-- Each of these versions are written to the temp directory and cleared on reboot (on Linux at least).
-- This is where we keep track of the hashes of the resized and cropped versions of the images so we
-- can avoid processing and writing the same cropped/resized image variant multiple times.
---@type table<string, { resized: table<string>, cropped: table<string> }>
local cache = {}

-- FIXME: having multiple instances of the same image that are bounded to
--  different sizes cause the virt_line calculations to break (i think the
--  height gets miss calculated)

-- FIXME: horrible performance when you resize a window so that the image
--  "bounding box" changes

---@param image Image
local render = function(image)
  local state = image.global_state
  local term_size = utils.term.get_size()
  local scale_factor = 1.0
  if type(state.options.scale_factor) == "number" then scale_factor = state.options.scale_factor end
  local image_rows = math.floor(image.image_height / term_size.cell_height * scale_factor)
  local image_columns = math.floor(image.image_width / term_size.cell_width * scale_factor)
  local image_cache = cache[image.original_path] or { resized = {}, cropped = {} }

  log.debug(("render() %s"):format(image.id), {
    id = image.id,
    x = image.geometry.x,
    y = image.geometry.y,
    width = image.geometry.width,
    height = image.geometry.height,
  })

  local original_x = image.geometry.x or 0
  local original_y = image.geometry.y or 0
  local width = image.geometry.width or 0
  local height = image.geometry.height or 0
  local bounds = {
    top = 0,
    right = term_size.screen_cols,
    bottom = term_size.screen_rows,
    left = 0,
  }

  -- infer missing w/h component
  local aspect_ratio = image.image_width / image.image_height
  local geometry_width_px = width * term_size.cell_width
  local geometry_height_px = height * term_size.cell_height
  if width == 0 and height ~= 0 then width = math.ceil(geometry_height_px * aspect_ratio / term_size.cell_width) end
  if height == 0 and width ~= 0 then height = math.ceil(geometry_width_px / aspect_ratio / term_size.cell_height) end

  -- if both w/h are missing, use the image dimensions
  if width == 0 and height == 0 then
    width = image_columns
    height = image_rows
  end

  -- rendered size cannot be larger than the image itself
  -- width = math.min(width, image_columns)
  -- height = math.min(height, image_rows)

  -- screen max width/height
  width = math.min(width, term_size.screen_cols)
  -- height = math.min(height, term_size.screen_rows)

  log.debug(("(1) x: %d, y: %d, width: %d, height: %d"):format(original_x, original_y, width, height))

  if image.window ~= nil then
    -- log.debug("window info", vim.fn.getwininfo(image.window)[1])

    -- bail if the window is invalid
    local window = utils.window.get_window(image.window, {
      with_masks = state.options.window_overlap_clear_enabled,
      ignore_masking_filetypes = state.options.window_overlap_clear_ft_ignore,
    })
    if window == nil then
      log.debug("invalid window", { id = image.id })
      return false
    end

    -- bail if the window is not visible
    if not window.is_visible then
      log.debug("windows not visible", { id = image.id })
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
      return false
    end

    -- bail if the window is overlapped
    if state.options.window_overlap_clear_enabled and #window.masks > 0 then
      log.debug("overlap", { id = image.id })
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
      return false
    end

    -- if the image is tied to a buffer the window must be displaying that buffer
    if image.buffer ~= nil and window.buffer ~= image.buffer then
      log.debug("buffer not shown", { id = image.id })
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
      return false
    end

    -- check if image is in fold
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. image.window .. ")")
    local is_folded = vim.fn.foldclosed(original_y + 1) ~= -1
    vim.api.nvim_command("noautocmd call nvim_set_current_win(" .. current_win .. ")")

    -- bail if it is
    if image.buffer and is_folded then
      log.debug("image is inside a fold", { id = image.id })
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
      image:clear(true)
      return false
    end

    -- window bounds
    bounds = window.rect
    -- subtract 1 for normal windows, not floating windows
    -- TODO: do we even still need this?
    if not window.is_floating then bounds.bottom = bounds.bottom - 1 end

    -- only apply global offsets to non-floating windows
    if not window.is_floating then
      -- global offsets
      local global_offsets = utils.offsets.get_global_offsets(window.id)

      log.debug("  Applying global offsets: " .. vim.inspect(global_offsets))

      -- this is ugly, and if get_global_offsets() is changed this could break
      bounds.top = bounds.top + global_offsets.y
      bounds.bottom = bounds.bottom + global_offsets.y
      bounds.left = bounds.left + global_offsets.x
      bounds.right = bounds.right

      log.debug("  Bounds after offsets: " .. vim.inspect(bounds))
    else
      log.debug("  Floating window - NOT applying global offsets")
    end

    local max_width_window_percentage = --
      image.max_width_window_percentage --
      or state.options.max_width_window_percentage

    local max_height_window_percentage = --
      image.max_height_window_percentage --
      or state.options.max_height_window_percentage

    if not image.ignore_global_max_size then
      local offset_x = 0
      local offset_y = 0
      if not window.is_floating then
        local global_offsets = utils.offsets.get_global_offsets(window.id)
        offset_x = global_offsets.x
        offset_y = global_offsets.y
      end

      if type(max_width_window_percentage) == "number" then
        width = math.min(
          -- original
          width,
          -- max_window_percentage
          math.floor((window.width - offset_x) * max_width_window_percentage / 100)
        )
      end
      if type(max_height_window_percentage) == "number" then
        height = math.min(
          -- original
          height,
          -- max_window_percentage
          math.floor((window.height - offset_y) * max_height_window_percentage / 100)
        )
      end
    end
  end

  log.debug(("(2) x: %d, y: %d, width: %d, height: %d"):format(original_x, original_y, width, height))

  -- global max width/height
  if not image.ignore_global_max_size then
    if type(state.options.max_width) == "number" then width = math.min(width, state.options.max_width) end
    if type(state.options.max_height) == "number" then height = math.min(height, state.options.max_height) end
  end

  width, height = utils.math.adjust_to_aspect_ratio(term_size, image.image_width, image.image_height, width, height)

  local absolute_x, absolute_y
  if image.window == nil then
    absolute_x = original_x
    absolute_y = original_y
    -- apply render_offset_top
    if image.render_offset_top and image.render_offset_top > 0 then
      --
      absolute_y = absolute_y + image.render_offset_top
    end
  else
    -- get window object
    local window = nil
    if image.window then
      window = utils.window.get_window(image.window, {
        with_masks = state.options.window_overlap_clear_enabled,
        ignore_masking_filetypes = state.options.window_overlap_clear_ft_ignore,
      })
    end

    local win_info = vim.fn.getwininfo(image.window)[1]
    local win_config = vim.api.nvim_win_get_config(image.window)

    local screen_pos
    local is_partial_scroll = false

    -- calculate screen position based on window type
    if window and window.is_floating then
      -- for floating windows, the position is relative to the window's content area
      screen_pos = {
        row = window.rect.top + original_y + 1,
        col = window.rect.left + original_x + 1,
      }
    else
      -- for normal windows, we call screenpos
      screen_pos = vim.fn.screenpos(image.window, math.max(1, original_y), original_x + 1)
    end

    if
      screen_pos.col == 0 --
      and screen_pos.row == 0 --
    then
      -- the screen_pos is outside the window

      -- check if image is below the viewport
      if original_y > win_info.botline then
        log.debug(("Image %s is below viewport (line %d > botline %d)"):format(image.id, original_y, win_info.botline))
        if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
        state.images[image.id] = image
        return false -- image is below the visible window
      end

      -- special case: if the image is ON the topline, it should be visible at the top
      if original_y + 1 == win_info.topline then
        log.debug(("Image %s is ON topline %d, rendering at top"):format(image.id, win_info.topline))
        absolute_x = win_info.wincol - 1 + win_info.textoff + original_x
        absolute_y = win_info.winrow
        -- When image is on topline, we want normal rendering with padding
        is_partial_scroll = false
      else
        -- Calculate the difference between the top line and top pos of window
        -- Its the best way i found to calculate the possible extmark virt_lines
        -- that could be partially scrolled away.
        local topline_screen_pos = vim.fn.screenpos(image.window, win_info.topline, 0)
        local diff = topline_screen_pos.row - win_info.winrow

        log.debug(("Image %s at/near topline calc"):format(image.id), {
          original_y = original_y,
          topline = win_info.topline,
          topline_screen_row = topline_screen_pos.row,
          winrow = win_info.winrow,
          diff = diff,
          height = height,
        })

        if diff <= 0 then
          -- The topline is at a real buffer line (not in middle of virtual lines)
          log.debug(("Image %s diff <= 0, cannot calculate position"):format(image.id))
          if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
          state.images[image.id] = image
          return false -- cannot determine proper position
        end

        -- there is a diff which means that there are virt_lines that the user has
        -- partially scrolled past

        -- This calculation only makes sense if the image is at the line being scrolled (topline - 1)
        -- If the image is further up, it shouldn't be visible at all
        if original_y + 1 < win_info.topline - 1 then
          log.debug(
            ("Image %s is above the partially scrolled line (line %d < topline %d - 1), hiding"):format(
              image.id,
              original_y + 1,
              win_info.topline
            )
          )
          if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
          state.images[image.id] = image
          return false
        end

        is_partial_scroll = true
        -- diff represents how many rows of virtual content are visible above the topline
        -- When diff = height, all virtual lines visible, image should start at winrow
        -- When diff = 1, only bottom row visible
        -- The -1 accounts for 0-based vs 1-based indexing
        absolute_y = win_info.winrow - height + diff - 1
        -- Try to manually calculate the x pos of the image.
        -- We cant use the "built in" one since its out of bounds of the window
        -- and therefore returns two 0s
        absolute_x = win_info.wincol - 1 + win_info.textoff + original_x

        log.debug(("Image %s calculated position for partial scroll"):format(image.id), {
          absolute_x = absolute_x,
          absolute_y = absolute_y,
          calculation = string.format(
            "winrow(%d) - height(%d) + diff(%d) - 1 = %d",
            win_info.winrow,
            height,
            diff,
            absolute_y
          ),
        })
      end
    else
      absolute_x = screen_pos.col - 1
      absolute_y = screen_pos.row
    end
    -- apply render_offset_top offset if set (but not for floating windows and not during partial scroll)
    local is_floating = window and window.is_floating or false
    if image.render_offset_top and image.render_offset_top > 0 and not is_floating and not is_partial_scroll then
      absolute_y = absolute_y + image.render_offset_top
    end
  end

  -- clear out of bounds images
  local laststatus_offset = (vim.o.laststatus == 2 and 1 or 0)
  local is_above = absolute_y + height <= bounds.top
  local is_below = absolute_y > bounds.bottom + laststatus_offset
  local is_left = absolute_x + width <= bounds.left
  local is_right = absolute_x >= bounds.right

  if is_above or is_below or is_left or is_right then
    if image.is_rendered then
      log.debug(("CLEARING out of bounds image %s"):format(image.id))
      state.backend.clear(image.id, true)
    else
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
    end
    log.debug("out of bounds")
    return false
  end

  -- compute final geometry and prevent useless re rendering
  local rendered_geometry = { x = absolute_x, y = absolute_y, width = width, height = height }
  -- log.debug("rendered_geometry", { geometry = rendered_geometry, window = vim.fn.getwininfo(image.window)[1] })

  -- handle crop/resize
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  local crop_offset_top = 0
  local cropped_pixel_height = height * term_size.cell_height
  local needs_crop = false
  local needs_resize = false
  local initial_crop_hash = image.crop_hash
  local initial_resize_hash = image.resize_hash

  -- compute crop top/bottom
  -- crop top
  if absolute_y < bounds.top then
    local visible_rows = height - (bounds.top - absolute_y)

    -- if no rows are visible after cropping, don't render
    if visible_rows <= 0 then
      log.debug(("Image %s has no visible rows after crop, hiding"):format(image.id))
      if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
      state.images[image.id] = image
      return false
    end

    cropped_pixel_height = visible_rows * term_size.cell_height
    crop_offset_top = (bounds.top - absolute_y) * term_size.cell_height
    if not state.backend.features.crop then absolute_y = bounds.top end
    needs_crop = true
  end

  -- crop bottom
  if absolute_y + height > bounds.bottom then
    cropped_pixel_height = (bounds.bottom - absolute_y + 1) * term_size.cell_height
    needs_crop = true
  end

  -- compute resize
  local resize_hash = ("%d-%d"):format(pixel_width, pixel_height)
  if image.image_width ~= pixel_width then needs_resize = true end

  -- TODO make this non-blocking

  -- resize
  if needs_resize then
    if image.resize_hash ~= resize_hash then
      local cached_path = image_cache.resized[resize_hash]

      -- try cache
      if cached_path then
        log.debug(("using cached resized image %s"):format(cached_path))
        image.resized_path = cached_path
        image.resize_hash = resize_hash
      else
        -- perform resize
        local tmp_path = state.tmp_dir .. "/" .. vim.base64.encode(image.id) .. "-resized-" .. resize_hash .. ".png"
        image.resized_path = state.processor.resize(image.path, pixel_width, pixel_height, tmp_path)
        image.resize_hash = resize_hash
        image_cache.resized[resize_hash] = image.resized_path
      end
    end
  else
    image.resized_path = image.path
    image.resize_hash = nil
  end

  -- crop
  local crop_hash = ("%d-%d-%d-%d"):format(0, crop_offset_top, pixel_width, cropped_pixel_height)
  if needs_crop and not state.backend.features.crop then
    if (needs_resize and image.resize_hash ~= resize_hash) or image.crop_hash ~= crop_hash then
      local cached_path = image_cache.cropped[crop_hash]

      -- try cache;
      if cached_path then
        log.debug(("using cached cropped image %s"):format(cached_path))
        image.cropped_path = cached_path
        image.crop_hash = crop_hash
      else
        -- perform crop
        local tmp_path = state.tmp_dir .. "/" .. vim.base64.encode(image.id) .. "-cropped-" .. crop_hash .. ".png"
        image.cropped_path = state.processor.crop(
          image.resized_path or image.path,
          0,
          crop_offset_top,
          pixel_width,
          cropped_pixel_height,
          tmp_path
        )
        image.crop_hash = crop_hash
        image_cache.cropped[crop_hash] = image.cropped_path
      end
    end
  elseif needs_crop then
    image.cropped_path = image.resized_path
    image.crop_hash = crop_hash
  else
    image.cropped_path = image.resized_path
    image.crop_hash = nil
  end

  if
    image.is_rendered
    and image.rendered_geometry.x == rendered_geometry.x
    and image.rendered_geometry.y == rendered_geometry.y
    and image.rendered_geometry.width == rendered_geometry.width
    and image.rendered_geometry.height == rendered_geometry.height
    and image.crop_hash == initial_crop_hash
    and image.resize_hash == initial_resize_hash
  then
    log.debug("skipping render", { id = image.id })
    return true
  end

  log.debug(("rendering to backend %s"):format(image.id), {
    x = absolute_x,
    y = absolute_y,
    width = width,
    height = height,
    resize_hash = image.resize_hash,
    crop_hash = image.crop_hash,
    needs_crop = needs_crop,
    original_y = original_y,
    bounds = bounds,
    extmark_line = original_y + 1, -- extmark line in 1-indexed
  })

  image.bounds = bounds
  state.backend.render(image, absolute_x, absolute_y, width, height)
  image.rendered_geometry = rendered_geometry
  cache[image.original_path] = image_cache

  log.debug(("rendered %s"):format(image.id))
  return true
end

local clear_cache_for_path = function(path)
  cache[path] = nil
end

return {
  render = render,
  clear_cache_for_path = clear_cache_for_path,
}
