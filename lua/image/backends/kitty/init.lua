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

local transmitted_images = {}
backend.render = function(image, x, y, width, height)
  local with_virtual_placeholders = backend.state.options.kitty_method == "unicode-placeholders"

  -- save cursor
  helpers.move_cursor(x + 1, y + 1, true)

  -- transmit image
  if transmitted_images[image.id] ~= image.crop_hash then
    helpers.write_graphics({
      action = codes.control.action.transmit,
      image_id = image.internal_id,
      transmit_format = codes.control.transmit_format.png,
      transmit_medium = codes.control.transmit_medium.file,
      display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
      display_virtual_placeholder = with_virtual_placeholders and 1 or 0,
      quiet = 2,
    }, image.path)
    transmitted_images[image.id] = true
  end

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
      placement_id = image.internal_id,
    })
    helpers.write_placeholder(image.internal_id, x, y, width, height)

    image.is_rendered = true
    backend.state.images[image.id] = image
    helpers.restore_cursor()
    return
  end

  helpers.move_cursor(x + 1, y + 1, false, backend.state.options.kitty_tmux_write_delay)
  helpers.write_graphics({
    action = codes.control.action.display,
    quiet = 2,
    image_id = image.internal_id,
    display_zindex = -1,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
    placement_id = image.internal_id,
  })
  image.is_rendered = true
  backend.state.images[image.id] = image
  helpers.restore_cursor()
end

backend.clear = function(image_id, shallow)
  helpers.move_cursor(0, 0, true)

  -- one
  if image_id then
    local image = backend.state.images[image_id]
    if not image then return end
    helpers.write_graphics({
      action = codes.control.action.delete,
      display_delete = shallow and "i" or "I",
      image_id = image.internal_id,
      quiet = 2,
    })
    image.is_rendered = false
    if not shallow then backend.state.images[image_id] = nil end
    helpers.restore_cursor()
    return
  end

  --all
  helpers.write_graphics({
    action = codes.control.action.delete,
    display_delete = "a",
    quiet = 2,
  })
  for id, image in pairs(backend.state.images) do
    image.is_rendered = false
    if not shallow then backend.state.images[id] = nil end
  end
  helpers.restore_cursor()
end

return backend
