local notify = vim.notify
vim.notify = function() end

local renderer = require("image/renderer")
local utils = require("image/utils")

vim.notify = notify

-- An image near the bottom of a normal window is cropped to the rows left in
-- the window, whatever 'laststatus' is: the window's last row shows an image,
-- and one that starts below the window is not drawn over the statusline.
describe("renderer bottom bounds", function()
  local originals
  local window
  local buffer

  -- the rows the backend is asked to show, worked out as the kitty backend does
  local make_image = function(y)
    local calls = {}
    local state = {
      options = {
        scale_factor = 1,
        window_overlap_clear_enabled = false,
        window_overlap_clear_ft_ignore = {},
      },
      images = {},
      backend = {
        features = { crop = true },
        clear = function() end,
        render = function(image, _, render_y, _, height)
          local rows = height
          if render_y + height > image.bounds.bottom then rows = image.bounds.bottom - render_y + 1 end
          calls[#calls + 1] = { y = render_y, rows = rows }
        end,
      },
      processor = {},
      tmp_dir = "/tmp",
    }

    local image = {
      id = "bottom-bounds-" .. y,
      path = "test.png",
      original_path = "test.png",
      image_width = 6,
      image_height = 3,
      window = window,
      buffer = buffer,
      global_state = state,
      geometry = { x = 0, y = y, width = 6, height = 3 },
      rendered_geometry = {},
      render_offset_top = 0,
      is_rendered = false,
    }

    state.images[image.id] = image
    return image, calls
  end

  before_each(function()
    originals = {
      get_size = utils.term.get_size,
      laststatus = vim.o.laststatus,
    }
    utils.term.get_size = function()
      return { cell_width = 1, cell_height = 1, screen_cols = vim.o.columns, screen_rows = vim.o.lines }
    end

    vim.cmd("silent! only")
    window = vim.api.nvim_get_current_win()
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(window, buffer)
    local lines = {}
    for i = 1, 400 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    vim.o.laststatus = originals.laststatus
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
    renderer.clear_cache_for_path("test.png")
  end)

  for _, laststatus in ipairs({ 0, 2, 3 }) do
    it(("crops a 3-row image to the window's last rows with laststatus=%d"):format(laststatus), function()
      vim.o.laststatus = laststatus
      local height = vim.api.nvim_win_get_height(window)
      local topline = 100

      -- window row `row` (1-based) starts an image anchored on the line above it
      for _, row in ipairs({ height - 2, height - 1, height }) do
        vim.fn.winrestview({ topline = topline })
        local image, calls = make_image(topline + row - 3)

        assert.is_true(renderer.render(image), "row " .. row)
        assert.are.same(1, #calls, "row " .. row)
        assert.are.same(height - row + 1, calls[1].rows, "row " .. row)
      end
    end)

    it(("does not draw an image that starts below the window with laststatus=%d"):format(laststatus), function()
      vim.o.laststatus = laststatus
      local height = vim.api.nvim_win_get_height(window)
      local topline = 100

      vim.fn.winrestview({ topline = topline })
      local image, calls = make_image(topline + height - 2)

      assert.is_false(renderer.render(image))
      assert.are.same(0, #calls)
    end)
  end
end)
