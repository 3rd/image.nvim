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
end

-- extend from empty line strategy to use extmarks
backend.render = function(image, x, y, width, height)
  -- transmit image
  helpers.move_cursor(x, y, true)
  helpers.write_graphics({
    action = codes.control.action.transmit,
    image_id = image.internal_id,
    transmit_format = codes.control.transmit_format.png,
    transmit_medium = codes.control.transmit_medium.file,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
    display_virtual_placeholder = is_tmux and 1 or 0,
    quiet = 2,
  }, image.path)

  -- unicode placeholders
  if is_tmux then
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
  local term_size = utils.term.get_size()
  local pixel_width = math.ceil(width * term_size.cell_width)
  local pixel_height = math.ceil(height * term_size.cell_height)

  helpers.move_cursor(x + 1, y + 1)
  helpers.write_graphics({
    action = codes.control.action.display,
    quiet = 2,
    image_id = image.internal_id,
    placement_id = 1,
    display_width = pixel_width,
    display_height = pixel_height,
    display_zindex = -1,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
  })
  backend.state.images[image.id] = image
  helpers.restore_cursor()
end

backend.clear = function(image_id)
  if image_id then
    local image = backend.state.images[image_id]
    if not image then return end
    helpers.write_graphics({
      action = codes.control.action.delete,
      display_delete = "i",
      image_id = image.internal_id,
      quiet = 2,
    })
    backend.state.images[image_id] = nil
    return
  end
  helpers.write_graphics({
    action = codes.control.action.delete,
    display_delete = "a",
    quiet = 2,
  })
  for id, _ in pairs(backend.state.images) do
    backend.state.images[id] = nil
  end
end

return backend
