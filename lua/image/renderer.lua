local log = require("image/utils/logger").within("renderer")
local transform_cache = require("image/utils/transform_cache")
local utils = require("image/utils")

-- document scans can recreate image objects for one id while a transform is still pending.
local pending_transform_owners = {}

local transform_crop_key = function(crop)
  if not crop then return "none" end
  return ("%d:%d:%d:%d"):format(crop.x, crop.y, crop.width, crop.height)
end

local transform_signature_for_request = function(
  source_format,
  pixel_width,
  pixel_height,
  crop,
  processor,
  backend_crop
)
  return table.concat({
    source_format,
    tostring(pixel_width),
    tostring(pixel_height),
    transform_crop_key(crop),
    processor or "",
    tostring(backend_crop or false),
    "png",
  }, "|")
end

local get_source_character_index = function(line, col)
  if col < 0 or col > #line then return nil end

  local character_index = vim.str_utfindex(line, col)
  if vim.str_byteindex(line, character_index) ~= col then return nil end
  return character_index
end

local is_source_grapheme_continuation = function(line, col, character_index)
  if col <= 0 or col >= #line then return false end

  local character_end = vim.str_byteindex(line, character_index + 1)
  return vim.fn.strchars(line:sub(1, col), true) == vim.fn.strchars(line:sub(1, character_end), true)
end

local conceal_applies_to_row = function(window, row)
  local mode = vim.api.nvim_get_mode().mode
  local mode_prefix = mode:sub(1, 1)
  local current_window = vim.api.nvim_get_current_win()

  if current_window == window and vim.api.nvim_win_get_cursor(window)[1] - 1 == row then
    local concealcursor_letter = "n"
    if mode_prefix == "i" or mode_prefix == "R" then
      concealcursor_letter = "i"
    elseif mode_prefix == "v" or mode_prefix == "V" or mode_prefix == "\22" then
      concealcursor_letter = "v"
    elseif mode_prefix == "c" then
      concealcursor_letter = "c"
    end
    if not vim.wo[window].concealcursor:find(concealcursor_letter, 1, true) then return false end
  end

  local is_visual_or_select_mode = mode_prefix == "v"
    or mode_prefix == "V"
    or mode_prefix == "\22"
    or mode_prefix == "s"
    or mode_prefix == "S"
    or mode_prefix == "\19"
  if
    is_visual_or_select_mode
    and not vim.wo[window].concealcursor:find("v", 1, true)
    and vim.api.nvim_win_get_buf(current_window) == vim.api.nvim_win_get_buf(window)
  then
    local cursor_row = vim.api.nvim_win_get_cursor(current_window)[1] - 1
    local visual_row = vim.fn.getpos("v")[2] - 1
    if row >= math.min(cursor_row, visual_row) and row <= math.max(cursor_row, visual_row) then return false end
  end

  return true
end

