local notify = vim.notify
vim.notify = function() end

local renderer = require("image/renderer")
local utils = require("image/utils")

vim.notify = notify

describe("renderer from another window", function()
  local image_buffer
  local image_window
  local other_buffer
  local other_window
  local originals
  local state

  local make_image = function(y)
    local image = {
      id = "visual-mode",
      path = "test.png",
      source_format = "png",
      image_width = 1,
      image_height = 1,
      window = image_window,
      buffer = image_buffer,
      global_state = state,
      geometry = { x = 0, y = y, width = 1, height = 1 },
      is_rendered = false,
      clear = function() end,
    }
    state.images[image.id] = image
    return image
  end

  before_each(function()
    image_window = vim.api.nvim_get_current_win()
    image_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(image_window, image_buffer)
    vim.api.nvim_buf_set_lines(image_buffer, 0, -1, false, { "one", "two", "three", "four" })

    vim.cmd("vsplit")
    other_window = vim.api.nvim_get_current_win()
    other_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(other_window, other_buffer)
    vim.api.nvim_buf_set_lines(other_buffer, 0, -1, false, { "foo bar" })

    originals = {
      get_size = utils.term.get_size,
      get_window = utils.window.get_window,
      get_global_offsets = utils.offsets.get_global_offsets,
    }
    utils.term.get_size = function()
      return { cell_width = 1, cell_height = 1, screen_cols = vim.o.columns, screen_rows = vim.o.lines }
    end
    utils.window.get_window = function(id)
      local position = vim.api.nvim_win_get_position(id)
      return {
        id = id,
        buffer = vim.api.nvim_win_get_buf(id),
        is_visible = true,
        is_floating = false,
        rect = {
          top = position[1],
          right = position[2] + vim.api.nvim_win_get_width(id),
          bottom = position[1] + vim.api.nvim_win_get_height(id),
          left = position[2],
        },
      }
    end
    utils.offsets.get_global_offsets = function()
      return { x = 0, y = 0 }
    end

    state = {
      options = { scale_factor = 1, window_overlap_clear_enabled = false },
      images = {},
      backend = {
        features = { crop = true },
        render = function() end,
        clear = function() end,
      },
    }
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    utils.window.get_window = originals.get_window
    utils.offsets.get_global_offsets = originals.get_global_offsets

    vim.cmd("normal! \27")
    if vim.api.nvim_win_is_valid(other_window) then vim.api.nvim_win_close(other_window, true) end
    vim.api.nvim_buf_delete(other_buffer, { force = true })
    vim.api.nvim_buf_delete(image_buffer, { force = true })
  end)

  it("keeps Visual mode in the current window", function()
    vim.api.nvim_feedkeys("v", "nx", false)
    assert.are.same("v", vim.fn.mode())

    assert.is_true(renderer.render(make_image(0)))

    assert.are.same("v", vim.fn.mode())
    assert.are.same(other_window, vim.api.nvim_get_current_win())
  end)

  it("still detects folds in the image window", function()
    vim.api.nvim_win_call(image_window, function()
      vim.wo.foldmethod = "manual"
      vim.cmd("2,3fold")
    end)

    assert.is_false(renderer.render(make_image(1)))
    assert.are.same(other_window, vim.api.nvim_get_current_win())
  end)
end)
