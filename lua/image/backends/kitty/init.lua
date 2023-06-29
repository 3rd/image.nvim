local utils = require("image/utils")
local codes = require("image/backends/kitty/codes")
local helpers = require("image/backends/kitty/helpers")

local is_tmux = vim.env.TMUX ~= nil
local tmux_has_passthrough = false

if is_tmux then
  local ok, result = pcall(vim.fn.system, "tmux show -Apv allow-passthrough")
  if ok and result == "on\n" then tmux_has_passthrough = true end
end

---@type Backend
local backend = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  state = nil,
}

-- TODO: check for kitty
backend.setup = function(state)
  backend.state = state
  if is_tmux and not tmux_has_passthrough then
    utils.throw("tmux does not have allow-passthrough enabled")
    return
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    pattern = "*",
    callback = function()
      backend.clear()
    end,
  })
end

-- extend from empty line strategy to use extmarks
backend.render = function(image, x, y, width, height)
  local term_size = utils.term.get_size()
  local with_virtual_placeholders = backend.state.options.kitty_method == "unicode-placeholders"

  -- save cursor
  helpers.move_cursor(x + 1, y + 1, true)

  -- clear out of bounds images
  if
    y + height < image.bounds.top
    or y > image.bounds.bottom
    or x + width < image.bounds.left
    or x > image.bounds.right
  then
    -- utils.debug( "deleting out of bounds image", { id = image.id, x = x, y = y, width = width, height = height, bounds = image.bounds })
    helpers.write_graphics({
      action = codes.control.action.delete,
      display_delete = "i",
      image_id = image.internal_id,
      quiet = 2,
    })
    image.is_rendered = false
    backend.state.images[image.id] = image
    helpers.restore_cursor()
    return
  end
  -- utils.debug("kitty: rendering image" .. image.path, { id = image.id, x = x, y = y, width = width, height = height, bounds = image.bounds })

  -- transmit image
  helpers.write_graphics({
    action = codes.control.action.transmit,
    image_id = image.internal_id,
    transmit_format = codes.control.transmit_format.png,
    transmit_medium = codes.control.transmit_medium.file,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
    display_virtual_placeholder = with_virtual_placeholders and 1 or 0,
    quiet = 2,
  }, image.path)

  -- unicode placeholders
  if with_virtual_placeholders then
    helpers.move_cursor(x + 1, y + 1, false, backend.state.options.kitty_tmux_write_delay)
    helpers.write_graphics({
      action = codes.control.action.display,
      quiet = 2,
      image_id = image.internal_id,
      display_rows = height,
      display_columns = width,
      display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
      display_virtual_placeholder = 1,
    })
    helpers.write_placeholder(image.internal_id, x, y, width, height)

    backend.state.images[image.id] = image
    helpers.restore_cursor()
    return
  end

  -- default display
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  local pixel_top = 0

  -- top crop
  if y < image.bounds.top then
    local visible_rows = height - (image.bounds.top - y)
    pixel_height = visible_rows * term_size.cell_height
    pixel_top = (image.bounds.top - y) * term_size.cell_height
    y = image.bounds.top
  end

  -- bottom crop
  if y + height > image.bounds.bottom then
    --
    pixel_height = (image.bounds.bottom - y + 1) * term_size.cell_height
  end

  helpers.move_cursor(x + 1, y + 1, false, backend.state.options.kitty_tmux_write_delay)
  helpers.write_graphics({
    action = codes.control.action.display,
    quiet = 2,
    image_id = image.internal_id,
    display_width = pixel_width,
    display_height = pixel_height,
    display_y = pixel_top,
    display_zindex = -1,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
  })
  backend.state.images[image.id] = image
  helpers.restore_cursor()
end

backend.clear = function(image_id, shallow)
  if image_id then
    local image = backend.state.images[image_id]
    if not image then return end
    helpers.write_graphics({
      action = codes.control.action.delete,
      display_delete = "i",
      image_id = image.internal_id,
      quiet = 2,
    })
    image.is_rendered = false
    if not shallow then backend.state.images[image_id] = nil end
    return
  end
  helpers.write_graphics({
    action = codes.control.action.delete,
    display_delete = "a",
    quiet = 2,
  })
  for id, image in pairs(backend.state.images) do
    image.is_rendered = false
    if not shallow then backend.state.images[id] = nil end
  end
end

return backend
