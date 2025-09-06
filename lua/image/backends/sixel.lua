local utils = require("image/utils")
local log = require("image/utils/logger").within("backend.sixel")

local MAX_CACHE_SIZE = 50
local FLUSH_DELAY_MS = 50

local sixel_cache = {}
local cache_order = {}
local frame_desired = {}
local flush_timer = nil
local frame_version = 0
local last_painted_version = -1
local flush_in_progress = false

---@type Backend
---@diagnostic disable-next-line: missing-fields
local backend = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  state = nil,
  features = {
    crop = false,
  },
}

local mark_dirty = function()
  frame_version = frame_version + 1
end

local escape_shell_arg = function(str)
  return str:gsub("'", "'\\''")
end

local add_to_cache = function(key, data)
  -- remove from current position if exists
  for i, k in ipairs(cache_order) do
    if k == key then
      table.remove(cache_order, i)
      break
    end
  end

  -- remove oldest if at capacity
  if #cache_order >= MAX_CACHE_SIZE then
    local oldest = table.remove(cache_order, 1)
    sixel_cache[oldest] = nil
    log.debug("Evicted cache entry: " .. oldest)
  end

  -- add entry
  sixel_cache[key] = data
  table.insert(cache_order, key)
end

local encode_to_sixel = function(image_path, width, height)
  -- validate image path
  if not image_path or image_path == "" then
    log.error("Invalid image path provided")
    return nil
  end
  if vim.fn.filereadable(image_path) == 0 then
    log.error("Image file not found: " .. image_path)
    return nil
  end

  -- check cache
  local cache_key = string.format("%s-%d-%d", image_path, width or 0, height or 0)
  if sixel_cache[cache_key] then
    log.debug("Using cached sixel data for: " .. cache_key)
    -- update order
    for i, k in ipairs(cache_order) do
      if k == cache_key then
        table.remove(cache_order, i)
        table.insert(cache_order, cache_key)
        break
      end
    end
    return sixel_cache[cache_key]
  end

  -- build encoding command (magick)
  local magick_cmd = nil
  if vim.fn.executable("magick") == 1 then
    magick_cmd = "magick"
  elseif vim.fn.executable("convert") == 1 then
    magick_cmd = "convert"
  else
    log.error("ImageMagick not found (need 'magick' or 'convert' command)")
    return nil
  end
  local escaped_path = escape_shell_arg(image_path)
  local cmd = nil
  if width and height then
    cmd = string.format("%s '%s' -resize %dx%d sixel:-", magick_cmd, escaped_path, width, height)
  else
    cmd = string.format("%s '%s' sixel:-", magick_cmd, escaped_path)
  end

  log.debug("Encoding with ImageMagick: " .. cmd)

  -- encode
  local sixel_data = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    log.error("Failed to encode image to sixel: " .. vim.v.shell_error)
    return nil
  end

  -- check sizxel data
  if not sixel_data or sixel_data == "" then
    log.error("Empty sixel data received from ImageMagick")
    return nil
  end

  -- add to cache
  add_to_cache(cache_key, sixel_data)
  log.debug("Cached sixel data for: " .. cache_key)

  return sixel_data
end

local send_sixel = function(sixel_data, x, y)
  if not sixel_data then return false end

  -- check/wrap ESC P and ST
  local has_dcs_start = sixel_data:match("^\27P") or sixel_data:match("^\155")
  local has_st_end = sixel_data:match("\27\\$") or sixel_data:match("\156$")

  local wrapped_data = sixel_data
  if not has_dcs_start then wrapped_data = "\27P0;1;0q" .. wrapped_data end
  if not has_st_end then wrapped_data = wrapped_data .. "\27\\" end

  -- build sequence
  local sequence = ""

  -- save cursor and move
  sequence = sequence .. "\27[s" -- Save cursor
  sequence = sequence .. string.format("\27[%d;%dH", y + 1, x + 1) -- Move to position

  -- sixel data
  sequence = sequence .. wrapped_data

  -- restore cursor
  sequence = sequence .. "\27[u" -- Restore cursor

  -- send via stderr
  vim.fn.chansend(vim.v.stderr, sequence)
  vim.fn.chansend(vim.v.stderr, "")

  log.debug(string.format("Sent sixel to position (%d, %d)", x, y))
  return true
