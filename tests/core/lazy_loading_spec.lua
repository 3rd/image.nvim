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

local unload_image_modules = function()
  for module_name in pairs(package.loaded) do
    if module_name == "image" or module_name:match("^image/") then package.loaded[module_name] = nil end
  end
end

local setup_image = function(options)
  unload_image_modules()
  local image = require("image")
  image.setup(vim.tbl_deep_extend("force", {
    integrations = disabled_integrations,
  }, options or {}))
  return image
end

local with_missing_magick = function(callback)
  unload_image_modules()
  local loaded_magick = package.loaded["magick"]
  local preload_magick = package.preload["magick"]
  package.loaded["magick"] = nil
  package.preload["magick"] = function()
    error("missing magick sentinel")
  end

  local ok, err = pcall(callback)
  package.loaded["magick"] = loaded_magick
  package.preload["magick"] = preload_magick
  unload_image_modules()
  if not ok then error(err) end
end

local capture_error_writes = function(callback)
  local err_writeln = vim.api.nvim_err_writeln
  local messages = {}
  vim.api.nvim_err_writeln = function(message)
    table.insert(messages, message)
  end

  local ok, err = pcall(callback, messages)
  vim.api.nvim_err_writeln = err_writeln
  if not ok then error(err) end
  return messages
end

describe("lazy loading", function()
  after_each(function()
    unload_image_modules()
  end)

  it("does not load configured processor or backend during setup", function()
    setup_image({
      backend = "kitty",
      processor = "magick_rock",
    })

    assert.is_nil(package.loaded["image/processors/magick_rock"])
    assert.is_nil(package.loaded["image/magick"])
    assert.is_nil(package.loaded["image/backends/kitty"])
  end)

  it("checks magick rock availability after setup without loading the processor", function()
    setup_image({
      backend = "kitty",
      processor = "magick_rock",
    })

    assert.is_true(vim.wait(1000, function()
      return package.loaded["image/magick"] ~= nil
    end))
    assert.is_nil(package.loaded["image/processors/magick_rock"])
    assert.is_nil(package.loaded["image/backends/kitty"])
  end)

  it("uses the setup warning message for first-use magick rock failures", function()
    with_missing_magick(function()
      local messages = capture_error_writes(function(messages)
        setup_image({
          backend = "kitty",
          processor = "magick_rock",
        })

        assert.is_true(vim.wait(1000, function()
          return #messages == 1
        end))

        local processor = require("image/processors/magick_rock")
        local ok, err = pcall(processor.convert_to_png, "tests/test_data/100x100.png", "unused.png")

        assert.is_false(ok)
        assert.is_not_nil(tostring(err):find(messages[1], 1, true))
      end)

      assert.is_equal(messages[1], messages[2])
    end)
  end)

  it("validates processor and backend names during setup", function()
    assert.has_error(function()
      setup_image({ processor = "missing" })
    end, "image.nvim: processor not found: missing")

    assert.has_error(function()
      setup_image({ backend = "missing" })
    end, "image.nvim: backend not found: missing")
  end)

  it("loads the processor on first image creation", function()
    local image = setup_image({
      backend = "sixel",
      processor = "magick_cli",
    })

    assert.is_nil(package.loaded["image/processors/magick_cli"])
    assert.is_not_nil(image.from_file("tests/test_data/100x100.png"))
    assert.is_not_nil(package.loaded["image/processors/magick_cli"])
    assert.is_nil(package.loaded["image/backends/sixel"])
  end)

  it("loads and sets up the backend on first backend use", function()
    local image = setup_image({
      backend = "sixel",
      processor = "magick_cli",
    })

    assert.is_nil(package.loaded["image/backends/sixel"])
    image.clear("missing")
    assert.is_not_nil(package.loaded["image/backends/sixel"])
    assert.is_not_nil(require("image/backends/sixel").state)
  end)
end)
