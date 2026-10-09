local unload_image_modules = function()
  for name in pairs(package.loaded) do
    if name == "image" or name:match("^image/") then package.loaded[name] = nil end
  end
end

describe("tab switching with API images", function()
  local api
  local original_tab
  local original_buffer
  local saved_modules
  local autocmd_ids
  local tmp_dir

  local flush = function()
    vim.wait(20, function()
      return false
    end)
  end

  local make_image = function(id, opts)
    local img = assert(api.from_file(
      "tests/test_data/100x100.png",
      vim.tbl_extend("force", {
        id = id,
        window = vim.api.nvim_get_current_win(),
        buffer = vim.api.nvim_get_current_buf(),
        x = 0,
        y = 0,
        width = 5,
        height = 3,
      }, opts or {})
    ))
    tmp_dir = img.global_state.tmp_dir
    img:render()
    assert.is_true(vim.wait(200, function()
      return img.is_rendered
    end))
    return img
  end

  before_each(function()
    saved_modules = {}
    for name, module in pairs(package.loaded) do
      if name == "image" or name:match("^image/") then saved_modules[name] = module end
    end
    unload_image_modules()
    autocmd_ids = {}
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
      if autocmd.id then autocmd_ids[autocmd.id] = true end
    end
    original_tab = vim.api.nvim_get_current_tabpage()
    original_buffer = vim.api.nvim_get_current_buf()
    vim.cmd("tabnew")

    -- Keep real windows, autocommands, Image objects, renderer, and Kitty backend.
    -- Only terminal I/O and ImageMagick are replaced for headless CI.
    package.loaded["image/utils/term"] = {
      get_size = function()
        return { cell_width = 8, cell_height = 16, screen_cols = 80, screen_rows = 24 }
      end,
      get_tty = function() end,
    }
    package.loaded["image/backends/kitty/helpers"] = setmetatable({}, {
      __index = function()
        return function() end
      end,
    })
    package.loaded["image/processors/magick_cli"] = {
      get_format = function()
        return "png"
      end,
      get_dimensions = function()
        return { width = 100, height = 100 }
      end,
      transform = function(path, _, output_path, complete)
        assert(vim.uv.fs_copyfile(path, output_path))
        complete({ ok = true, path = output_path })
      end,
    }
    local integrations = {}
    for _, name in ipairs({ "markdown", "asciidoc", "typst", "neorg", "syslang", "html", "css", "org" }) do
      integrations[name] = { enabled = false }
    end
    api = require("image")
    api.setup({ backend = "kitty", processor = "magick_cli", integrations = integrations })
  end)

  after_each(function()
    api.disable()
    flush()
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
      if autocmd.id and not autocmd_ids[autocmd.id] then pcall(vim.api.nvim_del_autocmd, autocmd.id) end
    end
    vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace("image.nvim"), {})
    vim.api.nvim_set_current_tabpage(original_tab)
    vim.cmd("silent tabonly!")
    vim.api.nvim_set_current_buf(original_buffer)
    if tmp_dir then vim.fn.delete(tmp_dir, "rf") end
    tmp_dir = nil
    unload_image_modules()
    for name, module in pairs(saved_modules) do
      package.loaded[name] = module
    end
  end)

  it("retains and restores a bound image and its virtual padding when returning to its tab", function()
    local img = make_image("tab-image", { with_virtual_padding = true })
    vim.cmd("tabnew")
    flush()
    assert.is_false(img.is_rendered)
    assert.are.same({ img }, api.get_images())

    vim.cmd("tabclose")
    flush()
    assert.is_true(img.is_rendered)
    assert.are.same({ img }, api.get_images())
    local marks =
      vim.api.nvim_buf_get_extmarks(img.buffer, img.global_state.extmarks_namespace, 0, -1, { details = true })
    assert.are.same(1, #marks)
    assert.is_true(#marks[1][4].virt_lines > 0)
  end)

  it("restores an image bound to a window without a buffer", function()
    local img = make_image("window-only", { buffer = false })
    vim.cmd("tabnew")
    flush()
    assert.is_false(img.is_rendered)
    assert.are.same({ img }, api.get_images())
    vim.cmd("tabclose")
    flush()
    assert.is_true(img.is_rendered)
  end)

  it("hides every image in the old tab and restores only the current tab", function()
    local first_tab = vim.api.nvim_get_current_tabpage()
    local images = { make_image("first"), make_image("second"), make_image("third") }
    vim.cmd("tabnew")
    flush()
    for _, img in ipairs(images) do
      assert.is_false(img.is_rendered)
    end
    assert.are.same(3, #api.get_images())
    local other = make_image("other-tab")

    vim.api.nvim_set_current_tabpage(first_tab)
    flush()
    for _, img in ipairs(images) do
      assert.is_true(img.is_rendered)
    end
    assert.is_false(other.is_rendered)
    assert.are.same(4, #api.get_images())
  end)

  it("removes every image whose window has been closed", function()
    for i = 1, 6 do
      make_image("image-" .. i)
    end
    vim.cmd("tabclose")
    flush()
    assert.are.same({}, api.get_images())
  end)

  it("does not restore an image explicitly cleared by the caller", function()
    local img = make_image("cleared")
    img:clear()
    vim.cmd("tabnew")
    flush()
    vim.cmd("tabclose")
    flush()
    assert.is_false(img.is_rendered)
    assert.are.same({}, api.get_images())
  end)
end)
