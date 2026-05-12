local unload_image_modules = function()
  for module_name in pairs(package.loaded) do
    if module_name == "image" or module_name:match("^image/") then package.loaded[module_name] = nil end
  end
end

local disabled_integrations = {
  markdown = { enabled = false },
  asciidoc = { enabled = false },
  typst = { enabled = false },
  neorg = { enabled = false },
  syslang = { enabled = false },
  html = { enabled = false },
  css = { enabled = false },
  org = { enabled = false },
}

describe("window buffer switching", function()
  local originals

  before_each(function()
    unload_image_modules()
    originals = {
      get_mode = vim.api.nvim_get_mode,
      win_is_valid = vim.api.nvim_win_is_valid,
      buf_is_valid = vim.api.nvim_buf_is_valid,
      get_windows = require("image/utils").window.get_windows,
      get_window = require("image/utils").window.get_window,
      win_get_height = vim.api.nvim_win_get_height,
      win_get_buf = vim.api.nvim_win_get_buf,
      set_decoration_provider = vim.api.nvim_set_decoration_provider,
      schedule = vim.schedule,
    }
  end)

  after_each(function()
    local utils = require("image/utils")
    vim.api.nvim_get_mode = originals.get_mode
    vim.api.nvim_win_is_valid = originals.win_is_valid
    vim.api.nvim_buf_is_valid = originals.buf_is_valid
    vim.api.nvim_win_get_height = originals.win_get_height
    vim.api.nvim_win_get_buf = originals.win_get_buf
    vim.api.nvim_set_decoration_provider = originals.set_decoration_provider
    vim.schedule = originals.schedule
    utils.window.get_windows = originals.get_windows
    utils.window.get_window = originals.get_window
    unload_image_modules()
  end)

  it("clears only stale images for the window that changed buffers", function()
    local utils = require("image/utils")
    local image = require("image")
    local provider
    local clear_calls = {}
    local render_calls = {}
    local current_buffer = 100

    vim.api.nvim_get_mode = function()
      return { mode = "n" }
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_height = function()
      return 20
    end
    vim.api.nvim_win_get_buf = function()
      return current_buffer
    end
    vim.schedule = function(callback)
      callback()
    end
    vim.api.nvim_set_decoration_provider = function(_, opts)
      provider = opts
    end
    utils.window.get_windows = function()
      return {}
    end
    utils.window.get_window = function()
      return {
        is_visible = true,
        is_floating = false,
        masks = {},
        rect = { top = 0, right = 80, bottom = 20, left = 0 },
      }
    end

    image.setup({
      integrations = disabled_integrations,
    })

    local old_window_image = {
      id = "old-window",
      window = 10,
      buffer = 100,
      namespace = "markdown",
      is_rendered = true,
      clear = function(_, shallow)
        clear_calls[#clear_calls + 1] = { id = "old-window", shallow = shallow }
      end,
      render = function() end,
    }
    local other_window_image = {
      id = "other-window",
      window = 20,
      buffer = 100,
      namespace = "markdown",
      is_rendered = true,
      clear = function(_, shallow)
        clear_calls[#clear_calls + 1] = { id = "other-window", shallow = shallow }
      end,
      render = function() end,
    }
    local current_window_image = {
      id = "current-window",
      window = 10,
      buffer = 200,
      namespace = "markdown",
      is_rendered = false,
      clear = function(_, shallow)
        clear_calls[#clear_calls + 1] = { id = "current-window", shallow = shallow }
      end,
      render = function()
        render_calls[#render_calls + 1] = { id = "current-window" }
      end,
    }

    image.get_images = function(opts)
      local images = { old_window_image, other_window_image, current_window_image }
      local matches = {}
      for _, current_image in ipairs(images) do
        if
          not opts
          or (
            (not opts.window or opts.window == current_image.window)
            and (not opts.buffer or opts.buffer == current_image.buffer)
            and (not opts.namespace or opts.namespace == current_image.namespace)
          )
        then
          matches[#matches + 1] = current_image
        end
      end
      return matches
    end

    provider.on_win(nil, 10, 100, 0, 10)
    provider.on_win(nil, 10, 100, 0, 10)
    current_buffer = 200
    provider.on_win(nil, 10, 200, 0, 10)
    provider.on_win(nil, 10, 200, 0, 10)

    assert.are.same(1, #clear_calls)
    assert.are.same("old-window", clear_calls[1].id)
    assert.is_true(clear_calls[1].shallow)
    assert.are.same(1, #render_calls)
    assert.are.same("current-window", render_calls[1].id)
  end)

  it("uses each window's current buffer for scheduled overlap handling", function()
    local utils = require("image/utils")
    local image = require("image")
    local provider
    local scheduled = {}
    local current_buffer = 100
    local render_calls = {}

    vim.api.nvim_get_mode = function()
      return { mode = "n" }
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_buf = function()
      return current_buffer
    end
    vim.schedule = function(callback)
      scheduled[#scheduled + 1] = callback
    end
    vim.api.nvim_set_decoration_provider = function(_, opts)
      provider = opts
    end
    utils.window.get_windows = function()
      return {
        {
          id = 10,
          buffer = current_buffer,
          masks = {},
        },
      }
    end
    utils.window.get_window = function()
      return {
        is_visible = true,
        is_floating = false,
        masks = {},
        rect = { top = 0, right = 80, bottom = 20, left = 0 },
      }
    end

    image.setup({
      window_overlap_clear_enabled = true,
      integrations = disabled_integrations,
    })

    local old_buffer_image = {
      id = "old-buffer",
      window = 10,
      buffer = 100,
      namespace = "markdown",
      is_rendered = false,
      clear = function() end,
      render = function()
        render_calls[#render_calls + 1] = { id = "old-buffer" }
      end,
    }
    local current_buffer_image = {
      id = "current-buffer",
      window = 10,
      buffer = 200,
      namespace = "markdown",
      is_rendered = false,
      clear = function() end,
      render = function()
        render_calls[#render_calls + 1] = { id = "current-buffer" }
      end,
    }

    image.get_images = function(opts)
      local images = { old_buffer_image, current_buffer_image }
      local matches = {}
      for _, current_image in ipairs(images) do
        if
          not opts
          or (
            (not opts.window or opts.window == current_image.window)
            and (not opts.buffer or opts.buffer == current_image.buffer)
            and (not opts.namespace or opts.namespace == current_image.namespace)
          )
        then
          matches[#matches + 1] = current_image
        end
      end
      return matches
    end

    provider.on_win(nil, 10, 100, 0, 10)
    current_buffer = 200
    scheduled[1]()

    assert.are.same(1, #render_calls)
    assert.are.same("current-buffer", render_calls[1].id)
  end)

  it("skips queued rerenders when the window has switched again", function()
    local utils = require("image/utils")
    local image = require("image")
    local provider
    local scheduled = {}
    local current_buffer = 100
    local render_calls = {}

    vim.api.nvim_get_mode = function()
      return { mode = "n" }
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_height = function()
      return 20
    end
    vim.api.nvim_win_get_buf = function()
      return current_buffer
    end
    vim.api.nvim_set_decoration_provider = function(_, opts)
      provider = opts
    end
    utils.window.get_windows = function()
      return {}
    end
    utils.window.get_window = function()
      return {
        is_visible = true,
        is_floating = false,
        masks = {},
        rect = { top = 0, right = 80, bottom = 20, left = 0 },
      }
    end

    image.setup({
      integrations = disabled_integrations,
    })

    local old_buffer_image = {
      id = "old-buffer",
      window = 10,
      buffer = 100,
      namespace = "markdown",
      is_rendered = true,
      clear = function() end,
      render = function() end,
    }
    local switched_buffer_image = {
      id = "switched-buffer",
      window = 10,
      buffer = 200,
      namespace = "markdown",
      is_rendered = false,
      clear = function() end,
      render = function()
        render_calls[#render_calls + 1] = { id = "switched-buffer" }
      end,
    }

    image.get_images = function(opts)
      local images = { old_buffer_image, switched_buffer_image }
      local matches = {}
      for _, current_image in ipairs(images) do
        if
          not opts
          or (
            (not opts.window or opts.window == current_image.window)
            and (not opts.buffer or opts.buffer == current_image.buffer)
            and (not opts.namespace or opts.namespace == current_image.namespace)
          )
        then
          matches[#matches + 1] = current_image
        end
      end
      return matches
    end

    vim.schedule = function(callback)
      callback()
    end
    provider.on_win(nil, 10, 100, 0, 10)
    provider.on_win(nil, 10, 100, 0, 10)

    vim.schedule = function(callback)
      scheduled[#scheduled + 1] = callback
    end
    current_buffer = 200
    provider.on_win(nil, 10, 200, 0, 10)
    current_buffer = 300
    scheduled[1]()

    assert.are.same(0, #render_calls)
  end)
end)
