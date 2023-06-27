local utils = require("image/utils")
local codes = require("image/backends/kitty/codes")
local helpers = require("image/backends/kitty/helpers")

local term_size = helpers.get_term_size()

local images = {}
local last_kitty_id = 0

local is_tmux = vim.env.TMUX ~= nil
local tmux_has_passthrough = false

if is_tmux then
  local ok, result = pcall(vim.fn.system, "tmux show -Apv allow-passthrough")
  if ok and result == "on\n" then tmux_has_passthrough = true end
end

---@type Backend
local backend = {}

-- TODO: check for kitty
backend.setup = function(options)
  backend.options = options

  if is_tmux and not tmux_has_passthrough then
    utils.throw("tmux does not have allow-passthrough enabled")
    return
  end

  vim.defer_fn(function()
    -- log(get_term_size())
  end, 1000)
end

-- extend from empty line strategy to use extmarks
backend.render = function(image_id, url, x, y, max_cols, max_rows)
  if not images[image_id] then
    last_kitty_id = last_kitty_id + 1
    images[image_id] = last_kitty_id
  end
  local kitty_id = images[image_id]

  local image_width, image_height = utils.png.get_dimensions(url)
  local rows = math.floor(image_height / term_size.cell_height)
  local columns = math.floor(image_width / term_size.cell_width)
  -- local rows = max_rows
  -- local pixel_height = math.floor(max_rows * term_size.cell_height)
  -- local pixel_width = math.floor(image_width * pixel_height / image_height)
  -- local columns = math.floor(pixel_width / term_size.cell_width)
  -- log({
  --   image_width = image_width,
  --   image_height = image_height,
  --   columns = columns,
  --   rows = rows,
  -- })

  -- if true then
  --   helpers.move_cursor(10, 10)
  --   return
  -- end

  helpers.move_cursor(x, y, true)

  -- transmit image
  helpers.write_graphics({
    action = codes.control.action.transmit,
    image_id = kitty_id,
    transmit_format = codes.control.transmit_format.png,
    transmit_medium = codes.control.transmit_medium.file,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
    display_virtual_placeholder = is_tmux and 1 or 0,
    quiet = 2,
  }, url)

  -- unicode placeholders
  if is_tmux then
    -- create virtual image placement
    helpers.write_graphics({
      action = codes.control.action.display,
      quiet = 2,
      image_id = kitty_id,
      display_rows = rows,
      display_columns = columns,
      display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
      display_virtual_placeholder = 1,
    })

    -- write placeholder
    helpers.write_placeholder(kitty_id, x, y, rows, columns)
    helpers.restore_cursor()
    return
  end

  -- default display
  helpers.move_cursor(x + 1, y + 1)
  helpers.write_graphics({
    action = codes.control.action.display,
    quiet = 2,
    image_id = kitty_id,
    placement_id = 1,
    display_rows = rows,
    display_columns = columns,
    display_zindex = -1,
    display_cursor_policy = codes.control.display_cursor_policy.do_not_move,
  })
  helpers.restore_cursor()
end

backend.clear = function(image_id)
  if image_id then
    helpers.write_graphics({
      action = codes.control.action.delete,
      display_delete = "i",
      image_id = 1,
      quiet = 2,
    })
  end
  helpers.write_graphics({
    action = codes.control.action.delete,
    display_delete = "a",
    quiet = 2,
  })
end

return backend
