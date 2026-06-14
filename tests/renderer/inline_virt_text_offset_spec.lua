local notify = vim.notify
vim.notify = function() end

local renderer = require("image/renderer")
local utils = require("image/utils")

vim.notify = notify

describe("renderer inline virtual text offset", function()
  local originals
  local ns

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
          calls[#calls + 1] = { x = x, y = y, width = width, height = height }
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
      geometry = { x = opts.x or 0, y = opts.y or 4, width = 5, height = 5 },
      rendered_geometry = {},
      render_offset_top = 0,
      is_rendered = false,
    }

    state.images[image.id] = image
    return image, calls
  end

  local setup_window_mocks = function()
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    utils.term.get_size = function()
      return { cell_width = 1, cell_height = 1, screen_cols = 80, screen_rows = 40 }
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
        rect = { top = 0, right = 80, bottom = 40, left = 0 },
      }
    end

    vim.fn.getwininfo = function()
      return { { botline = 20, topline = 1, wincol = 1, winrow = 1, textoff = 0 } }
    end

    -- normal in-viewport case: screenpos returns a valid position
    vim.fn.screenpos = function(_, line, col)
      return { row = line, col = col }
    end
  end

  before_each(function()
    originals = {
      get_size = utils.term.get_size,
      get_window = utils.window.get_window,
      getwininfo = vim.fn.getwininfo,
      screenpos = vim.fn.screenpos,
    }
    ns = vim.api.nvim_create_namespace("test_inline_virt_text")
    -- ensure buffer has enough lines for our extmark rows
    local buf = vim.api.nvim_get_current_buf()
    local lines = {}
    for _ = 1, 20 do
      lines[#lines + 1] = ""
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    utils.window.get_window = originals.get_window
    vim.fn.getwininfo = originals.getwininfo
    vim.fn.screenpos = originals.screenpos
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    renderer.clear_cache_for_path("test.png")
  end)

  it("does not shift non-indented image when no inline virt_text is present", function()
    setup_window_mocks()
    local image, calls = make_image({ x = 0, y = 4 })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    -- screenpos returns col=1 for col input=1 (x=0 + 1), absolute_x = col - 1 = 0
    assert.are.same(0, calls[1].x)
  end)

  it("shifts non-indented image right by inline virt_text width at its row", function()
    setup_window_mocks()
    local buf = vim.api.nvim_get_current_buf()
    -- inject 4-cell inline virt_text at row 4, col 0 (matches render-markdown indent)
    vim.api.nvim_buf_set_extmark(buf, ns, 4, 0, {
      virt_text = { { "    ", "Normal" } },
      virt_text_pos = "inline",
    })
    local image, calls = make_image({ x = 0, y = 4 })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    assert.are.same(4, calls[1].x)
  end)

  it("does not shift indented image (x>0) even when virt_text is present", function()
    setup_window_mocks()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_extmark(buf, ns, 4, 0, {
      virt_text = { { "    ", "Normal" } },
      virt_text_pos = "inline",
    })
    local image, calls = make_image({ x = 3, y = 4 })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    -- screenpos returns col = x+1 = 4, absolute_x = 4 - 1 = 3, no virt_text shift
    assert.are.same(3, calls[1].x)
  end)

  it("ignores non-inline virt_text (e.g. eol) at the image row", function()
    setup_window_mocks()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_extmark(buf, ns, 4, 0, {
      virt_text = { { "    ", "Normal" } },
      virt_text_pos = "eol",
    })
    local image, calls = make_image({ x = 0, y = 4 })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    assert.are.same(0, calls[1].x)
  end)

  it("sums multiple inline virt_text chunks at the image row", function()
    setup_window_mocks()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_extmark(buf, ns, 4, 0, {
      virt_text = {
        { "  ", "Normal" },
        { "▎ ", "Normal" },
      },
      virt_text_pos = "inline",
    })
    local image, calls = make_image({ x = 0, y = 4 })

    assert.is_true(renderer.render(image))
    assert.are.same(1, #calls)
    -- "  " is 2 cells, "▎ " is 2 cells → total 4
    assert.are.same(4, calls[1].x)
  end)
end)
