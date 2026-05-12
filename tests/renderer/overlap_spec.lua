local notify = vim.notify
vim.notify = function() end

local renderer = require("image/renderer")
local utils = require("image/utils")

vim.notify = notify

describe("renderer overlap handling", function()
  local originals

  local make_image = function(opts)
    local calls = {}
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

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
        render = function(_, x, y, width, height)
          calls[#calls + 1] = {
            x = x,
            y = y,
            width = width,
            height = height,
          }
        end,
      },
      processor = {},
      tmp_dir = "/tmp",
    }

    local image = {
      id = opts.id or "test-image",
      path = "test.png",
      original_path = "test.png",
      image_width = 5,
      image_height = 5,
      window = window,
      buffer = buffer,
      global_state = state,
      geometry = {
        x = 2,
        y = 4,
        width = 5,
        height = 5,
      },
      rendered_geometry = {},
      render_offset_top = opts.render_offset_top,
      overlap = opts.overlap,
      is_rendered = false,
    }

    state.images[image.id] = image
    return image, calls
  end

  local setup_window_mocks = function(opts)
    local screenpos_calls = 0
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    utils.term.get_size = function()
      return {
        cell_width = 1,
        cell_height = 1,
        screen_cols = 80,
        screen_rows = 40,
      }
    end

    utils.window.get_window = function()
      return {
        id = window,
        buffer = buffer,
        is_visible = true,
        is_floating = false,
        masks = {},
        width = 80,
        height = 40,
        rect = {
          top = 0,
          right = 80,
          bottom = 40,
          left = 0,
        },
      }
    end

    vim.fn.getwininfo = function()
      return {
        {
          botline = 20,
          topline = opts.topline,
          wincol = 1,
          winrow = 10,
          textoff = 3,
        },
      }
    end

    vim.fn.screenpos = function(_, line)
      screenpos_calls = screenpos_calls + 1
      if line == opts.topline then return { row = opts.topline_screen_row or 10, col = 1 } end
      return { row = 0, col = 0 }
    end

    return function()
      return screenpos_calls
    end
  end

  before_each(function()
    originals = {
      get_size = utils.term.get_size,
      get_window = utils.window.get_window,
      getwininfo = vim.fn.getwininfo,
      screenpos = vim.fn.screenpos,
    }
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    utils.window.get_window = originals.get_window
    vim.fn.getwininfo = originals.getwininfo
    vim.fn.screenpos = originals.screenpos
    renderer.clear_cache_for_path("test.png")
  end)

  it("keeps omitted overlap on the existing virtual-line fallback path", function()
    local get_screenpos_calls = setup_window_mocks({
      topline = 6,
      topline_screen_row = 10,
    })
    local image, calls = make_image({
      render_offset_top = 2,
    })

    assert.is_false(renderer.render(image))
    assert.are.same(0, #calls)
    assert.are.same(2, get_screenpos_calls())
  end)

  it("renders explicit overlap without applying render_offset_top twice", function()
    local get_screenpos_calls = setup_window_mocks({
      topline = 6,
    })
    local image, calls = make_image({
      render_offset_top = 2,
      overlap = 5,
    })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    assert.are.same(5, calls[1].x)
    assert.are.same(11, calls[1].y)
    assert.are.same(1, get_screenpos_calls())
  end)
end)