local resolve_concealed_screen_x = function(image, window, win_info, row, col, screen_pos)
  if
    not image.buffer
    or window.buffer ~= image.buffer
    or screen_pos.row == 0
    or screen_pos.col == 0
    or win_info.leftcol > 0
    or vim.wo[window.id].conceallevel < 2
  then
    return nil
  end
  if not conceal_applies_to_row(window.id, row) then return nil end

  local line = vim.api.nvim_buf_get_lines(image.buffer, row, row + 1, false)[1] or ""
  local anchor_character_index = get_source_character_index(line, col)
  if not anchor_character_index or is_source_grapheme_continuation(line, col, anchor_character_index) then
    return nil
  end

  local marks = vim.api.nvim_buf_get_extmarks(
    image.buffer,
    -1,
    { row, 0 },
    { row, col },
    { details = true, overlap = true }
  )
  local has_conceal_extmark = false
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details.conceal ~= nil and not details.invalid then
      has_conceal_extmark = true
      break
    end
  end
  if not has_conceal_extmark then return nil end

  local segment_start = col
  local segment_screen_pos = screen_pos
  for character_index = anchor_character_index - 1, 0, -1 do
    local source_col = vim.str_byteindex(line, character_index)
    local position = vim.fn.screenpos(window.id, row + 1, source_col + 1)
    if position.row == screen_pos.row and position.col > 0 then
      segment_start = source_col
      segment_screen_pos = position
    elseif position.row == 0 or position.row < screen_pos.row then
      break
    end
  end

  local segment_character_index = get_source_character_index(line, segment_start)
  if not segment_character_index or is_source_grapheme_continuation(line, segment_start, segment_character_index) then
    return nil
  end

  -- Syntax and match conceal are not represented by persistent extmarks.
  local match_conceals_segment = vim.api.nvim_win_call(window.id, function()
    for _, match in ipairs(vim.fn.getmatches(window.id)) do
      if match.group == "Conceal" then
        if match.pattern then
          -- matchbufline() cannot locate conceal that crosses a line boundary.
          if
            match.pattern:find("\\_", 1, true)
            or match.pattern:find("\\n", 1, true)
            or match.pattern:find("\n", 1, true)
          then
            return true
          end
          local engine_selector = match.pattern:sub(1, 5)
          local matchbufline_pattern = "\\C" .. match.pattern
          if engine_selector == "\\%#=0" or engine_selector == "\\%#=1" or engine_selector == "\\%#=2" then
            matchbufline_pattern = engine_selector .. "\\C" .. match.pattern:sub(6)
          end
          for _, pattern_match in ipairs(vim.fn.matchbufline(image.buffer, matchbufline_pattern, row + 1, row + 1)) do
            local match_start = pattern_match.byteidx
            local match_end = match_start + #pattern_match.text
            if match_start < col and match_end > segment_start then return true end
          end
        else
          local has_position = false
          for key, position in pairs(match) do
            if type(key) == "string" and key:match("^pos%d+$") then
              has_position = true
              if position[1] == row + 1 then
                if position[2] == nil then return true end

                local match_start = position[2] - 1
                local match_end = match_start + math.max(position[3] or 1, 1)
                if match_start < col and match_end > segment_start then return true end
              end
            end
          end
          if not has_position then return true end
        end
      end
    end
    return false
  end)
  if match_conceals_segment then return nil end
  local syntax_conceals_segment = vim.api.nvim_win_call(window.id, function()
    for character_index = segment_character_index, anchor_character_index - 1 do
      local source_col = vim.str_byteindex(line, character_index)
      if vim.fn.synconcealed(row + 1, source_col + 1)[1] == 1 then return true end
    end
    return false
  end)
  if syntax_conceals_segment then return nil end

  local concealed_ranges = {}
  local conceallevel = vim.wo[window.id].conceallevel

  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details.conceal ~= nil and not details.invalid then
      local ends_before_segment = details.end_row == row and details.end_col ~= nil and details.end_col <= segment_start
      if not ends_before_segment and not (mark[2] == row and mark[3] >= col) then
        if mark[2] ~= row or details.end_row ~= row or details.end_col == nil then return nil end
        local range_start = math.max(mark[3], segment_start)
        local range_end = math.min(details.end_col, col)
        if range_end > range_start then
          if conceallevel == 2 and details.conceal ~= "" then return nil end
          local range_start_character_index = get_source_character_index(line, mark[3])
          local range_end_character_index = get_source_character_index(line, details.end_col)
          if
            not range_start_character_index
            or not range_end_character_index
            or is_source_grapheme_continuation(line, mark[3], range_start_character_index)
            or is_source_grapheme_continuation(line, details.end_col, range_end_character_index)
          then
            return nil
          end

          concealed_ranges[#concealed_ranges + 1] = { start = range_start, finish = range_end }
        end
      end
    end
  end

  if #concealed_ranges == 0 then return nil end
  table.sort(concealed_ranges, function(a, b)
    return a.start < b.start
  end)

  local merged_ranges = {}
  for _, range in ipairs(concealed_ranges) do
    local previous = merged_ranges[#merged_ranges]
    if previous and range.start <= previous.finish then
      previous.finish = math.max(previous.finish, range.finish)
    else
      merged_ranges[#merged_ranges + 1] = range
    end
  end

  if line:sub(merged_ranges[1].start + 1, col):find("\t", 1, true) then return nil end

  local hidden_width = 0
  for _, range in ipairs(merged_ranges) do
    local hidden_text = line:sub(range.start + 1, range.finish)
    local range_width = vim.fn.strdisplaywidth(hidden_text)
    -- Wide concealed graphemes can change the wrapped row without updating screenpos().
    if segment_start > 0 and range_width ~= vim.fn.strchars(hidden_text, true) then return nil end
    hidden_width = hidden_width + range_width
  end

  local raw_width = screen_pos.col - segment_screen_pos.col
  local visible_width = raw_width - hidden_width
  if visible_width < 0 then return nil end

  if vim.wo[window.id].rightleft then
    local window_left = win_info.wincol - 1
    local text_left = window_left + win_info.textoff
    local text_right = window_left + (win_info.width - win_info.textoff) - 1
    local continuation_prefix = segment_screen_pos.col - 1 - text_left
    return text_right - continuation_prefix - visible_width
  end

  return segment_screen_pos.col - 1 + visible_width
end

-- FIXME: having multiple instances of the same image that are bounded to
--  different sizes cause the virt_line calculations to break (i think the
--  height gets miss calculated)

-- FIXME: horrible performance when you resize a window so that the image
--  "bounding box" changes

---@param image Image
local render = function(image)
  local state = image.global_state
  local term_size = utils.term.get_size()
  if not term_size then return end
  local scale_factor = 1.0
  if type(state.options.scale_factor) == "number" then scale_factor = state.options.scale_factor end
  local image_rows = math.floor(image.image_height / term_size.cell_height * scale_factor)
  local image_columns = math.floor(image.image_width / term_size.cell_width * scale_factor)

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
    absolute_y = absolute_y + (image.render_offset_top or 0)
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
      -- for normal windows, we call screenpos (original_y is 0-indexed, screenpos wants 1-indexed)
      screen_pos = vim.fn.screenpos(image.window, math.max(1, original_y + 1), original_x + 1)
    end

    if
      screen_pos.col == 0 --
      and screen_pos.row == 0 --
    then
      -- the screen_pos is outside the window

      -- check if image is below the viewport (original_y is 0-indexed, botline is 1-indexed)
      if original_y + 1 > win_info.botline then
        log.debug(
          ("Image %s is below viewport (line %d > botline %d)"):format(image.id, original_y + 1, win_info.botline)
        )
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
        local overlap_absolute_y = utils.virtual_padding.get_overlap_scroll_position(
          original_y,
          win_info.topline,
          win_info.winrow,
          height,
          image.render_offset_top,
          image.overlap
        )

        if overlap_absolute_y then
          -- explicit overlap can keep the image visible by covering real buffer lines, not virt_lines.
          is_partial_scroll = true
          absolute_y = overlap_absolute_y
          absolute_x = win_info.wincol - 1 + win_info.textoff + original_x
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
            -- The topline is at a real buffer line, not in the middle of virtual lines.
            log.debug(("Image %s diff <= 0, cannot calculate position"):format(image.id))
            if state.images[image.id] and state.images[image.id] ~= image then state.images[image.id]:clear(true) end
            state.images[image.id] = image
            return false
          elseif original_y + 1 < win_info.topline - 1 then
            -- This calculation only makes sense if the image is at the line being scrolled (topline - 1).
            -- If the image is further up, it should not be visible unless explicit overlap handled it above.
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
          else
            -- diff represents how many virtual rows are visible above the topline.
            -- When diff = height, all virtual lines are visible and the image starts at winrow.
            -- When diff = 1, only the bottom row is visible; the -1 accounts for 0-based math.
            is_partial_scroll = true
            absolute_y = win_info.winrow - height + diff - 1
            -- screenpos is out of bounds here, so calculate x from the window origin and text offset.
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
        end
      end
    else
      absolute_x = screen_pos.col - 1
      if window and not window.is_floating then
        absolute_x = resolve_concealed_screen_x(image, window, win_info, original_y, original_x, screen_pos)
          or absolute_x
      end
      absolute_y = screen_pos.row
    end
    -- apply render_offset_top except for floating windows or during partial scroll
    local is_floating = window and window.is_floating or false
    if not is_floating and not is_partial_scroll then absolute_y = absolute_y + (image.render_offset_top or 0) end

    -- account for inline virtual text (e.g. render-markdown indent) at the image row.
    -- only when x=0, since treesitter node:range() already includes virt text offsets
    -- for non-zero positions.
    if original_x == 0 and image.buffer then
      local ok_marks, extmarks = pcall(
        vim.api.nvim_buf_get_extmarks,
        image.buffer,
        -1,
        { original_y, 0 },
        { original_y, 0 },
        { details = true }
      )
      if ok_marks then
        for _, mark in ipairs(extmarks) do
          local details = mark[4]
          if details and details.virt_text and details.virt_text_pos == "inline" then
            for _, chunk in ipairs(details.virt_text) do
              absolute_x = absolute_x + vim.fn.strdisplaywidth(chunk[1])
            end
          end
        end
      end
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
  local initial_transform_key = image.transform_key

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

  if image.image_width ~= pixel_width then needs_resize = true end

  local crop_hash = ("%d-%d-%d-%d"):format(0, crop_offset_top, pixel_width, cropped_pixel_height)
  local source_format = (image.source_format or "png"):lower()
  local transform_crop = nil
  if needs_crop and not state.backend.features.crop then
    transform_crop = {
      x = 0,
      y = crop_offset_top,
      width = pixel_width,
      height = cropped_pixel_height,
    }
  end

  local needs_transform = needs_resize or transform_crop ~= nil or source_format ~= "png"
  local transform_key = nil

  if needs_transform then
    local transform_signature = transform_signature_for_request(
      source_format,
      pixel_width,
      pixel_height,
      transform_crop,
      state.options.processor,
      state.backend.features.crop
    )

    local source, source_error = transform_cache.source_identity(image.path)
    if not source then
      if pending_transform_owners[image.id] == image then pending_transform_owners[image.id] = nil end
      image.pending_transform_key = nil
      image.transform_signature = nil
      log.error(source_error)
      return image.is_rendered == true
    end

    local request = {
      source = source,
      source_format = source_format,
      target_width = pixel_width,
      target_height = pixel_height,
      crop = transform_crop,
      processor = state.options.processor,
      backend_crop = state.backend.features.crop,
      output_format = "png",
    }
    request.key = transform_cache.build_key(request)
    transform_key = request.key

    if image.transform_key == request.key and not image.pending_transform_key then
      image.transform_signature = transform_signature
    else
      if image.pending_transform_key == request.key and pending_transform_owners[image.id] == image then
        return image.is_rendered == true
      end

      local entry = transform_cache.get_or_queue(request, state.tmp_dir, function(output_path, complete)
        state.processor.transform(request.source.path, request, output_path, complete)
      end, function(completed_entry)
        if image.pending_transform_key ~= request.key then return end
        if pending_transform_owners[image.id] ~= image then return end

        pending_transform_owners[image.id] = nil
        image.pending_transform_key = nil
        if completed_entry.status ~= "complete" then
          log.error(("image transform failed for %s: %s"):format(image.id, completed_entry.error or "unknown error"))
          return
        end

        image:render()
      end)

      if entry.status == "pending" then
        image.pending_transform_key = request.key
        pending_transform_owners[image.id] = image
        local current_image = state.images[image.id]
        if not current_image or not current_image.is_rendered or current_image == image then
          state.images[image.id] = image
        end
        log.debug(("queued image transform %s"):format(image.id), { key = request.key })
        return image.is_rendered == true
      end

      if entry.status == "failed" then
        if pending_transform_owners[image.id] == image then pending_transform_owners[image.id] = nil end
        if image.pending_transform_key == request.key then image.pending_transform_key = nil end
        log.error(("image transform failed for %s: %s"):format(image.id, entry.error or "unknown error"))
        return image.is_rendered == true
      end

      image.resized_path = entry.output_path
      image.cropped_path = entry.output_path
      image.resize_hash = request.key
      image.transform_signature = transform_signature
    end
  else
    image.resized_path = image.path
    image.cropped_path = image.path
    image.resize_hash = nil
    image.transform_signature = nil
  end

  image.transform_key = transform_key
  image.crop_hash = needs_crop and crop_hash or nil

  if
    image.is_rendered
    and image.rendered_geometry.x == rendered_geometry.x
    and image.rendered_geometry.y == rendered_geometry.y
    and image.rendered_geometry.width == rendered_geometry.width
    and image.rendered_geometry.height == rendered_geometry.height
    and image.crop_hash == initial_crop_hash
    and image.resize_hash == initial_resize_hash
    and initial_transform_key == transform_key
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

  log.debug(("rendered %s"):format(image.id))
  return true
end

local clear_cache_for_path = function(path)
  transform_cache.clear_for_path(path)
end

return {
  render = render,
  clear_cache_for_path = clear_cache_for_path,
}
