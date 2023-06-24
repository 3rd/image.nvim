local utils = require("image/utils")
local codes = require("image/backends/kitty/codes")
local helpers = require("image/backends/kitty/helpers")

local term_size = helpers.get_term_size()

---@type Backend
local backend = {}

backend.setup = function()
  vim.defer_fn(function()
    -- log(get_term_size())
  end, 1000)
end

local images = {}
local last_kitty_id = 0

-- extend from empty line strategy to use extmarks
backend.render = function(image_id, url, x, y, max_cols, max_rows)
  if not images[image_id] then
    last_kitty_id = last_kitty_id + 1
    images[image_id] = last_kitty_id
  end
  local kitty_id = images[image_id]

  helpers.write_graphics({
    action = codes.control.action.transmit,
    transmit_format = codes.control.transmit_format.png,
    transmit_medium = codes.control.transmit_medium.file,
    quiet = 2,
    image_id = kitty_id,
    placement_id = 1,
  }, url)

  helpers.move_cursor(x + 1, y + 1)

  local rows = max_rows
  local image_width, image_height = utils.png.get_dimensions(url)
  local pixel_height = math.floor(max_rows * term_size.cell_height)
  local pixel_width = math.floor(image_width * pixel_height / image_height)
  local columns = math.floor(pixel_width / term_size.cell_width)

  log({ image_width, image_height, rows, columns })

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
