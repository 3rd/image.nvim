local unload_modules = function()
  package.loaded["image/renderer"] = nil
  package.loaded["image/utils/transform_cache"] = nil
end

local notify = vim.notify
vim.notify = function() end

local utils = require("image/utils")

vim.notify = notify

describe("renderer transform pipeline", function()
  local originals
  local renderer
  local scheduled
  local temp_path
  local output_paths

  local make_image = function(opts)
    local calls = {}
    local completions = {}
    local state
    state = {
      options = {
        processor = "stub",
        scale_factor = 1,
        window_overlap_clear_enabled = false,
        window_overlap_clear_ft_ignore = {},
      },
      images = {},
      backend = {
        features = { crop = opts.backend_crop ~= false },
        clear = function() end,
        render = function(image, x, y, width, height)
          calls[#calls + 1] = {
            path = image.cropped_path,
            x = x,
            y = y,
            width = width,
            height = height,
          }
          image.is_rendered = true
          state.images[image.id] = image
        end,
      },
      processor = {
        transform = function(_, _, output_path, complete)
          output_paths[#output_paths + 1] = output_path
          completions[#completions + 1] = function()
            vim.fn.writefile({ "output" }, output_path)
            complete({ ok = true, path = output_path })
          end
        end,
      },
      tmp_dir = "/tmp",
    }

    local image = {
      id = opts.id or "transform-test",
      internal_id = 1,
      path = temp_path,
      original_path = temp_path,
      source_format = opts.source_format or "png",
      image_width = opts.image_width or 10,
      image_height = opts.image_height or 10,
      global_state = state,
      geometry = {
        x = 2,
        y = 3,
        width = opts.width or 5,
        height = opts.height or 5,
      },
      rendered_geometry = {},
      is_rendered = opts.is_rendered or false,
    }

    image.render = function(self)
      return renderer.render(self)
    end

    return image, calls, completions
  end

  before_each(function()
    unload_modules()
    renderer = require("image/renderer")
    temp_path = vim.fn.tempname()
    vim.fn.writefile({ "source" }, temp_path)
    output_paths = {}
    scheduled = {}
    originals = {
      get_size = utils.term.get_size,
      schedule = vim.schedule,
    }
    utils.term.get_size = function()
      return {
        cell_width = 1,
        cell_height = 1,
        screen_cols = 80,
        screen_rows = 40,
      }
    end
    vim.schedule = function(callback)
      scheduled[#scheduled + 1] = callback
    end
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    vim.schedule = originals.schedule
    renderer.clear_cache_for_path(temp_path)
    vim.fn.delete(temp_path)
    for _, path in ipairs(output_paths) do
      vim.fn.delete(path)
    end
    unload_modules()
  end)

  it("queues missing transforms and renders after completion", function()
    local image, calls, completions = make_image({})

    assert.is_false(renderer.render(image))
    assert.are.same(0, #calls)
    assert.are.same(1, #completions)
    assert.are.same("string", type(image.pending_transform_key))

    completions[1]()
    assert.are.same(1, #scheduled)
    scheduled[1]()

    assert.are.same(1, #calls)
    assert.are.same(5, calls[1].width)
    assert.are.same(5, calls[1].height)
    assert.are.same(nil, image.pending_transform_key)
  end)

  it("ignores stale transform completions", function()
    local image, calls, completions = make_image({})

    assert.is_false(renderer.render(image))
    image.pending_transform_key = "newer-request"

    completions[1]()
    scheduled[1]()

    assert.are.same(0, #calls)
  end)

  it("renders the latest image owner when repeated scans share a pending transform", function()
    local image, calls, completions = make_image({
      id = "shared-transform",
    })

    assert.is_false(renderer.render(image))

    local newer_image = {
      id = image.id,
      internal_id = 2,
      path = temp_path,
      original_path = temp_path,
      source_format = "png",
      image_width = image.image_width,
      image_height = image.image_height,
      global_state = image.global_state,
      geometry = {
        x = 12,
        y = 3,
        width = 5,
        height = 5,
      },
      rendered_geometry = {},
      is_rendered = false,
    }
    newer_image.render = function(self)
      return renderer.render(self)
    end

    assert.is_false(renderer.render(newer_image))
    assert.are.same(1, #completions)

    completions[1]()
    scheduled[1]()

    assert.are.same(1, #calls)
    assert.are.same(12, calls[1].x)
    assert.are.same(newer_image, image.global_state.images[image.id])
  end)

  it("keeps an already rendered image visible while a new transform is pending", function()
    local image, calls, completions = make_image({
      is_rendered = true,
    })
    image.rendered_geometry = { x = 2, y = 3, width = 10, height = 10 }

    assert.is_true(renderer.render(image))
    assert.are.same(1, #completions)
    assert.are.same("string", type(image.pending_transform_key))
    assert.are.same(0, #calls)
  end)

  it("queues format conversion even when size does not change", function()
    local image, calls, completions = make_image({
      image_width = 5,
      image_height = 5,
      source_format = "jpeg",
    })

    assert.is_false(renderer.render(image))
    assert.are.same(0, #calls)
    assert.are.same(1, #completions)
  end)
end)