end

local paint_frame = function()
  -- checks
  if not backend.state or not backend.state.images then
    log.error("Backend state not initialized")
    return
  end
  local term_size = utils.term.get_size()
  if not term_size or not term_size.cell_width or not term_size.cell_height then
    log.error("Invalid terminal size")
    return
  end

  -- sort images by position
  local ordered = {}
  for _, entry in pairs(frame_desired) do
    table.insert(ordered, entry)
  end
  table.sort(ordered, function(a, b)
    if a.y == b.y then return a.x < b.x end
    return a.y < b.y
  end)

  -- render images
  for _, entry in ipairs(ordered) do
    local image, x, y, w, h = entry.image, entry.x, entry.y, entry.w, entry.h
    -- check image
    if not image or not image.cropped_path then
      log.error("Invalid image data for rendering")
      goto continue
    end

    -- calculate pixel dimensions from cell dimensions
    local pixel_width = w * term_size.cell_width
    local pixel_height = h * term_size.cell_height

    -- encode and send image
    local sixel_data = encode_to_sixel(image.cropped_path, pixel_width, pixel_height)
    if sixel_data then
      send_sixel(sixel_data, x, y)
      image.is_rendered = true
      backend.state.images[image.id] = image
      log.debug(string.format("frame: rendered %s at (%d,%d) %dx%d", image.id, x, y, w, h))
    else
      log.error("frame: failed to encode " .. tostring(image.cropped_path))
    end

    ::continue::
  end
end

---@type fun()
local schedule_flush

local execute_flush = function()
  local this_version = frame_version
  flush_timer = nil
  flush_in_progress = true
  if backend and backend.state then backend.state.disable_decorator_handling = true end

  log.debug("flush clear")
  pcall(vim.cmd, [[noautocmd mode]])

  vim.schedule(function()
    vim.api.nvim_input("<Ignore>")
    vim.schedule(function()
      paint_frame()

      if backend and backend.state then backend.state.disable_decorator_handling = false end
      last_painted_version = this_version
      flush_in_progress = false

      -- schedule next flush if there were updates while painting
      if frame_version ~= last_painted_version then schedule_flush() end
    end)
  end)
end

schedule_flush = function()
  if flush_in_progress then
    log.debug("Flush already in progress, skipping schedule")
    return
  end

  -- cancel pending flush
  if flush_timer then
    flush_timer:stop()
    flush_timer = nil
  end

  -- schedule new flush
  flush_timer = vim.defer_fn(function()
    execute_flush()
  end, FLUSH_DELAY_MS)
end

function backend.setup(state)
  backend.state = state

  -- check magick
  if vim.fn.executable("magick") == 0 and vim.fn.executable("convert") == 0 then
    utils.throw("ImageMagick not found. Please install ImageMagick with sixel support.")
    return
  end

  -- tmux check
  if utils.tmux.is_tmux and not utils.tmux.has_passthrough then
    log.warn("tmux detected but passthrough may not be enabled for sixel")
  end

  log.info("Sixel backend initialized")
end

function backend.render(image, x, y, width, height)
  if not image or not image.id then
    log.error("Invalid image provided to render")
    return
  end

  local prev = frame_desired[image.id]

  -- update if position or dimensions changed
  if not prev or prev.x ~= x or prev.y ~= y or prev.w ~= width or prev.h ~= height or prev.image ~= image then
    frame_desired[image.id] = { image = image, x = x, y = y, w = width, h = height }
    mark_dirty()
  end

  schedule_flush()
end

function backend.clear(image_id, shallow)
  if not backend.state or not backend.state.images then return end

  -- clear specific image
  if image_id then
    local image = backend.state.images[image_id]
    if not image then return end

    if frame_desired[image_id] ~= nil then
      frame_desired[image_id] = nil
      mark_dirty()
    end

    if not shallow then
      backend.state.images[image_id] = nil
      schedule_flush()
    end

    image.is_rendered = false
    return
  end

  -- clear all images
  for _, image in pairs(backend.state.images) do
    image.is_rendered = false
  end

  frame_desired = {}
  mark_dirty()
  log.debug("Queued clear-all scene")
  schedule_flush()
end

return backend
