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
  rst = { enabled = false },
  syslang = { enabled = false },
  html = { enabled = false },
  css = { enabled = false },
  org = { enabled = false },
}

describe("focus-aware rendering", function()
  local originals
  local render_calls
  local backend_state

  before_each(function()
    unload_image_modules()
    originals = {
      create_autocmd = vim.api.nvim_create_autocmd,
      schedule = vim.schedule,
      schedule_wrap = vim.schedule_wrap,
      uv = vim.uv,
    }
    render_calls = {}
    backend_state = nil
    if not vim.uv then vim.uv = vim.loop end

    package.loaded["image/renderer"] = {
      render = function(image)
        render_calls[#render_calls + 1] = image.id
        image.global_state.images[image.id] = image
        image.is_rendered = true
        return true
      end,
      clear_cache_for_path = function() end,
    }
    package.loaded["image/backends/kitty"] = {
      features = { crop = true },
      setup = function(state)
        backend_state = state
      end,
      clear = function(id, shallow)
        local image = backend_state.images[id]
        if not image then return end
        image.is_rendered = false
        if not shallow then backend_state.images[id] = nil end
      end,
      render = function(image)
        image.is_rendered = true
        backend_state.images[image.id] = image
      end,
    }
  end)

  after_each(function()
    vim.api.nvim_create_autocmd = originals.create_autocmd
    vim.schedule = originals.schedule
    vim.schedule_wrap = originals.schedule_wrap
    vim.uv = originals.uv
    pcall(vim.api.nvim_del_augroup_by_name, "image.nvim")
    local namespace = vim.api.nvim_get_namespaces()["image.nvim"]
    if namespace then pcall(vim.api.nvim_set_decoration_provider, namespace, {}) end
    unload_image_modules()
  end)

  it("keeps images hidden while unfocused and restores them on focus gain", function()
    local focus_lost
    local focus_gained
    vim.schedule = function(callback)
      callback()
    end
    vim.schedule_wrap = function(callback)
      return callback
    end
    vim.api.nvim_create_autocmd = function(events, options)
      if events == "FocusLost" then focus_lost = options.callback end
      if events == "FocusGained" then focus_gained = options.callback end
      return originals.create_autocmd(events, options)
    end

    local image = require("image")
    image.setup({
      editor_only_render_when_focused = true,
      integrations = disabled_integrations,
      hijack_file_patterns = {},
    })
    vim.api.nvim_create_autocmd = originals.create_autocmd

    local current_image = image.from_file("tests/test_data/100x100.png")
    current_image:render()
    assert.are.same(1, #render_calls)

    focus_lost()
    current_image:render()
    assert.are.same(1, #render_calls)

    focus_gained()
    assert.are.same(2, #render_calls)
  end)
end)
