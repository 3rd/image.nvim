local unload_image_modules = function()
  for module_name in pairs(package.loaded) do
    if module_name == "image" or module_name:match("^image/") then package.loaded[module_name] = nil end
  end
end

describe("image source refresh", function()
  local original_uv
  local source_path
  local clear_calls
  local cache_clear_calls
  local dimension_calls
  local render_calls

  before_each(function()
    unload_image_modules()
    original_uv = vim.uv
    if not vim.uv then vim.uv = vim.loop end

    clear_calls = 0
    cache_clear_calls = 0
    dimension_calls = 0
    render_calls = 0
    package.loaded["image/renderer"] = {
      render = function(image)
        render_calls = render_calls + 1
        image.global_state.images[image.id] = image
        image.is_rendered = true
        return true
      end,
      clear_cache_for_path = function()
        cache_clear_calls = cache_clear_calls + 1
      end,
    }

    source_path = vim.fn.tempname()
    local file = assert(io.open(source_path, "wb"))
    file:write("\x89PNG\r\n\x1A\nfirst")
    file:close()
  end)

  after_each(function()
    vim.uv = original_uv
    if source_path then vim.fn.delete(source_path) end
    unload_image_modules()
  end)

  it("refreshes a changed source even when the second-resolution mtime is unchanged", function()
    local image_module = require("image/image")
    local state
    state = {
      enabled = true,
      rendering_paused = false,
      images = {},
      extmarks_namespace = vim.api.nvim_create_namespace("image-refresh-test"),
      processor = {
        get_format = function()
          return "png"
        end,
        get_dimensions = function()
          dimension_calls = dimension_calls + 1
          return { width = 2, height = 2 }
        end,
      },
      backend = {
        clear = function(id, shallow)
          clear_calls = clear_calls + 1
          local image = state.images[id]
          if image then
            image.is_rendered = false
            if not shallow then state.images[id] = nil end
          end
        end,
      },
    }

    local image = image_module.from_file(source_path, nil, state)
    image:render()
    assert.are.same(1, dimension_calls)
    assert.are.same(1, render_calls)
    assert.are.same(0, clear_calls)

    local original_mtime_seconds = vim.fn.getftime(source_path)
    local original_stat = assert(vim.uv.fs_stat(source_path))
    local file = assert(io.open(source_path, "wb"))
    file:write("\x89PNG\r\n\x1A\nother")
    file:close()
    local updated_stat = assert(vim.uv.fs_stat(source_path))
    assert.are.same(original_stat.size, updated_stat.size)
    local changed_mtime_nsec = original_stat.mtime.nsec == 250000000 and 750000000 or 250000000
    assert.is_true(
      vim.uv.fs_utime(source_path, original_stat.atime.sec, original_stat.mtime.sec + changed_mtime_nsec / 1000000000)
    )
    local changed_stat = assert(vim.uv.fs_stat(source_path))
    assert.are.same(original_stat.mtime.sec, changed_stat.mtime.sec)
    assert.are.same(false, original_stat.mtime.nsec == changed_stat.mtime.nsec)
    assert.are.same(original_mtime_seconds, vim.fn.getftime(source_path))

    local reloaded_image = image_module.from_file(source_path, nil, state)
    assert.are.same(false, image == reloaded_image)
    assert.are.same(false, image.source_signature == reloaded_image.source_signature)
    assert.are.same(2, dimension_calls)

    image:render()
    assert.are.same(3, dimension_calls)
    assert.are.same(2, render_calls)
    assert.are.same(1, clear_calls)
    assert.are.same(1, cache_clear_calls)
  end)
end)
