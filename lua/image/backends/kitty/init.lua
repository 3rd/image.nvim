local codes = require("image/backends/kitty/codes")
local helpers = require("image/backends/kitty/helpers")
local utils = require("image/utils")
local log = require("image/utils/logger").within("backend.kitty")

local editor_tty = utils.term.get_tty()
local is_SSH = (vim.env.SSH_CLIENT ~= nil) or (vim.env.SSH_TTY ~= nil)

---@type Backend
---@diagnostic disable-next-line: missing-fields
local backend = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  state = nil,
  features = {
    crop = true,
  },
}

-- index transmitted images, clear index on resize
local transmitted_images = {}
vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    transmitted_images = {}
  end,
})

backend.setup = function(state)
  backend.state = state
  if utils.tmux.is_tmux and not utils.tmux.has_passthrough then
    utils.throw("tmux does not have allow-passthrough enabled")
    return
  end

  if state.options.kitty_method == "unicode-placeholders" then backend.features.crop = false end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      backend.clear()
    end,
  })
end

backend.render = function(image, x, y, width, height)
  local with_virtual_placeholders = backend.state.options.kitty_method == "unicode-placeholders"

  local transmit_medium = codes.control.transmit_medium.file

  if is_SSH then transmit_medium = codes.control.transmit_medium.direct end

  -- transmit image
  local transmit = function()
    local transmit_payload = {
      action = codes.control.action.transmit,
      image_id = image.internal_id,
      transmit_format = codes.control.transmit_format.png,
      transmit_medium = transmit_medium,
      display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
      quiet = 2,
    }
    if with_virtual_placeholders then transmit_payload.display_virtual_placeholder = 1 end
    helpers.write_graphics(transmit_payload, image.cropped_path)
    log.debug("transmitted image " .. image.id .. " (" .. image.internal_id .. ")")
  end
  if backend.features.crop then
    local preprocessing_hash = ("%s-%s"):format(image.id, image.resize_hash)
    if transmitted_images[image.id] ~= preprocessing_hash then
      transmit()
      transmitted_images[image.id] = preprocessing_hash
    end
  else
    local preprocessing_hash = ("%s-%s-%s"):format(image.id, image.resize_hash, image.crop_hash)
    if transmitted_images[image.id] ~= preprocessing_hash then
      transmit()
      transmitted_images[image.id] = preprocessing_hash
    end
  end

  -- unicode placeholders
  if with_virtual_placeholders then
    if backend.state.images[image.id] and backend.state.images[image.id] ~= image then
      backend.state.images[image.id]:clear(true)
    end

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

  local display_payload = {
    action = codes.control.action.display,
    quiet = 2,
    image_id = image.internal_id,
    display_zindex = -1,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
    placement_id = image.internal_id,
  }

  -- crop
  if backend.features.crop then
    local term_size = utils.term.get_size()
    local pixel_width = width * term_size.cell_width
    local pixel_height = height * term_size.cell_height
    local pixel_top = 0
    local pixel_left = 0

    -- crop top
    if y < image.bounds.top then
      local visible_rows = height - (image.bounds.top - y)
      pixel_height = visible_rows * term_size.cell_height
      pixel_top = (image.bounds.top - y) * term_size.cell_height
      y = image.bounds.top
    end

    -- crop bottom
    if y + height > image.bounds.bottom then pixel_height = (image.bounds.bottom - y + 1) * term_size.cell_height end

    -- crop right
    if x + width > image.bounds.right then pixel_width = (image.bounds.right - x) * term_size.cell_width end

    -- crop left
    if x < image.bounds.left then
      local visible_columns = width - (image.bounds.left - x)
      pixel_width = visible_columns * term_size.cell_width
      pixel_left = (image.bounds.left - x) * term_size.cell_width
      x = image.bounds.left
    end

    display_payload.display_width = pixel_width
    display_payload.display_height = pixel_height
    display_payload.display_y = pixel_top
    display_payload.display_x = pixel_left
  end

  if backend.state.images[image.id] and backend.state.images[image.id] ~= image then
    backend.state.images[image.id]:clear(true)
  end

  helpers.update_sync_start()
  helpers.move_cursor(x + 1, y + 1, true)
  helpers.write_graphics(display_payload)
  helpers.restore_cursor()
  helpers.update_sync_end()

  backend.state.images[image.id] = image
  image.is_rendered = true

  log.debug("path:", { path = image.cropped_path, payload = display_payload })
end

local get_clear_tty_override = function()
  if not utils.tmux.is_tmux then return nil end
  local current_tmux_tty = utils.tmux.get_pane_tty()
  if current_tmux_tty == editor_tty then return nil end
  return current_tmux_tty
end

backend.clear = function(image_id, shallow)
  -- one
  if image_id then
    local image = backend.state.images[image_id]
    if not image then return end

    if image.is_rendered then
      local tty = get_clear_tty_override()
      helpers.write_graphics({
        action = codes.control.action.delete,
        display_delete = "i",
        image_id = image.internal_id,
        quiet = 2,
        tty = tty,
      })
    end

    image.is_rendered = false
    if not shallow then
      backend.state.images[image_id] = nil
      transmitted_images[image.id] = nil
    end
    log.debug("cleared image", { id = image.id, internal_id = image.internal_id, shallow = shallow })
    return
  end

  --all
  helpers.write_graphics({
    action = codes.control.action.delete,
    display_delete = "a",
    quiet = 2,
    tty = get_clear_tty_override(),
  })

  log.debug("cleared all")
  for id, image in pairs(backend.state.images) do
    image.is_rendered = false
    if not shallow then
      backend.state.images[id] = nil
      transmitted_images[image.id] = nil
    end
    log.debug("cleared image (all)", { id = image.id, shallow = shallow })
  end
end

return backend
